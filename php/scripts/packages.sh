#!/usr/bin/env bash

set -euo pipefail

apk --update --no-cache add \
    curl \
    g++ \
    gcc \
    libc-dev \
    make \
    openssl \
    sudo \
    git \
    acl \
#    grep \
#    jq \
#    mariadb-client \
#    openssh-client \
#    patch \
#    python3 \
#    rsync \
#    zip

apk add --update --no-cache \
    autoconf \
    openssl-dev \
    acl
#    build-base \
#    file \
