#!/usr/bin/env sh

docker pull $NAMESPACE:$IMAGE_VERSION || true
docker build --compress --cache-from $NAMESPACE:$IMAGE_VERSION -t $NAMESPACE:$IMAGE_VERSION -f $DOCKERFILE .
docker tag $NAMESPACE:$IMAGE_VERSION
docker push $NAMESPACE:$IMAGE_VERSION
