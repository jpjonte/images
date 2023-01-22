#!/busybox/sh

set -eux

mkdir -p /kaniko/.docker

echo "{\"auths\":{\"$REGISTRY_URL\":{\"username\":\"$REGISTRY_USER\",\"password\":\"$REGISTRY_PASSWORD\"}}}" > /kaniko/.docker/config.json
