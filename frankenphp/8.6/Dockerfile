FROM ghcr.io/php/pie:1.6-bin@sha256:f49c15dbb88a7aec373fdb15ab9004bf08958772db3b476c42364e10a8ea416f AS pie
FROM mlocati/php-extension-installer:2@sha256:584fcc217b94a10187367552f6571cd8680ee4bf22bd752f1087a7d55e35e7de AS php-extension-installer

FROM dunglas/frankenphp:1-php8.6-alpine@sha256:0b1a04c35c52056de21f09983a01d7bdfe0c16ee7e66b2f9c238a0c8688e6469

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
