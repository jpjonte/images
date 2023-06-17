FROM plugfox/flutter:stable-android

RUN sdkmanager "--update" "--verbose" \
    && sdkmanager "build-tools;33.0.2" "platform-tools" "platforms;android-33" "extras;android;m2repository" "extras;google;google_play_services" "extras;google;m2repository"

# TODO: remove repository once it reaches a stable version of alpine
RUN apk add --update --no-cache --repository=http://dl-cdn.alpinelinux.org/alpine/edge/testing lcov

RUN dart pub global activate cobertura
RUN dart pub global activate junitreport

ENV PATH="${PATH}:${HOME}/.pub-cache/bin"
