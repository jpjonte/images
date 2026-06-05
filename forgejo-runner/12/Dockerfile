# syntax=docker/dockerfile:1

# Custom Forgejo Actions runner for the HOST execution backend.
#
# The stock runner image (data.forgejo.org/forgejo/runner) is Alpine/musl with
# only git+bash. Under the host backend, workflow jobs run inside THIS image, so
# we add:
#   - nodejs  : musl Node runtime for JS actions (actions/checkout, ...)
#   - buildctl: BuildKit client, to build images against a remote rootless
#               buildkitd (no Docker daemon needed)
#
# Multi-arch (amd64+arm64): every base here ships both, so buildx resolves the
# right arch per platform.

FROM moby/buildkit:v0.30.0 AS buildkit

FROM data.forgejo.org/forgejo/runner:12
USER root
RUN apk add --no-cache nodejs
COPY --from=buildkit /usr/bin/buildctl /usr/local/bin/buildctl
USER 1000:1000
