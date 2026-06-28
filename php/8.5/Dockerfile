FROM php:8.5-fpm-alpine@sha256:fd9669cdc9caa2bc4857a2c9f6b5e86c47a7f85043a6717c29901ca4a8b1cd4e

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

# Node (CI-only): required so the Forgejo runner can execute JS actions
# (actions/checkout, actions/cache) inside this job container. Alpine's nodejs
# package is >=20, which actions/*@node20 require; assert it at build time.
RUN apk add --no-cache nodejs \
  && node -e 'process.exit(+process.versions.node.split(".")[0] >= 20 ? 0 : 1)'
