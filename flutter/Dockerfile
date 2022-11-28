FROM plugfox/flutter:stable-android

RUN sdkmanager "--update" "--verbose" \
    && sdkmanager "build-tools;30.0.3" "platform-tools" "platforms;android-30" "platforms;android-31" "platforms;android-32" "platforms;android-33" "extras;android;m2repository" "extras;google;google_play_services" "extras;google;m2repository"

# TODO: remove repository once alpine 3.17 is out
RUN apk add --update --no-cache --repository=http://dl-cdn.alpinelinux.org/alpine/edge/testing lcov

RUN dart pub global activate cobertura
RUN dart pub global activate junitreport

ENV PATH="${PATH}:${HOME}/.pub-cache/bin"
