# syntax=docker/dockerfile:1.7

# =========================================================================
# Stage: base
# Debian-slim + Flutter SDK only. No Android, no .git, no CI tools.
# =========================================================================
FROM debian:bookworm-slim AS base

ARG FLUTTER_VERSION=stable
ARG YQ_VERSION=4.45.4
ARG TARGETARCH
ENV DEBIAN_FRONTEND=noninteractive

# System dependencies (ca-certificates is required on debian-slim for HTTPS).
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates \
      git \
      curl \
      unzip \
      xz-utils \
      zip

# yq (YAML processor)
RUN curl -fsSL "https://github.com/mikefarah/yq/releases/download/v${YQ_VERSION}/yq_linux_${TARGETARCH}" \
      -o /usr/local/bin/yq \
    && chmod +x /usr/local/bin/yq

# Flutter SDK. Shallow-clone and keep .git — Flutter calls `git rev-parse`
# to identify itself and refuses to run without it. Skip the Android
# precache; it belongs in the android stage.
ENV FLUTTER_HOME=/opt/flutter
ENV PATH="${FLUTTER_HOME}/bin:${FLUTTER_HOME}/bin/cache/dart-sdk/bin:${PATH}:/root/.pub-cache/bin"

RUN git clone --branch "$FLUTTER_VERSION" --depth 1 https://github.com/flutter/flutter.git "$FLUTTER_HOME" \
    && flutter config --no-analytics \
    && flutter precache --universal --no-android --no-ios --no-linux --no-windows --no-macos --no-web \
    && flutter doctor

# =========================================================================
# Stage: base-ci
# base + shared CI tooling (lcov, jq, glab, cobertura, junitreport).
# =========================================================================
FROM base AS base-ci

ARG GLAB_VERSION=1.82.0
ARG TARGETARCH

COPY flutter/install-ci-tools.sh /tmp/install-ci-tools.sh
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    GLAB_VERSION="${GLAB_VERSION}" TARGETARCH="${TARGETARCH}" \
      /tmp/install-ci-tools.sh \
    && rm /tmp/install-ci-tools.sh

# =========================================================================
# Stage: android
# base + JDK + Android SDK (build-tools, platform-tools, platform, NDK).
# Drops both extras;*;m2repository — legacy Support Library, not needed
# for AndroidX projects.
# =========================================================================
FROM base AS android

ARG TARGETARCH
ARG ANDROID_CMDLINE_TOOLS_VERSION=11076708
ARG ANDROID_BUILD_TOOLS_VERSION=35.0.0
ARG ANDROID_PLATFORM_VERSION=android-35
ARG ANDROID_NDK_VERSION=28.2.13676358
ENV DEBIAN_FRONTEND=noninteractive

# JDK + native build deps for Android/Flutter desktop tooling
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    apt-get update && apt-get install -y --no-install-recommends \
      openjdk-17-jdk-headless \
      clang \
      cmake \
      ninja-build \
      pkg-config \
      libgtk-3-dev

# Android engine artifacts (gradle wrapper shims, build tooling)
RUN flutter precache --android

# Android command-line tools
ENV ANDROID_HOME=/opt/android-sdk
ENV ANDROID_SDK_ROOT=$ANDROID_HOME

RUN mkdir -p "$ANDROID_HOME/cmdline-tools" \
    && curl -fsSL "https://dl.google.com/android/repository/commandlinetools-linux-${ANDROID_CMDLINE_TOOLS_VERSION}_latest.zip" -o /tmp/cmdline-tools.zip \
    && unzip -q /tmp/cmdline-tools.zip -d "$ANDROID_HOME/cmdline-tools" \
    && mv "$ANDROID_HOME/cmdline-tools/cmdline-tools" "$ANDROID_HOME/cmdline-tools/latest" \
    && rm /tmp/cmdline-tools.zip

ENV PATH="${PATH}:${ANDROID_HOME}/cmdline-tools/latest/bin:${ANDROID_HOME}/platform-tools"

# Android SDK packages. No extras;*;m2repository — legacy AOSP Support
# Library m2repos are huge (~500MB combined) and only needed for non-
# AndroidX projects.
RUN yes | sdkmanager --licenses > /dev/null 2>&1 \
    && sdkmanager \
      "build-tools;${ANDROID_BUILD_TOOLS_VERSION}" \
      "platform-tools" \
      "platforms;${ANDROID_PLATFORM_VERSION}" \
      "ndk;${ANDROID_NDK_VERSION}"

# Gradle cache warmup — build a throwaway project to download Gradle & deps.
# Skipped on arm64: the Android SDK ships x86_64-only binaries (aapt2,
# cmake, etc.).
RUN if [ "$TARGETARCH" = "amd64" ]; then \
      flutter create /tmp/_warmup \
      && cd /tmp/_warmup \
      && flutter build apk --debug \
      && rm -rf /tmp/_warmup; \
    fi

RUN flutter doctor
