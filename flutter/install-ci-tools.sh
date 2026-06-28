#!/usr/bin/env bash
# Installs CI-only tooling on top of a Flutter image.
# Expects env vars: GLAB_VERSION, TARGETARCH.
# Assumes apt cache mounts are managed by the calling RUN step.
set -euo pipefail

: "${GLAB_VERSION:?GLAB_VERSION is required}"
: "${TARGETARCH:?TARGETARCH is required}"

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends \
  lcov \
  jq

# Node (CI-only): lets the Forgejo runner execute JS actions (actions/checkout,
# actions/cache) inside this container. Pinned tarball — Debian's apt node is 18,
# too old for actions/*@node20. TARGETARCH is amd64|arm64; node uses x64|arm64.
NODE_VERSION="${NODE_VERSION:-20.20.2}"
case "$TARGETARCH" in
  amd64) NODE_ARCH=x64 ;;
  arm64) NODE_ARCH=arm64 ;;
  *) echo "unsupported TARGETARCH: $TARGETARCH" >&2; exit 1 ;;
esac
curl -fsSL "https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}-linux-${NODE_ARCH}.tar.xz" \
  | tar -xJ -C /usr/local --strip-components=1 --no-same-owner
node -e 'process.exit(+process.versions.node.split(".")[0] >= 20 ? 0 : 1)'
node --version

# glab CLI
curl -fsSL "https://gitlab.com/gitlab-org/cli/-/releases/v${GLAB_VERSION}/downloads/glab_${GLAB_VERSION}_linux_${TARGETARCH}.deb" \
  -o /tmp/glab.deb
dpkg -i /tmp/glab.deb
rm /tmp/glab.deb

# Dart global tools (PATH already includes /root/.pub-cache/bin)
dart pub global activate cobertura
dart pub global activate junitreport

# SQLCipher (source-built) for projects with at-rest DB encryption tests.
# Debian's apt libsqlcipher is SQLCipher 3.x (SQLite 3.15.2) and lacks symbols
# the `sqlite3` Dart package needs (e.g. sqlite3_stmt_isexplain), so build a
# current release. Installs /usr/local/lib/libsqlcipher.so, loaded in tests via
# DynamicLibrary.open('libsqlcipher.so'). libssl3 is pinned (manual) so the
# autoremove below keeps the libcrypto runtime libsqlcipher links against.
SQLCIPHER_VERSION="${SQLCIPHER_VERSION:-4.6.1}"
apt-get install -y --no-install-recommends build-essential libssl-dev libssl3 tcl
curl -fsSL "https://github.com/sqlcipher/sqlcipher/archive/refs/tags/v${SQLCIPHER_VERSION}.tar.gz" \
  -o /tmp/sqlcipher.tgz
tar xzf /tmp/sqlcipher.tgz -C /tmp
(
  cd "/tmp/sqlcipher-${SQLCIPHER_VERSION}"
  ./configure --enable-tempstore=yes --disable-tcl \
    CFLAGS="-DSQLITE_HAS_CODEC" LDFLAGS="-lcrypto"
  make -j"$(nproc)"
  make install
)
ldconfig
# Fail the build fast if the produced library is missing the symbol that the
# old Debian SQLCipher lacked — guards against a silent regression. Use a
# command-substitution + glob (no pipe) so `grep -q` closing the pipe early
# can't SIGPIPE `nm` and trip `set -o pipefail`.
case "$(nm -D /usr/local/lib/libsqlcipher.so)" in
  *sqlite3_stmt_isexplain*) ;;
  *) echo 'ERROR: built libsqlcipher.so lacks sqlite3_stmt_isexplain' >&2; exit 1 ;;
esac
rm -rf /tmp/sqlcipher.tgz "/tmp/sqlcipher-${SQLCIPHER_VERSION}"
apt-get purge -y build-essential libssl-dev tcl
apt-get autoremove -y
