# Flutter Image Split Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Split the monolithic `flutter` Docker image into four targeted images (`flutter:base`, `flutter:base-ci`, `flutter:android`, `flutter:android-ci`) to reduce size for consumers who don't need Android tooling.

**Architecture:** One multi-stage Dockerfile with four named stages chained `base → base-ci` and `base → android → android-ci`. CI-tool installation is factored into a shared shell script that both `-ci` stages `COPY` and execute, so the tool list lives in exactly one place while the binaries get installed in each target's filesystem. The base stage keeps the shallow Flutter `.git` (Flutter calls `git rev-parse` internally to identify itself and refuses to run without it) and skips the Android precache; the Android stage adds the JDK, command-line tools, SDK packages (NDK, build-tools, platform; no `extras;*;m2repository`), and the Gradle warmup (amd64 only). Switch base to `debian:bookworm-slim`.

**Tech Stack:** Docker (BuildKit, multi-stage, `--mount=type=cache`), GitHub Actions (matrix build + multi-arch manifest merge), Flutter SDK, Android SDK command-line tools.

---

## File Structure

- **Modify:** `flutter/Dockerfile` — replace with multi-stage build
- **Create:** `flutter/install-ci-tools.sh` — shared CI-tooling installer (lcov, jq, glab, cobertura, junitreport)
- **Modify:** `.github/workflows/build.yml` — build all four stages, publish under separate tags
- **Modify:** `.dockerignore` — no change expected; verify Flutter build context isn't accidentally narrowed

Each stage produces one image with one clear responsibility. The shared script avoids duplicating the CI tool list between `base-ci` and `android-ci` while keeping each stage's binaries baked into its own filesystem (no cross-stage `COPY --from` of installed packages, which is fragile for dpkg-installed binaries).

---

## Task 1: Create the shared CI tools install script

**Files:**
- Create: `flutter/install-ci-tools.sh`

- [ ] **Step 1: Write the script**

Create `flutter/install-ci-tools.sh` with the following content:

```bash
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

# glab CLI
curl -fsSL "https://gitlab.com/gitlab-org/cli/-/releases/v${GLAB_VERSION}/downloads/glab_${GLAB_VERSION}_linux_${TARGETARCH}.deb" \
  -o /tmp/glab.deb
dpkg -i /tmp/glab.deb
rm /tmp/glab.deb

# Dart global tools (PATH already includes /root/.pub-cache/bin)
dart pub global activate cobertura
dart pub global activate junitreport
```

- [ ] **Step 2: Make it executable in git**

Run:
```bash
chmod +x flutter/install-ci-tools.sh
git update-index --chmod=+x flutter/install-ci-tools.sh 2>/dev/null || true
```

