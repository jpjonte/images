# syntax=docker/dockerfile:1@sha256:87999aa3d42bdc6bea60565083ee17e86d1f3339802f543c0d03998580f9cb89

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

FROM moby/buildkit:v0.31.0@sha256:a095b3d11ce1a9a05b6064ef515dfca0291ec5bcf2ea8178da8f6461924294e1 AS buildkit

FROM data.forgejo.org/forgejo/runner:12@sha256:268ad0d1d24bd7ecf2386b7c44e8211398dc014ca81d4fd5fbad96fe79af18f5
USER root
RUN apk add --no-cache nodejs
COPY --from=buildkit /usr/bin/buildctl /usr/local/bin/buildctl
USER 1000:1000
