# Playwright base for Node apps that drive Chromium and compile native addons
# (better-sqlite3 & co.) — e.g. bud/easybank-import on forge.jpj.dev, which
# uses it both as its CI job container and as its image base.
#
# Upstream ships Chromium + its system deps and node; this adds what upstream
# lacks so consumers never run apt per CI job:
#   - python3, make, g++ : node-gyp builds from source when no prebuild matches
#   - util-linux         : flock (job locking)
#   - corepack enabled   : yarn/pnpm from the project's packageManager field
#
# Each playwright/<minor>/ directory publishes ghcr.io/jpjonte/playwright:<minor>
# and must stay on that minor (renovate.json); consumers' npm playwright must
# match it. A new minor gets its own directory instead of a bump.

FROM mcr.microsoft.com/playwright:v1.63.0-noble@sha256:eff16c30e6f3f4af0a03fa4b706120d5e9b0891c344a27d64559aff5900a4a27

# upgrade: the weekly rebuild (rebuild.yml) picks up OS security patches.
RUN apt-get update \
 && apt-get upgrade -y \
 && apt-get install -y --no-install-recommends python3 make g++ util-linux \
 && rm -rf /var/lib/apt/lists/* \
 && corepack enable
