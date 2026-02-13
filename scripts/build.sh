#!/busybox/sh

set -eux

TAG_LIST=""

for TAG in $TAGS; do
  TAG_LIST="${TAG_LIST} --destination ${NAMESPACE}:${TAG}"
done

CACHE_REPO="$NAMESPACE/cache"

/kaniko/executor \
  --context . \
  --dockerfile $DOCKERFILE \
  --snapshot-mode=redo \
  --cache=true \
  --cache-repo $CACHE_REPO \
  ${BUILD_ARGS:-} \
  $TAG_LIST
