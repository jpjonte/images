# syntax=docker/dockerfile:1@sha256:4edf897a3ffa55b89f906fc8cc78afdb3f1834cc9c7083565e611a8a7d5fe99e

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

FROM moby/buildkit:v0.34.2@sha256:c5f8862f52499773af85bc07695b2379ef08e8002352b0df2c4864c91d78dabe AS buildkit

FROM data.forgejo.org/forgejo/runner:13@sha256:568cea8c15ddc01fc8f330124892f572af7db37fa28344a2c1914405793bf61d
USER root
RUN apk add --no-cache nodejs
COPY --from=buildkit /usr/bin/buildctl /usr/local/bin/buildctl
USER 1000:1000
