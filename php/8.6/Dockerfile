FROM ghcr.io/php/pie:1.6-bin@sha256:f49c15dbb88a7aec373fdb15ab9004bf08958772db3b476c42364e10a8ea416f AS pie
FROM mlocati/php-extension-installer:2@sha256:584fcc217b94a10187367552f6571cd8680ee4bf22bd752f1087a7d55e35e7de AS php-extension-installer

FROM php:8.6-fpm-alpine@sha256:31d659619113bbf45ca69dfb04c7220f095c2b814d58ea373204aaa237eeb2a1

WORKDIR /tmp

COPY ./php/scripts/*.sh /tmp/

COPY --from=php-extension-installer /usr/bin/install-php-extensions /usr/local/bin/

# PIE is bind-mounted for this step only, so it never lands in the image.
RUN --mount=type=bind,from=pie,source=/pie,target=/usr/local/bin/pie \
  apk upgrade --no-cache \
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
