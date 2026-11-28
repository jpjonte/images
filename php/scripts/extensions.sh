#!/usr/bin/env sh

set -eu

# mbstring is built into the official images only up to PHP 8.5; from 8.6 it
# must be installed like any other extension. install-php-extensions skips it
# where it is already present.
install-php-extensions @composer \
  mbstring \
  exif \
  pcntl \
  bcmath \
  intl \
  opcache \
  pdo_pgsql \
  pgsql \
  zip \
  gmp \
  gd

# Non-bundled extensions come from PIE instead of PECL. Build tools and -dev
# packages are removed again afterwards; the runtime libraries stay. redis links
# the system liblzf because the source archive PIE downloads lacks the bundled
# liblzf git submodule.
apk add --no-cache liblzf zstd-libs lz4-libs
apk add --no-cache --virtual .pie-deps $PHPIZE_DEPS libtool liblzf-dev zstd-dev lz4-dev

# apcu 5.1.28, pcov 1.0.12 and phpredis 6.3.0 do not build on PHP 8.6. The
# fixes are merged upstream (krakjoe/apcu#629, krakjoe/pcov#134) or in a release
# candidate (phpredis 6.4.0RC1), so 8.6 installs those instead. Drop this once
# apcu 5.1.29, pcov 1.0.13 and phpredis 6.4.0 are released.
if [ "$(php -r 'echo PHP_VERSION_ID >= 80600 ? 1 : 0;')" = 1 ]; then
  pie install --no-cache 'apcu/apcu:dev-master#fb2c942552a3f5dab7f4dea4afb5cf0831222c57'
  pie install --no-cache 'pecl/pcov:dev-develop#3795c08561d69ca7f55f693492de59a65a6a182d'
  redis=phpredis/phpredis:6.4.0RC1
else
  pie install --no-cache \
    apcu/apcu \
    pecl/pcov
  redis=phpredis/phpredis
fi

pie install --no-cache "$redis" \
  --enable-redis-lzf --with-liblzf=/usr \
  --enable-redis-zstd --with-libzstd=/usr \
  --enable-redis-lz4 --with-liblz4=/usr

# PIE leaves debug symbols in; install-php-extensions strips its builds.
strip --strip-unneeded "$(php-config --extension-dir)"/apcu.so \
  "$(php-config --extension-dir)"/pcov.so \
  "$(php-config --extension-dir)"/redis.so

apk del .pie-deps

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
