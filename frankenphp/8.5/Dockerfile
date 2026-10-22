FROM ghcr.io/php/pie:1.5-bin@sha256:9d3e6d9dafa5ae8cf034489260e206a5aa1b488b29c0ddaea9149826d9e32f52 AS pie
FROM mlocati/php-extension-installer:2@sha256:ac4b252c153a9f6de5578ff2c417790aba836bb49855543144606033eceda253 AS php-extension-installer

FROM dunglas/frankenphp:1-php8.5-alpine@sha256:39dfc07f14f49503f1a02a0009459382b592448549edbac5a83fc988908f7723

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
