FROM dunglas/frankenphp:1-php8.5-alpine@sha256:467ad0da2ef2d09112df83b7082c5cd8cebbb67ee51c8551810f1fcb20984fca

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

WORKDIR /srv/app
