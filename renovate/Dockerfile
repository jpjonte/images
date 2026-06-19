# syntax=docker/dockerfile:1

# Stock Renovate (the default containerbase image, NOT -full) with the Flutter
# SDK baked on PATH. Renovate's pub manager needs `flutter`/`dart` to refresh
# pubspec.lock; containerbase has no dart/flutter tool, so we add it here and
# leave binarySource at its default (install) — that keeps containerbase
# auto-installing PHP/Composer/etc. for the other managed repos.
#
# RENOVATE_VERSION is required (no default): CI passes the upstream Renovate
# release tag, and the published image is tagged to match it.
ARG RENOVATE_VERSION
ARG FLUTTER_VERSION=3.44.1
FROM ghcr.io/renovatebot/renovate:${RENOVATE_VERSION}

# Re-declare after FROM so it is in scope for the RUN below.
ARG FLUTTER_VERSION

USER root

# Flutter's first-run Dart SDK bootstrap (bin/internal/update_dart_sdk.sh) needs
# curl + unzip (xz-utils for .tar.xz artifacts); git + ca-certificates are
# already present but asserted for safety.
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
       ca-certificates curl git unzip xz-utils \
    && rm -rf /var/lib/apt/lists/*

ENV FLUTTER_HOME=/opt/flutter
ENV PATH="${FLUTTER_HOME}/bin:${FLUTTER_HOME}/bin/cache/dart-sdk/bin:${PATH}"

# Shallow clone, keep .git (Flutter self-identifies via `git rev-parse`), then
# hand ownership to UID 1000 so the runtime user can write bin/cache.
RUN git clone --branch "${FLUTTER_VERSION}" --depth 1 \
      https://github.com/flutter/flutter.git "${FLUTTER_HOME}" \
    && git config --system --add safe.directory "${FLUTTER_HOME}" \
    && chown -R 1000:1000 "${FLUTTER_HOME}"

USER 1000

# Bake the Dart SDK + universal artifacts so nothing downloads at cron time.
RUN flutter config --no-analytics \
    && flutter precache --universal --no-android --no-ios --no-linux \
       --no-windows --no-macos --no-web \
    && flutter --version
