FROM ghcr.io/cirruslabs/flutter:stable

ENV PATH="${PATH}:/root/.pub-cache/bin"

RUN sdkmanager "--update" "--verbose" \
    && sdkmanager "build-tools;35.0.0" "platform-tools" "platforms;android-35" "extras;android;m2repository" "extras;google;google_play_services" "extras;google;m2repository" "ndk;28.2.13676358"

ARG GLAB_VERSION=1.82.0
RUN apt-get update && apt-get install -y lcov \
	&& curl -fsSL "https://gitlab.com/gitlab-org/cli/-/releases/v${GLAB_VERSION}/downloads/glab_${GLAB_VERSION}_linux_amd64.deb" -o /tmp/glab.deb \
	&& dpkg -i /tmp/glab.deb \
	&& rm /tmp/glab.deb

RUN dart pub global activate cobertura
RUN dart pub global activate junitreport
