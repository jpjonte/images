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

FROM moby/buildkit:v0.32.0@sha256:1f8167fcb0eca5b7126353d35299386945cbb8949cc516c592a49f80cfce4fa2 AS buildkit

FROM data.forgejo.org/forgejo/runner:13@sha256:7fb853bfe73c229be6349398359c0a7bd01fadfd17c106607b2221150b799ed2
USER root
RUN apk add --no-cache nodejs
COPY --from=buildkit /usr/bin/buildctl /usr/local/bin/buildctl
USER 1000:1000
