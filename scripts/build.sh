#!/usr/bin/env sh

set -eux

docker pull $NAMESPACE:$IMAGE_VERSION || true
docker build --compress --cache-from $NAMESPACE:$IMAGE_VERSION -t $NAMESPACE:$IMAGE_VERSION -t $NAMESPACE:latest -f $DOCKERFILE .
docker push $NAMESPACE:$IMAGE_VERSION
