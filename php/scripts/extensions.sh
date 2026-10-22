#!/usr/bin/env sh

set -eu

install-php-extensions @composer \
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

pie install --no-cache \
  apcu/apcu \
  pecl/pcov

pie install --no-cache phpredis/phpredis \
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
