Blackfire x PDFLib x FrankenPHP Segfault Reproducer
======

## Versions

|  PHP   |        Blackfire        |  PDFlib  | FrankenPHP | Caddy   |
|--------|-------------------------|----------|------------|---------|
| 8.3.26 | 1.92.44~linux-x64-zts83 | 10.0.3p2 |   v1.9.1   | v2.10.2 |

## How to reproduce

1. Start docker container
    ```shell
    docker compose up -d
    ```
2. Tail the log
    ```shell
    docker compose logs -f php
    ```
3. Open `https://localhost:8888` in your browser
4. Observe segfault in the logs

