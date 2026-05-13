#!/usr/bin/env bash
# Installs CI-only tooling on top of a Flutter image.
# Expects env vars: GLAB_VERSION, TARGETARCH.
# Assumes apt cache mounts are managed by the calling RUN step.
set -euo pipefail

: "${GLAB_VERSION:?GLAB_VERSION is required}"
: "${TARGETARCH:?TARGETARCH is required}"

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends \
  lcov \
  jq

# glab CLI
curl -fsSL "https://gitlab.com/gitlab-org/cli/-/releases/v${GLAB_VERSION}/downloads/glab_${GLAB_VERSION}_linux_${TARGETARCH}.deb" \
  -o /tmp/glab.deb
dpkg -i /tmp/glab.deb
rm /tmp/glab.deb

# Dart global tools (PATH already includes /root/.pub-cache/bin)
dart pub global activate cobertura
dart pub global activate junitreport
