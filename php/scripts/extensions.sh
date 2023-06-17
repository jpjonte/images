#!/usr/bin/env bash

set -euo pipefail

apk --update --no-cache add \
  bzip2 \
  bzip2-dev \
  freetype-dev \
  gmp-dev \
  icu-dev \
  imagemagick \
  imagemagick-dev \
  imap-dev \
  krb5-dev \
  libintl \
  libjpeg-turbo-dev \
  libmemcached-dev \
  libpng-dev \
  libxml2-dev \
  libxslt-dev \
  pcre-dev \
  postgresql-dev \
  zlib-dev \
  libzip-dev \
  libsodium-dev

PHP_OPENSSL=yes docker-php-ext-configure imap --with-kerberos --with-imap-ssl
docker-php-ext-install -j "$(nproc)" imap
docker-php-ext-install -j "$(nproc)" exif \
  pcntl \
  bcmath \
  bz2 \
  calendar \
  intl \
  mysqli \
  opcache \
  pdo_mysql \
  pdo_pgsql \
  pgsql \
  soap \
  xsl \
  zip \
  gmp
docker-php-source delete
docker-php-ext-configure gd --with-freetype --with-jpeg
docker-php-ext-install -j "$(nproc)" gd

apk add --no-cache --virtual .pgsql-deps postgresql-dev; \
	docker-php-ext-install -j$(nproc) pdo_pgsql; \
	apk add --no-cache --virtual .pgsql-rundeps so:libpq.so.5; \
	apk del .pgsql-deps

docker-php-source extract \
    && apk add --no-cache --virtual .phpize-deps-configure $PHPIZE_DEPS \
    && pecl install apcu \
    && docker-php-ext-enable apcu \
    && apk del .phpize-deps-configure \
    && docker-php-source delete

#Imagick
mkdir /usr/local/src \
  && cd /usr/local/src \
  && git clone https://github.com/Imagick/imagick \
  && cd imagick \
  && phpize \
  && ./configure \
  && make \
  && make install \
  && cd .. \
  && rm -rf imagick \
  && docker-php-ext-enable imagick

pecl install redis \
  &&  docker-php-ext-enable redis

{ \
    echo 'opcache.enable=1'; \
    echo 'opcache.revalidate_freq=0'; \
    echo 'opcache.validate_timestamps=1'; \
    echo 'opcache.max_accelerated_files=10000'; \
    echo 'opcache.memory_consumption=192'; \
    echo 'opcache.max_wasted_percentage=10'; \
    echo 'opcache.interned_strings_buffer=16'; \
    echo 'opcache.fast_shutdown=1'; \
} > /usr/local/etc/php/conf.d/opcache-recommended.ini

{ \
    echo 'apc.shm_segments=1'; \
    echo 'apc.shm_size=512M'; \
    echo 'apc.num_files_hint=7000'; \
    echo 'apc.user_entries_hint=4096'; \
    echo 'apc.ttl=7200'; \
    echo 'apc.user_ttl=7200'; \
    echo 'apc.gc_ttl=3600'; \
    echo 'apc.max_file_size=50M'; \
    echo 'apc.stat=1'; \
} > /usr/local/etc/php/conf.d/apcu-recommended.ini

echo "memory_limit=1G" > /usr/local/etc/php/conf.d/zz-conf.ini
