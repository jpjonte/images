#!/usr/bin/env sh

set -eu

rm -rf /tmp/* \
  /usr/includes/* \
  /usr/share/man/* \
  /var/cache/apk/* \
  /var/tmp/* \
  ~/.pie \
  "${XDG_CONFIG_HOME:-$HOME/.config}/pie"
