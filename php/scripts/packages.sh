#!/usr/bin/env bash

set -euo pipefail

apk --update --no-cache add \
    g++ \
    gcc \
    libc-dev \
    make \
    openssl \
    sudo \
    git \
#    grep \
#    jq \
#    mariadb-client \
#    openssh-client \
#    patch \
#    python3 \
#    rsync \
#    zip

# persistent / runtime deps
apk add --update --no-cache --virtual .persistent-deps \
    curl
#		ca-certificates \
#		tar \
#		xz \

apk add --update --no-cache \
    autoconf \
    openssl-dev \
    acl
#    build-base \
#    file \
