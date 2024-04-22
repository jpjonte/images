#!/usr/bin/env sh

set -eu

apk --update --no-cache add \
    curl \
    acl \
    bash
