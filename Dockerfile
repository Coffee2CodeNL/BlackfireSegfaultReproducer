FROM dunglas/frankenphp:1-php8.3 AS frankenphp_upstream

FROM frankenphp_upstream AS frankenphp_real_base

RUN set -eux; \
	install-php-extensions  \
	@composer \
	igbinary  \
	mbstring  \
	zip  \
	opcache  \
	pdo_mysql  \
	pcntl  \
	soap \
	redis \
	gd \
	intl \
	sysvsem \
	;

RUN version=$(php -r "echo PHP_MAJOR_VERSION.PHP_MINOR_VERSION.'-zts';") \
	&& architecture=$(uname -m) \
	&& curl -A "Docker" -o /tmp/blackfire-probe.tar.gz -D - -L -s https://blackfire.io/api/v1/releases/probe/php/linux/$architecture/$version \
	&& mkdir -p /tmp/blackfire \
	&& tar zxpf /tmp/blackfire-probe.tar.gz -C /tmp/blackfire \
	&& mv /tmp/blackfire/blackfire-*.so $(php -r "echo ini_get ('extension_dir');")/blackfire.so \
	&& printf "extension=blackfire.so\nblackfire.agent_socket=tcp://blackfire:8307\nblackfire.debug.sigsegv_handler=1\nblackfire.log_file=/efs/blackfire.log" > $PHP_INI_DIR/conf.d/blackfire.ini \
	&& rm -rf /tmp/blackfire /tmp/blackfire-probe.tar.gz

COPY --link index.php index.php
COPY --link Caddyfile /etc/frankenphp/Caddyfile
COPY --link --chmod=755 docker-entrypoint.sh /usr/local/bin/docker-entrypoint

COPY php_pdflib_83_ts.so /var/php_pdflib.so
RUN export configdir=$(php-config --extension-dir) \
	&& mv /var/php_pdflib.so $configdir/php_pdflib.so

COPY app.ini $PHP_INI_DIR/conf.d/10-app.ini

ENTRYPOINT ["docker-entrypoint"]
HEALTHCHECK --start-period=60s CMD curl -f http://localhost:2019/metrics || exit 1
CMD [ "frankenphp", "run", "--config", "/etc/frankenphp/Caddyfile" ]