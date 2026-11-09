FROM ghcr.io/php/pie:1.5-bin@sha256:3fca03c16df842d02b654dc382db3756058d9c128064f57cace14f8728779ce9 AS pie
FROM mlocati/php-extension-installer:2@sha256:4fd45396c16685266d32bf147a24ecd5e81029d3820295895bf4a90131190ac9 AS php-extension-installer

FROM dunglas/frankenphp:1-php8.5-alpine@sha256:bf8051e99d28fd546b0d1c1b74329f3eba0496b56bb8cd979a10ab1265e28f5c

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

# The upstream image sets cap_net_bind_service=ep on the FrankenPHP binary so it
# can bind :80/:443 as non-root. The *effective* bit makes it "capability-dumb":
# under a hardened securityContext that empties the capability bounding set
# (capabilities.drop: [ALL]), the kernel can no longer grant that effective cap
# and refuses the exec with EPERM ("frankenphp: Operation not permitted").
# Consumers run behind a Service/Ingress on an unprivileged port (:8080), so the
# capability is unnecessary — strip it to keep the binary exec-able under
# drop-ALL. See https://git.jpj.dev/bud/pantry/-/issues/309.
RUN setcap -r /usr/local/bin/frankenphp

WORKDIR /srv/app
