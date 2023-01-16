#!/usr/bin/env sh

set -eux

MAIN=$(echo ${TAGS} | cut -d' ' -f1)
LIST=""

for TAG in $TAGS; do
  LIST="${LIST} -t ${NAMESPACE}:${TAG}"
done

docker context create ci
docker buildx create --use ci
docker buildx build . -f $DOCKERFILE $LIST --platform linux/amd64,linux/arm64 --push
