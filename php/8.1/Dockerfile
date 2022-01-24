FROM php:8.1-alpine

WORKDIR /tmp

COPY ./php/scripts/*.sh /tmp/
COPY --from=composer:2 /usr/bin/composer /usr/bin/composer

RUN chmod +x /tmp/*.sh \
  && adduser -D php \
  && mkdir -p /var/www/html \
  && apk add --update --no-cache bash tree \
  && bash ./packages.sh \
  && bash ./extensions.sh \
  && rm -rf ~/.composer/cache/* \
  && chown -R php:php /var/www /home/php \
  && echo "php  ALL = ( ALL ) NOPASSWD: ALL" >> /etc/sudoers \
  && bash ./cleanup.sh

USER php

WORKDIR /var/www/html

CMD ["php", "-a"]
