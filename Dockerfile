# Runtime for the mbn-cms sites: PHP 7.4 + psr 1.1.0 + Phalcon 4.1.0 (matches web102 php7.4 pools)
# plus nginx in the same container. A site image only adds its source:
#   FROM ghcr.io/vinadesign-365/php-phalcon-base:7.4-4.1.0
#   COPY . /var/www/app
FROM php:7.4-fpm-bullseye

ENV TZ=Asia/Ho_Chi_Minh \
    FPM_MAX_CHILDREN=10

# Bullseye is moving to archive.debian.org (mirror returns 404); apt-install falls back to the archive.
COPY apt-install.sh /usr/local/bin/apt-install
RUN chmod 755 /usr/local/bin/apt-install

RUN savedAptMark="$(apt-mark showmanual)" \
    && apt-install \
        libfreetype6-dev libjpeg62-turbo-dev libpng-dev libzip-dev libicu-dev libmagickwand-dev libonig-dev \
    && docker-php-ext-configure gd --with-freetype --with-jpeg \
    && docker-php-ext-install -j"$(nproc)" gd zip intl exif pdo_mysql mysqli opcache mbstring \
    && pecl install apcu-5.1.19 imagick-3.7.0 redis-5.3.7 psr-1.1.0 \
    && docker-php-ext-enable apcu imagick redis psr \
    && MAKEFLAGS="-j$(nproc)" pecl install phalcon-4.1.0 \
    && docker-php-ext-enable phalcon \
    && rm -rf /tmp/pear \
    # phalcon must load after psr
    && mv /usr/local/etc/php/conf.d/docker-php-ext-phalcon.ini /usr/local/etc/php/conf.d/zz-docker-php-ext-phalcon.ini \
    && apt-mark auto '.*' > /dev/null && apt-mark manual $savedAptMark > /dev/null \
    && find /usr/local -type f -name '*.so*' -exec ldd '{}' ';' \
        | awk '/=>/ { print $3 }' | sort -u | xargs -r dpkg-query --search 2>/dev/null \
        | cut -d: -f1 | sort -u | xargs -r apt-mark manual \
    && apt-get purge -y --auto-remove -o APT::AutoRemove::RecommendsImportant=false \
    && rm -rf /var/lib/apt/lists/* \
    && php -r 'echo "phalcon ", Phalcon\Version::get(), PHP_EOL;'

RUN apt-install nginx \
    && rm -rf /var/lib/apt/lists/* /etc/nginx/sites-enabled /etc/nginx/sites-available /etc/nginx/conf.d/* /var/www/html

COPY php/php.ini /usr/local/etc/php/conf.d/zz-prod.ini
COPY php/www.conf /usr/local/etc/php-fpm.d/www.conf
COPY nginx/nginx.conf /etc/nginx/nginx.conf
COPY nginx/site.conf /etc/nginx/conf.d/site.conf
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
# docker.conf ships an fpm access log that duplicates nginx; drop it.
RUN rm -f /usr/local/etc/php-fpm.d/zz-docker.conf /usr/local/etc/php-fpm.d/www.conf.default \
    && sed -i '/^access\.log/d' /usr/local/etc/php-fpm.d/docker.conf \
    && chmod 755 /usr/local/bin/entrypoint.sh \
    && mkdir -p /var/lib/php/sessions /var/www/app \
    && chown www-data:www-data /var/lib/php/sessions \
    && php-fpm -t && nginx -t

WORKDIR /var/www/app
EXPOSE 80
HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
    CMD php -r 'exit(@file_get_contents("http://127.0.0.1/healthz") === "ok" ? 0 : 1);'
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
