FROM plugfox/flutter:stable-android-warmed

RUN sdkmanager "--update" "--verbose" \
    && sdkmanager "build-tools;30.0.2" "platform-tools" "platforms;android-28" "platforms;android-29" "platforms;android-30" "extras;android;m2repository" "extras;google;google_play_services" "extras;google;m2repository" \
