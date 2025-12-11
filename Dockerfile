#syntax=docker/dockerfile:1

FROM dunglas/frankenphp:1.9-builder-php8.4.14 AS frankenphp_builder
COPY --from=caddy:2.10.2-builder /usr/bin/xcaddy /usr/bin/xcaddy

RUN apt-get update && \
	apt-get install --no-install-recommends -y \
	git

RUN CGO_ENABLED=1 \
	XCADDY_SETCAP=1 \
	XCADDY_GO_BUILD_FLAGS="-ldflags='-w -s' -tags=nobadger,nomysql,nopgx" \
	CGO_CFLAGS="$(php-config --includes)" \
	CGO_LDFLAGS="$(php-config --ldflags) $(php-config --libs)" \
	xcaddy build \
	    --output /usr/local/bin/frankenphp \
	    --with github.com/dunglas/frankenphp/caddy \
    	--with github.com/dunglas/mercure/caddy \
    	--with github.com/dunglas/vulcain/caddy \
    	--with github.com/dunglas/caddy-cbrotli

# Versions
FROM dunglas/frankenphp:1-php8.4 AS frankenphp_upstream
COPY --from=frankenphp_builder --link /usr/local/bin/frankenphp /usr/local/bin/frankenphp


# The different stages of this Dockerfile are meant to be built into separate images
# https://docs.docker.com/develop/develop-images/multistage-build/#stop-at-a-specific-build-stage
# https://docs.docker.com/compose/compose-file/#target


# Base FrankenPHP image
FROM frankenphp_upstream AS frankenphp_base

WORKDIR /app

VOLUME /app/var/

# persistent / runtime deps
# hadolint ignore=DL3008
RUN apt-get update && apt-get install -y --no-install-recommends \
    acl \
	file \
    gettext \
	git \
    locales \
    && locale-gen en_US.UTF-8 \
    && update-locale \
	&& rm -rf /var/lib/apt/lists/*

RUN set -eux; \
	install-php-extensions \
		@composer \
		bcmath \
		gmp \
		igbinary \
		intl \
		mbstring \
		opcache \
		pcntl \
		redis \
		sodium \
		xsl \
		zip \
	;

# https://getcomposer.org/doc/03-cli.md#composer-allow-superuser
ENV COMPOSER_ALLOW_SUPERUSER=1

ENV PHP_INI_SCAN_DIR=":$PHP_INI_DIR/app.conf.d"

###> recipes ###
###> doctrine/doctrine-bundle ###
RUN install-php-extensions pdo_pgsql
###< doctrine/doctrine-bundle ###
###< recipes ###

RUN version=$(php -r "echo PHP_MAJOR_VERSION.PHP_MINOR_VERSION.'-zts';") \
	&& architecture=$(uname -m) \
	&& curl -A "Docker" -o /tmp/blackfire-probe.tar.gz -D - -L -s https://blackfire.io/api/v1/releases/probe/php/linux/$architecture/$version \
	&& mkdir -p /tmp/blackfire \
	&& tar zxpf /tmp/blackfire-probe.tar.gz -C /tmp/blackfire \
	&& mv /tmp/blackfire/blackfire-*.so $(php -r "echo ini_get ('extension_dir');")/blackfire.so \
	&& printf "extension=blackfire.so\nblackfire.agent_socket=tcp://blackfire:8307\nblackfire.debug.sigsegv_handler=1\nblackfire.log_level=4\nblackfire.log_file=/var/log/blackfire.log\nblackfire.apm_enabled=0" > $PHP_INI_DIR/conf.d/blackfire.ini \
	&& rm -rf /tmp/blackfire /tmp/blackfire-probe.tar.gz

COPY --link frankenphp/conf.d/10-app.ini $PHP_INI_DIR/app.conf.d/
COPY --link --chmod=755 frankenphp/docker-entrypoint.sh /usr/local/bin/docker-entrypoint
COPY --link frankenphp/Caddyfile /etc/frankenphp/Caddyfile
COPY --link --chmod=755 count_log_lines.sh /usr/local/bin/count-log-lines

ENTRYPOINT ["docker-entrypoint"]

HEALTHCHECK --start-period=60s CMD curl -f http://localhost:2019/metrics || exit 1
CMD [ "frankenphp", "run", "--config", "/etc/frankenphp/Caddyfile" ]

# Dev FrankenPHP image
FROM frankenphp_base AS frankenphp_dev

ENV APP_ENV=dev
ENV XDEBUG_MODE=off
ENV FRANKENPHP_WORKER_CONFIG=watch

RUN mv "$PHP_INI_DIR/php.ini-development" "$PHP_INI_DIR/php.ini"

RUN set -eux; \
	install-php-extensions \
		xdebug \
	;

COPY --link frankenphp/conf.d/20-app.dev.ini $PHP_INI_DIR/app.conf.d/

CMD [ "frankenphp", "run", "--config", "/etc/frankenphp/Caddyfile", "--watch" ]

# Prod FrankenPHP image
FROM frankenphp_base AS frankenphp_prod

ENV APP_ENV=prod

RUN mv "$PHP_INI_DIR/php.ini-production" "$PHP_INI_DIR/php.ini"

COPY --link frankenphp/conf.d/20-app.prod.ini $PHP_INI_DIR/app.conf.d/

# prevent the reinstallation of vendors at every changes in the source code
COPY --link composer.* symfony.* ./
RUN set -eux; \
	composer install --no-cache --prefer-dist --no-dev --no-autoloader --no-scripts --no-progress

# copy sources
COPY --link --exclude=frankenphp/ . ./

RUN set -eux; \
	mkdir -p var/cache var/log; \
	composer dump-autoload --classmap-authoritative --no-dev; \
	composer dump-env prod; \
	composer run-script --no-dev post-install-cmd; \
	chmod +x bin/console; sync;
