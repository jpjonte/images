#!/usr/bin/env bash

set -euo pipefail

apk del --purge \
  openssl-dev
#  grep \
#  build-base \
#  file \

rm -rf /tmp/* \
        /usr/includes/* \
        /usr/share/man/* \
        /var/cache/apk/* \
        /var/tmp/*
