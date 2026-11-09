FROM ghcr.io/php/pie:1.5-bin@sha256:3fca03c16df842d02b654dc382db3756058d9c128064f57cace14f8728779ce9 AS pie
FROM mlocati/php-extension-installer:2@sha256:4fd45396c16685266d32bf147a24ecd5e81029d3820295895bf4a90131190ac9 AS php-extension-installer

FROM php:8.5-fpm-alpine@sha256:64535609509e0fd5c8529359e6b599a68ce42089defd565f7881efdae7687cea

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
