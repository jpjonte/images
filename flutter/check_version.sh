#!/bin/sh
set -eu

# Queries the Flutter releases API for the current stable version.
# Checks if that tag already exists in the registry.
# Writes FLUTTER_VERSION and FLUTTER_BUILD to flutter_version.env.

FLUTTER_RELEASES="https://storage.googleapis.com/flutter_infra_release/releases/releases_linux.json"

VERSION=$(curl -s "$FLUTTER_RELEASES" \
  | jq -r '.current_release.stable as $h | .releases[] | select(.hash==$h) | .version')

echo "Latest stable Flutter version: $VERSION"

# Check registry for existing tag (Docker Registry HTTP API V2)
STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
  -u "$REGISTRY_USER:$REGISTRY_PASSWORD" \
  "https://$REGISTRY_URL/v2/flutter/manifests/$VERSION" \
  -H "Accept: application/vnd.docker.distribution.manifest.v2+json")

if [ "$STATUS" = "200" ]; then
  echo "Flutter $VERSION already exists in registry"
  echo "FLUTTER_BUILD=false" > flutter_version.env
else
  echo "New Flutter version: $VERSION"
  echo "FLUTTER_BUILD=true" > flutter_version.env
fi
echo "FLUTTER_VERSION=$VERSION" >> flutter_version.env
