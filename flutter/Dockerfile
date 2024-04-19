FROM ghcr.io/cirruslabs/flutter:stable

ENV PATH="${PATH}:/root/.pub-cache/bin"

RUN sdkmanager "--update" "--verbose"

RUN apt-get update && apt-get install -y lcov

RUN dart pub global activate cobertura
RUN dart pub global activate junitreport
