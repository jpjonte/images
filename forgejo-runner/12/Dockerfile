# syntax=docker/dockerfile:1@sha256:ecfaec9ed6d810b56388c508f4121597bfbba70d41a6dfeee4d8cad5f295fc32

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

FROM moby/buildkit:v0.33.0@sha256:6c2fa84a6b61ccd72899dde4239f8d5717f05f9a8ca6f3cad185fb1a95a94de3 AS buildkit

FROM data.forgejo.org/forgejo/runner:13@sha256:7fb853bfe73c229be6349398359c0a7bd01fadfd17c106607b2221150b799ed2
USER root
RUN apk add --no-cache nodejs
COPY --from=buildkit /usr/bin/buildctl /usr/local/bin/buildctl
USER 1000:1000
