FROM dunglas/frankenphp:1-php8.5-alpine@sha256:fb1829d72fb9efea8ae3aabbb4d2f3497594f1506bdc2b5021a6d76f242a4a15

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