(The `git update-index` line is a no-op if the file isn't tracked yet; the staged `git add` in the commit step will pick up the exec bit from the filesystem.)

- [ ] **Step 3: Lint the script**

Run: `shellcheck flutter/install-ci-tools.sh`
Expected: no warnings. If `shellcheck` isn't installed, run via Docker: `docker run --rm -v "$PWD:/mnt" koalaman/shellcheck:stable /mnt/flutter/install-ci-tools.sh`. Fix any findings before committing.

- [ ] **Step 4: Commit**

```bash
git add flutter/install-ci-tools.sh
git commit -m "flutter: add shared CI tools install script"
```

---

## Task 2: Rewrite Dockerfile with `base` + `base-ci` stages

**Files:**
- Modify: `flutter/Dockerfile` (full rewrite)

This task replaces the Dockerfile entirely. The `android` and `android-ci` stages are appended in Task 3 and Task 4; after this task, building `--target android*` will fail until Task 3 lands, which is fine — `base` and `base-ci` must be working end-to-end first.

- [ ] **Step 1: Replace `flutter/Dockerfile` with the new multi-stage version**

Overwrite `flutter/Dockerfile` with:

```dockerfile
# syntax=docker/dockerfile:1.7

# =========================================================================
# Stage: base
# Debian-slim + Flutter SDK only. No Android, no .git, no CI tools.
# =========================================================================
FROM debian:bookworm-slim AS base

ARG FLUTTER_VERSION=stable
ARG YQ_VERSION=4.45.4
ARG TARGETARCH
ENV DEBIAN_FRONTEND=noninteractive

# System dependencies (ca-certificates is required on debian-slim for HTTPS).
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates \
      git \
      curl \
      unzip \
      xz-utils \
      zip

# yq (YAML processor)
RUN curl -fsSL "https://github.com/mikefarah/yq/releases/download/v${YQ_VERSION}/yq_linux_${TARGETARCH}" \
      -o /usr/local/bin/yq \
    && chmod +x /usr/local/bin/yq

# Flutter SDK. Shallow-clone, drop .git (saves ~600MB-1GB), skip Android
# precache — that belongs in the android stage.
ENV FLUTTER_HOME=/opt/flutter
ENV PATH="${FLUTTER_HOME}/bin:${FLUTTER_HOME}/bin/cache/dart-sdk/bin:${PATH}:/root/.pub-cache/bin"

RUN git clone --branch "$FLUTTER_VERSION" --depth 1 https://github.com/flutter/flutter.git "$FLUTTER_HOME" \
    && rm -rf "$FLUTTER_HOME/.git" \
    && flutter config --no-analytics \
    && flutter precache --universal --no-android --no-ios --no-linux --no-windows --no-macos --no-web \
    && flutter doctor

# =========================================================================
# Stage: base-ci
# base + shared CI tooling (lcov, jq, glab, cobertura, junitreport).
# =========================================================================
FROM base AS base-ci

ARG GLAB_VERSION=1.82.0
ARG TARGETARCH

COPY flutter/install-ci-tools.sh /tmp/install-ci-tools.sh
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    GLAB_VERSION="${GLAB_VERSION}" TARGETARCH="${TARGETARCH}" \
      /tmp/install-ci-tools.sh \
    && rm /tmp/install-ci-tools.sh
```

- [ ] **Step 2: Build `base` for the host architecture**

Run from the repo root:
```bash
DOCKER_BUILDKIT=1 docker build -f flutter/Dockerfile --target base -t flutter-base:test .
```
Expected: build succeeds; `flutter doctor` runs in the final layer and reports the Flutter channel/version without crashing.

- [ ] **Step 3: Smoke test `base`**

Run:
```bash
docker run --rm flutter-base:test bash -c '
  set -e
  flutter --version
  dart --version
  yq --version
  echo "OK"
'
```
Expected: prints Flutter version, Dart version, yq version, then `OK`.

- [ ] **Step 4: Record image size**

Run: `docker image ls flutter-base:test --format '{{.Size}}'`
Expected: noticeably smaller than the previous monolithic image (record the number; you'll compare against the original in Task 5). The previous image with Android + Gradle warmup typically lands in the 8-12GB range; `base` alone should be well under 3GB.

- [ ] **Step 5: Build `base-ci`**

Run:
```bash
DOCKER_BUILDKIT=1 docker build -f flutter/Dockerfile --target base-ci -t flutter-base-ci:test .
```
Expected: build succeeds.

- [ ] **Step 6: Smoke test `base-ci`**

Run:
```bash
docker run --rm flutter-base-ci:test bash -c '
  set -e
  flutter --version
  lcov --version
  jq --version
  glab --version
  cobertura --help >/dev/null
  tojunit --help >/dev/null   # binary name from the junitreport package
  echo "OK"
'
```
Expected: all six commands run successfully; final line is `OK`. `cobertura --help` and `tojunit --help` print usage and exit 0 (or non-zero with usage on stderr — `>/dev/null` keeps the test quiet; what matters is the binary is found on PATH). Note: the `junitreport` dart package installs the binary as `tojunit`.

- [ ] **Step 7: Commit**

```bash
git add flutter/Dockerfile
git commit -m "flutter: split image into base + base-ci stages

Switch base to debian:bookworm-slim, drop Flutter .git directory,
move android precache out of base, and add a base-ci variant that
layers shared CI tooling on top of base."
```

---

## Task 3: Add `android` stage

**Files:**
- Modify: `flutter/Dockerfile` (append `android` stage)

- [ ] **Step 1: Append the `android` stage to `flutter/Dockerfile`**

Add the following block to the end of `flutter/Dockerfile` (after the `base-ci` stage):

```dockerfile
# =========================================================================
# Stage: android
# base + JDK + Android SDK (build-tools, platform-tools, platform, NDK).
# Drops both extras;*;m2repository — legacy Support Library, not needed
# for AndroidX projects.
# =========================================================================
FROM base AS android

ARG TARGETARCH
ARG ANDROID_CMDLINE_TOOLS_VERSION=11076708
ARG ANDROID_BUILD_TOOLS_VERSION=35.0.0
ARG ANDROID_PLATFORM_VERSION=android-35
ARG ANDROID_NDK_VERSION=28.2.13676358
ENV DEBIAN_FRONTEND=noninteractive

# JDK + native build deps for Android/Flutter desktop tooling
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    apt-get update && apt-get install -y --no-install-recommends \
      openjdk-17-jdk-headless \
      clang \
      cmake \
      ninja-build \
      pkg-config \
      libgtk-3-dev

# Android engine artifacts (gradle wrapper shims, build tooling)
RUN flutter precache --android

# Android command-line tools
ENV ANDROID_HOME=/opt/android-sdk
ENV ANDROID_SDK_ROOT=$ANDROID_HOME

RUN mkdir -p "$ANDROID_HOME/cmdline-tools" \
    && curl -fsSL "https://dl.google.com/android/repository/commandlinetools-linux-${ANDROID_CMDLINE_TOOLS_VERSION}_latest.zip" -o /tmp/cmdline-tools.zip \
    && unzip -q /tmp/cmdline-tools.zip -d "$ANDROID_HOME/cmdline-tools" \
    && mv "$ANDROID_HOME/cmdline-tools/cmdline-tools" "$ANDROID_HOME/cmdline-tools/latest" \
    && rm /tmp/cmdline-tools.zip

ENV PATH="${PATH}:${ANDROID_HOME}/cmdline-tools/latest/bin:${ANDROID_HOME}/platform-tools"

# Android SDK packages. No extras;*;m2repository — legacy AOSP Support
# Library m2repos are huge (~500MB combined) and only needed for non-
# AndroidX projects.
RUN yes | sdkmanager --licenses > /dev/null 2>&1 \
    && sdkmanager \
      "build-tools;${ANDROID_BUILD_TOOLS_VERSION}" \
      "platform-tools" \
      "platforms;${ANDROID_PLATFORM_VERSION}" \
      "ndk;${ANDROID_NDK_VERSION}"

# Gradle cache warmup — build a throwaway project to download Gradle & deps.
# Skipped on arm64: the Android SDK ships x86_64-only binaries (aapt2,
# cmake, etc.).
RUN if [ "$TARGETARCH" = "amd64" ]; then \
      flutter create /tmp/_warmup \
      && cd /tmp/_warmup \
      && flutter build apk --debug \
      && rm -rf /tmp/_warmup; \
    fi

RUN flutter doctor
```

- [ ] **Step 2: Build `android` for the host architecture**

Run:
```bash
DOCKER_BUILDKIT=1 docker build -f flutter/Dockerfile --target android -t flutter-android:test .
```
Expected: build succeeds. On arm64 hosts the Gradle warmup is skipped (per the `TARGETARCH` guard); on amd64 hosts it runs and takes 5-10 extra minutes.

- [ ] **Step 3: Smoke test `android`**

Run:
```bash
docker run --rm flutter-android:test bash -c '
  set -e
  flutter --version
  java -version
  test -d "$ANDROID_HOME/platforms/android-35" || (echo "ERROR: platform missing" >&2; exit 1)
  test -d "$ANDROID_HOME/ndk/28.2.13676358" || (echo "ERROR: NDK missing" >&2; exit 1)
  test ! -d "$ANDROID_HOME/extras/google/m2repository" || (echo "ERROR: google m2repo should not be installed" >&2; exit 1)
  test ! -d "$ANDROID_HOME/extras/android/m2repository" || (echo "ERROR: android m2repo should not be installed" >&2; exit 1)
  echo "OK"
'
```
Expected: prints Flutter and Java versions, confirms the SDK platform and NDK are present, confirms neither m2repository is present, then `OK`.

- [ ] **Step 4: Record image size**

Run: `docker image ls flutter-android:test --format '{{.Size}}'`
Expected: smaller than the previous monolithic image by at least ~500MB (the dropped m2repos) plus the ~600MB-1GB saved by removing `.git` in `base`.

- [ ] **Step 5: Commit**

```bash
git add flutter/Dockerfile
git commit -m "flutter: add android stage layered on base

JDK, Android SDK (build-tools, platform-tools, platform-35, NDK), and
amd64 Gradle warmup. Drops both extras;*;m2repository packages —
legacy AOSP Support Library, not needed for AndroidX projects."
```

---

## Task 4: Add `android-ci` stage

**Files:**
- Modify: `flutter/Dockerfile` (append `android-ci` stage)

- [ ] **Step 1: Append the `android-ci` stage to `flutter/Dockerfile`**

Add the following block to the end of `flutter/Dockerfile`:

```dockerfile
# =========================================================================
# Stage: android-ci
# android + shared CI tooling. Uses the same install script as base-ci
# so the tool list lives in exactly one place.
# =========================================================================
FROM android AS android-ci

ARG GLAB_VERSION=1.82.0
ARG TARGETARCH

COPY flutter/install-ci-tools.sh /tmp/install-ci-tools.sh
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    GLAB_VERSION="${GLAB_VERSION}" TARGETARCH="${TARGETARCH}" \
      /tmp/install-ci-tools.sh \
    && rm /tmp/install-ci-tools.sh
```

- [ ] **Step 2: Build `android-ci`**

Run:
```bash
DOCKER_BUILDKIT=1 docker build -f flutter/Dockerfile --target android-ci -t flutter-android-ci:test .
```
Expected: build succeeds (re-uses cached layers from the `android` build).

- [ ] **Step 3: Smoke test `android-ci`**

Run:
```bash
docker run --rm flutter-android-ci:test bash -c '
  set -e
  flutter --version
  java -version
  test -d "$ANDROID_HOME/ndk/28.2.13676358" || (echo "ERROR: NDK missing" >&2; exit 1)
  lcov --version
  jq --version
  glab --version
  cobertura --help >/dev/null
  tojunit --help >/dev/null   # binary name from the junitreport package
  echo "OK"
'
```
Expected: all checks pass; final line is `OK`.

- [ ] **Step 4: Record image size**

Run: `docker image ls flutter-android-ci:test --format '{{.Size}}'`
Expected: marginally larger than `android` (CI tools add ~30-50MB).

- [ ] **Step 5: Commit**

```bash
git add flutter/Dockerfile
git commit -m "flutter: add android-ci stage

Layers shared CI tooling on top of android using the same install
script as base-ci."
```

---

## Task 5: Compare sizes and document the savings

**Files:**
- (no file changes; this task records evidence for the PR description)

- [ ] **Step 1: Build the old image for comparison**

Run:
```bash
git stash
DOCKER_BUILDKIT=1 docker build -f flutter/Dockerfile -t flutter-old:test .
git stash pop
```
Expected: old monolithic image builds. Record its size with:
```bash
docker image ls flutter-old:test --format '{{.Size}}'
```

- [ ] **Step 2: Tabulate sizes**

Collect sizes from Tasks 2-4 and the old image. Format as a table you can paste into the PR description:

```
| Image              | Size before | Size after |
|--------------------|-------------|------------|
| flutter (old)      | <X>         | —          |
| flutter:base       | —           | <Y>        |
| flutter:base-ci    | —           | <Y+small>  |
| flutter:android    | —           | <Z>        |
| flutter:android-ci | —           | <Z+small>  |
```

Sanity-check expectations:
- `flutter:android` should be smaller than `flutter (old)` by roughly the dropped m2repos (~500MB), plus whatever debian-slim saves over ubuntu:24.04 (~50-80MB).
- `flutter:base` should be ~3-5x smaller than `flutter:android` (no JDK, no Android SDK, no NDK, no Gradle cache).

If any number is off by more than 2x from these expectations, investigate before continuing — likely cause is a precache step landing in the wrong stage.

- [ ] **Step 3: Clean up test images**

Run:
```bash
docker image rm flutter-old:test flutter-base:test flutter-base-ci:test flutter-android:test flutter-android-ci:test
```

No commit for this task — it's measurement only. Keep the size table for the PR description.

---

## Task 6: Update GitHub Actions workflow to build all four targets

**Files:**
- Modify: `.github/workflows/build.yml` — `build-flutter` and `merge-flutter` jobs

The current workflow builds a single image and publishes it under `flutter:stable` and `flutter:<version>`. We need to build all four targets per platform, publish each under its own repo name with the same tagging scheme, and keep the existing `flutter` repo name working for backwards compatibility.

**Tagging scheme:**
- `ghcr.io/jpjonte/flutter:stable` and `ghcr.io/jpjonte/flutter:<version>` → continue to point at the `android` target (the current default — preserves backwards compatibility for existing consumers).
- `ghcr.io/jpjonte/flutter-base:stable` / `:<version>`
- `ghcr.io/jpjonte/flutter-base-ci:stable` / `:<version>`
- `ghcr.io/jpjonte/flutter-android-ci:stable` / `:<version>`

(`flutter-android` is redundant with the back-compat `flutter` tag — don't publish both. If you want them separate, change the back-compat tag scheme; otherwise the four published repos are `flutter`, `flutter-base`, `flutter-base-ci`, `flutter-android-ci`.)

- [ ] **Step 1: Replace the `build-flutter` job with a matrix over targets**

In `.github/workflows/build.yml`, replace the `build-flutter` job (currently lines 78-134) with the following:

```yaml
  # ── Flutter (per-platform, per-target build) ────────────────────
  build-flutter:
    needs: [changes, check-flutter]
    if: |
      always() && (
        (github.event_name == 'push' && needs.changes.outputs.flutter == 'true') ||
        (github.event_name == 'schedule' && needs.check-flutter.outputs.build == 'true') ||
        github.event_name == 'workflow_dispatch'
      )
    strategy:
      fail-fast: false
      matrix:
        target:
          - { name: base,        repo: flutter-base }
          - { name: base-ci,     repo: flutter-base-ci }
          - { name: android,     repo: flutter }
          - { name: android-ci,  repo: flutter-android-ci }
        platform:
          - linux/amd64
          - linux/arm64
        include:
          - platform: linux/amd64
            runner: ubuntu-latest
          - platform: linux/arm64
            runner: ubuntu-24.04-arm
    runs-on: ${{ matrix.runner }}
    outputs:
      version: ${{ steps.version.outputs.version }}
    steps:
      - uses: actions/checkout@v4
      - uses: docker/setup-buildx-action@v3
      - uses: docker/login-action@v3
        with:
          registry: ${{ env.REGISTRY }}
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}
      - name: Determine version
        id: version
        run: |
          VERSION="${{ needs.check-flutter.outputs.version || inputs.flutter_version }}"
          if [[ -z "$VERSION" ]]; then
            VERSION=$(curl -s https://storage.googleapis.com/flutter_infra_release/releases/releases_linux.json \
              | jq -r '.current_release.stable as $h | .releases[] | select(.hash==$h) | .version')
          fi
          echo "version=$VERSION" >> "$GITHUB_OUTPUT"
      - name: Build and push by digest
        id: build
        uses: docker/build-push-action@v6
        with:
          context: .
          file: flutter/Dockerfile
          target: ${{ matrix.target.name }}
          platforms: ${{ matrix.platform }}
          build-args: |
            FLUTTER_VERSION=${{ steps.version.outputs.version }}
          outputs: type=image,name=${{ env.NAMESPACE }}/${{ matrix.target.repo }},push-by-digest=true,name-canonical=true,push=true
      - name: Export digest
        run: |
          mkdir -p /tmp/digests
          digest="${{ steps.build.outputs.digest }}"
          touch "/tmp/digests/${digest#sha256:}"
      - name: Sanitize platform for artifact name
        id: sanitize
        run: echo "suffix=$(echo '${{ matrix.platform }}' | tr '/' '-')" >> "$GITHUB_OUTPUT"
      - uses: actions/upload-artifact@v4
        with:
          name: flutter-${{ matrix.target.name }}-digest-${{ steps.sanitize.outputs.suffix }}
          path: /tmp/digests/*
          if-no-files-found: error
          retention-days: 1
```

Key differences from the original job:
- Added `target` matrix dimension with paired `name` + `repo`.
- Added `target: ${{ matrix.target.name }}` to the `docker/build-push-action` invocation.
- Changed `outputs:` to reference `${{ matrix.target.repo }}` so each target lands in its own repo.
- Renamed the digest artifact to include the target name, so the merge job can fan out.
- Added `fail-fast: false` so one target failing doesn't cancel the rest.

- [ ] **Step 2: Replace the `merge-flutter` job with a per-target matrix**

In `.github/workflows/build.yml`, replace the `merge-flutter` job (currently lines 137-164) with:

```yaml
  # ── Flutter (merge multi-arch manifests, one per target) ────────
  merge-flutter:
    needs: [build-flutter]
    if: |
      always() && needs.build-flutter.result == 'success'
    runs-on: ubuntu-latest
    strategy:
      fail-fast: false
      matrix:
        target:
          - { name: base,        repo: flutter-base }
          - { name: base-ci,     repo: flutter-base-ci }
          - { name: android,     repo: flutter }
          - { name: android-ci,  repo: flutter-android-ci }
    steps:
      - uses: docker/setup-buildx-action@v3
      - uses: docker/login-action@v3
        with:
          registry: ${{ env.REGISTRY }}
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}
      - uses: actions/download-artifact@v4
        with:
          pattern: flutter-${{ matrix.target.name }}-digest-*
          merge-multiple: true
          path: /tmp/digests
      - name: Determine tags
        id: tags
        run: |
          VERSION="${{ needs.build-flutter.outputs.version }}"
          echo "tags=${{ env.NAMESPACE }}/${{ matrix.target.repo }}:stable,${{ env.NAMESPACE }}/${{ matrix.target.repo }}:${VERSION}" >> "$GITHUB_OUTPUT"
      - name: Create multi-arch manifest
        working-directory: /tmp/digests
        run: |
          TAGS=$(echo "${{ steps.tags.outputs.tags }}" | tr ',' '\n' | sed 's/^/-t /' | tr '\n' ' ')
          docker buildx imagetools create $TAGS \
            $(printf '${{ env.NAMESPACE }}/${{ matrix.target.repo }}@sha256:%s ' *)
      - name: Inspect published manifest
        run: |
          docker buildx imagetools inspect ${{ env.NAMESPACE }}/${{ matrix.target.repo }}:stable
```

Key differences from the original merge job:
- Added the same `target` matrix as `build-flutter` so each target gets its own manifest.
- `download-artifact` pattern now scoped by target name.
- Tags and manifest are scoped to `${{ matrix.target.repo }}`.
- Added `inspect` step (matches the pattern used by the PHP merge job).

- [ ] **Step 3: Update the schedule-only existence check**

The `check-flutter` job (currently lines 53-76) checks whether `flutter:<version>` already exists. Since the `flutter` repo (alias for the `android` target) is still being published, this check remains correct — leave it as-is. Verify by reading lines 53-76 and confirming the `docker manifest inspect ${{ env.NAMESPACE }}/flutter:$VERSION` line is unchanged.

- [ ] **Step 4: Lint the workflow**

Run: `actionlint .github/workflows/build.yml`
Expected: no errors. If `actionlint` isn't installed, run via Docker: `docker run --rm -v "$PWD:/repo" --workdir /repo rhysd/actionlint:latest -color`. Fix any findings.

- [ ] **Step 5: Validate with `gh workflow view`**

Run: `gh workflow view "Build Docker images" --yaml | head -20`
Expected: workflow parses cleanly and shows the updated definition (this catches YAML syntax errors `actionlint` may miss).

- [ ] **Step 6: Commit**

```bash
git add .github/workflows/build.yml
git commit -m "ci: build all four flutter image targets in parallel

Matrix over (target, platform). The android target keeps publishing to
the flutter repo for backwards compatibility; base, base-ci, and
android-ci publish to their own repos."
```

---

## Task 7: Open the PR

- [ ] **Step 1: Push the branch**

Run:
```bash
git push -u origin HEAD
```

- [ ] **Step 2: Open the PR**

Run:
```bash
gh pr create --title "flutter: split image into base/base-ci/android/android-ci" --body "$(cat <<'EOF'
## Summary
- Split the monolithic `flutter` Docker image into four multi-stage targets so consumers can pull just what they need.
- Drop both `extras;*;m2repository` packages (~500MB savings on the Android variant).
- Switch base to `debian:bookworm-slim`.
- Move `flutter precache --android`, JDK, Android SDK, NDK, Gradle warmup, and native build deps (`clang/cmake/ninja/libgtk-3-dev`) out of the base and into the `android` stage.
- Shared CI tooling (`lcov`, `jq`, `glab`, `cobertura`, `junitreport`) is defined once in `flutter/install-ci-tools.sh` and layered onto `base` and `android` to produce the `-ci` variants.

## Image sizes
<paste the table from Task 5 here>

## Tags published
- `ghcr.io/jpjonte/flutter:{stable,<version>}` → `android` target (backwards-compatible)
- `ghcr.io/jpjonte/flutter-base:{stable,<version>}`
- `ghcr.io/jpjonte/flutter-base-ci:{stable,<version>}`
- `ghcr.io/jpjonte/flutter-android-ci:{stable,<version>}`

## Test plan
- [ ] CI build job succeeds for all four targets on both linux/amd64 and linux/arm64
- [ ] Each multi-arch manifest is published and inspectable via `docker buildx imagetools inspect`
- [ ] Pull `ghcr.io/jpjonte/flutter:stable` and confirm `flutter doctor`, `sdkmanager --list_installed`, and an Android build still work (backwards-compat)
- [ ] Pull `ghcr.io/jpjonte/flutter-base:stable` and confirm `flutter --version` works without Android tooling present
- [ ] Pull `ghcr.io/jpjonte/flutter-base-ci:stable` and confirm `lcov`, `jq`, `glab`, `cobertura`, `junitreport` all run
EOF
)"
```

Expected: PR opens; CI kicks off the matrix build. Wait for green before merging.

---

## Self-Review Notes

Spec coverage check: split into base/android ✓, Debian slim ✓, CI variants for both ✓, drop both m2repository ✓, re-add CI tools (shared script) ✓, multi-stage Dockerfile ✓, written implementation plan ✓.

Type/name consistency check:
- Script name `install-ci-tools.sh` used consistently across Tasks 1, 2, and 4.
- Stage names `base`, `base-ci`, `android`, `android-ci` used consistently in Dockerfile, smoke tests, and workflow matrix.
- Repo names `flutter`, `flutter-base`, `flutter-base-ci`, `flutter-android-ci` used consistently in workflow build and merge jobs.
- `ANDROID_NDK_VERSION` (28.2.13676358) is the same value in the Dockerfile build arg, the `sdkmanager` invocation, and the smoke test path assertion.
