#!/usr/bin/env sh

set -eux

MAIN=$(echo ${TAGS} | cut -d' ' -f1)
LIST=""

for TAG in $TAGS; do
  LIST="${LIST} -t ${NAMESPACE}:${TAG}"
done

docker pull $NAMESPACE:$MAIN || true
docker build --compress --cache-from $NAMESPACE:$MAIN $LIST -f $DOCKERFILE .
docker push $NAMESPACE:$MAIN
