FROM php:8.5-fpm-alpine@sha256:bdc083e7b6acfb5eec64b5c85c134fe33cde8aa177da0d93fc46e43df2555b98

WORKDIR /tmp

COPY ./php/scripts/*.sh /tmp/

ADD https://github.com/mlocati/docker-php-extension-installer/releases/latest/download/install-php-extensions /usr/local/bin/

RUN chmod +x /usr/local/bin/install-php-extensions

RUN apk upgrade --no-cache \
  && chmod +x /tmp/*.sh \
  && adduser -D php \
  && mkdir -p /var/www/html \
  && sh ./packages.sh \
  && sh ./extensions.sh \
  && rm -rf ~/.composer/cache/* \
  && chown -R php:php /var/www /home/php \
  && sh ./cleanup.sh
