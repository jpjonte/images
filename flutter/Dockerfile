FROM ubuntu:24.04

ARG FLUTTER_VERSION=stable
ENV DEBIAN_FRONTEND=noninteractive

# System dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
      git curl unzip xz-utils zip \
      openjdk-17-jdk-headless \
      lcov \
      clang cmake ninja-build pkg-config libgtk-3-dev \
    && rm -rf /var/lib/apt/lists/*

# Flutter SDK
ENV FLUTTER_HOME=/opt/flutter
ENV PATH="${FLUTTER_HOME}/bin:${FLUTTER_HOME}/bin/cache/dart-sdk/bin:${PATH}:/root/.pub-cache/bin"

RUN git clone --branch $FLUTTER_VERSION --depth 1 https://github.com/flutter/flutter.git $FLUTTER_HOME \
    && flutter config --no-analytics

# Android command-line tools
ENV ANDROID_HOME=/opt/android-sdk
ENV ANDROID_SDK_ROOT=$ANDROID_HOME

RUN mkdir -p $ANDROID_HOME/cmdline-tools \
    && curl -fsSL https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip -o /tmp/cmdline-tools.zip \
    && unzip -q /tmp/cmdline-tools.zip -d $ANDROID_HOME/cmdline-tools \
    && mv $ANDROID_HOME/cmdline-tools/cmdline-tools $ANDROID_HOME/cmdline-tools/latest \
    && rm /tmp/cmdline-tools.zip

ENV PATH="${PATH}:${ANDROID_HOME}/cmdline-tools/latest/bin:${ANDROID_HOME}/platform-tools"

RUN yes | sdkmanager --licenses > /dev/null 2>&1 \
    && sdkmanager \
      "build-tools;35.0.0" \
      "platform-tools" \
      "platforms;android-35"

# glab CLI
ARG GLAB_VERSION=1.82.0
RUN curl -fsSL "https://gitlab.com/gitlab-org/cli/-/releases/v${GLAB_VERSION}/downloads/glab_${GLAB_VERSION}_linux_amd64.deb" -o /tmp/glab.deb \
    && dpkg -i /tmp/glab.deb \
    && rm /tmp/glab.deb

# Dart global tools
RUN dart pub global activate cobertura \
    && dart pub global activate junitreport

RUN flutter doctor
