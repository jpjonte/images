#!/busybox/sh

set -eux

TAG_LIST=""

for TAG in $TAGS; do
  TAG_LIST="${TAG_LIST} --destination ${NAMESPACE}:${TAG}"
done

/kaniko/executor \
  --context . \
  --dockerfile $DOCKERFILE \
  $TAG_LIST
