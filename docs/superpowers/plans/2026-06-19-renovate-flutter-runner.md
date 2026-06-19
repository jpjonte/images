# Flutter-equipped Renovate runner — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Bake Flutter into a custom `ghcr.io/jpjonte/renovate` image so the self-hosted Renovate runner refreshes `pubspec.lock` (and flags unresolvable pub bumps) without dropping containerbase for the other managed repos.

**Architecture:** A new Dockerfile layers the Flutter SDK onto the stock Renovate image and keeps `binarySource: install` (default). The `docker` repo's CI builds and publishes it multi-arch; the `argocd` Renovate CronJob is repointed at it; a small `life-tracker` config cleanup follows. The design rests on one inferred behaviour (the `pub` manager using the `PATH` Flutter under `binarySource: install`), gated by a dry-run before the live cutover.

**Tech Stack:** Docker (multi-stage, multi-arch buildx), GitHub Actions (the `docker` repo's `build.yml`), Flutter SDK, Renovate (self-hosted, Forgejo platform), Argo CD / Kubernetes CronJob, JSON5 Renovate config.

**Reference spec:** `docs/superpowers/specs/2026-06-19-renovate-flutter-runner-design.md`

## Global Constraints

- **Base image = the default (slim) Renovate image**, NOT `-full`. It is the containerbase image already in use; keeping it preserves `binarySource: install`.
- **`binarySource` stays `install`** (the default). Do NOT set it to `global`. This is what keeps containerbase auto-installing PHP/Composer/etc. for `bud/pantry`.
- **Flutter pinned to `3.44.1`** — life-tracker's `.fvmrc`. Must stay ≥ life-tracker's Flutter so its bundled Dart satisfies `pubspec`'s `environment.sdk: '>=3.12.0 <4.0.0'`.
- **Image runs as UID 1000**, matching the CronJob's `runAsUser: 1000`; `/opt/flutter` must be owned by 1000.
- **Multi-arch amd64 + arm64**, following the existing `build-flutter` / `_image.yml` pattern.
- **No regression for `bud/pantry`** — containerbase tool auto-install must remain intact.
- **`life-tracker` repo conventions** (Task 6 only): branch `prefix/issue-slug`, commit `#<issue> message`, a `CHANGELOG.md` entry under today's date, `fvm dart format` / `fvm flutter analyze` before push, PR body with `Closes #XXX`.

## Repos & cross-repo ordering

This plan spans three repos. Order matters because the cluster can only pull the image after the `docker` PR merges and CI publishes it:

1. `docker` — Tasks 1–2 (image + CI), Task 3 (local dry-run gate). **Then merge the `docker` PR so CI publishes `ghcr.io/jpjonte/renovate:43.232.0`.**
2. `argocd` — Task 4 (cutover). Merge → Argo CD rolls the new image onto the live CronJob.
3. `life-tracker` — Task 5 (config cleanup + close PR #379).

Work in the existing `docker` branch `feat/renovate-flutter-image` (already created; holds the spec commit) for Tasks 1–2.

## File structure

| Repo | File | Responsibility |
|------|------|----------------|
| docker | `renovate/Dockerfile` (create) | Stock Renovate image + baked Flutter SDK on PATH, runs as UID 1000 |
| docker | `.github/workflows/build.yml` (modify) | `changes` filter + `check-renovate` freshness job + `build-renovate` / `merge-renovate` jobs |
| argocd | `apps/renovate/values.yaml` (modify) | Repoint `image:` to `ghcr.io/jpjonte/renovate` + update the `# renovate:` annotation |
| life-tracker | `renovate.json5` (modify) | Refresh the stale `lockFileMaintenance` NOTE; add a temporary `share_plus` major hold |
| life-tracker | `CHANGELOG.md` (modify) | `Internal` entry under today's date |

---

### Task 1: Custom Renovate + Flutter image

**Files:**
- Create: `renovate/Dockerfile` (in the `docker` repo)

**Interfaces:**
- Consumes: `ghcr.io/renovatebot/renovate:${RENOVATE_VERSION}` (build arg), Flutter `${FLUTTER_VERSION}` git branch.
- Produces: an image with `flutter` and `dart` on `PATH`, runnable as UID 1000, whose default entrypoint is still Renovate's. Build args: `RENOVATE_VERSION` (no default — caller supplies), `FLUTTER_VERSION` (default `3.44.1`).

- [ ] **Step 1: Create the Dockerfile**

Create `renovate/Dockerfile`:

```dockerfile
# syntax=docker/dockerfile:1

# Stock Renovate (the default containerbase image, NOT -full) with the Flutter
# SDK baked on PATH. Renovate's pub manager needs `flutter`/`dart` to refresh
# pubspec.lock; containerbase has no dart/flutter tool, so we add it here and
# leave binarySource at its default (install) — that keeps containerbase
# auto-installing PHP/Composer/etc. for the other managed repos.
ARG RENOVATE_VERSION
ARG FLUTTER_VERSION=3.44.1
FROM ghcr.io/renovatebot/renovate:${RENOVATE_VERSION}

# Re-declare after FROM so it is in scope for the RUN below.
ARG FLUTTER_VERSION

USER root

# Flutter's first-run Dart SDK bootstrap (bin/internal/update_dart_sdk.sh) needs
# curl + unzip; git + ca-certificates are already present but asserted for safety.
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
       ca-certificates curl git unzip xz-utils \
    && rm -rf /var/lib/apt/lists/*

ENV FLUTTER_HOME=/opt/flutter
ENV PATH="${FLUTTER_HOME}/bin:${FLUTTER_HOME}/bin/cache/dart-sdk/bin:${PATH}"

# Shallow clone, keep .git (Flutter self-identifies via `git rev-parse`), then
# hand ownership to UID 1000 so the runtime user can write bin/cache.
RUN git clone --branch "${FLUTTER_VERSION}" --depth 1 \
      https://github.com/flutter/flutter.git "${FLUTTER_HOME}" \
    && git config --system --add safe.directory "${FLUTTER_HOME}" \
    && chown -R 1000:1000 "${FLUTTER_HOME}"

USER 1000

# Bake the Dart SDK + universal artifacts so nothing downloads at cron time.
RUN flutter config --no-analytics \
    && flutter precache --universal --no-android --no-ios --no-linux \
       --no-windows --no-macos --no-web \
    && flutter --version
```

- [ ] **Step 2: Build the image locally (amd64) to verify it assembles**

Run:
```bash
cd /Users/bud/dev/private/server/docker
docker build \
  --build-arg RENOVATE_VERSION=43.232.0 \
  --build-arg FLUTTER_VERSION=3.44.1 \
  -f renovate/Dockerfile \
  -t jpjonte/renovate:test .
```
Expected: build succeeds; the `flutter precache` / `flutter --version` layer prints a Flutter `3.44.1` banner. If `apt-get` fails (containerbase lockdown) or Flutter's Dart bootstrap fails (missing `curl`/`unzip`), fix here — this is the layer that proves those assumptions.

- [ ] **Step 3: Smoke-test the toolchain as the runtime user**

Run:
```bash
docker run --rm --user 1000 --entrypoint bash jpjonte/renovate:test -lc \
  'flutter --version && dart --version && flutter pub --help >/dev/null && echo OK'
```
Expected: Flutter `3.44.1` + Dart version banners, then `OK`. Confirms `flutter`/`dart` resolve on `PATH` for UID 1000 and `flutter pub` is usable.

- [ ] **Step 4: Commit**

```bash
cd /Users/bud/dev/private/server/docker
git add renovate/Dockerfile
git commit -m "feat(renovate): bake Flutter into a custom Renovate image

Layers the Flutter SDK (pinned 3.44.1) onto the stock Renovate image so the
pub manager can refresh pubspec.lock. Keeps the default (slim) base and
binarySource=install, so containerbase still serves the other managers.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: CI build & publish pipeline

**Files:**
- Modify: `.github/workflows/build.yml` (in the `docker` repo)

**Interfaces:**
- Consumes: the existing `changes` (paths-filter) job, the `_image.yml` conventions, `secrets.GITHUB_TOKEN`, `env.NAMESPACE = ghcr.io/jpjonte`.
- Produces: published tags `ghcr.io/jpjonte/renovate:<renovate-version>` and `:latest`, multi-arch, built from `renovate/Dockerfile` with `RENOVATE_VERSION` + `FLUTTER_VERSION` build args.

- [ ] **Step 1: Add a `renovate` path filter to the `changes` job**

In `.github/workflows/build.yml`, add the output and filter to the `changes` job. Add to its `outputs:` block:
```yaml
      renovate: ${{ steps.filter.outputs.renovate }}
```
And add to the `dorny/paths-filter` `filters:` block:
```yaml
            renovate:
              - 'renovate/**'
```

- [ ] **Step 2: Add the scheduled freshness check job**

After the `check-flutter` job, add a `check-renovate` job that builds only when upstream publishes a Renovate version we have not built:
```yaml
  # ── Check for new Renovate version (schedule only) ───────────────
  check-renovate:
    if: github.event_name == 'schedule'
    runs-on: ubuntu-latest
    outputs:
      build: ${{ steps.check.outputs.build }}
      version: ${{ steps.check.outputs.version }}
    steps:
      - name: Check latest Renovate release
        id: check
        run: |
          VERSION=$(curl -fsSL https://api.github.com/repos/renovatebot/renovate/releases/latest \
            | jq -r '.tag_name')
          echo "Latest Renovate version: $VERSION"
          echo "version=$VERSION" >> "$GITHUB_OUTPUT"

          if docker manifest inspect ${{ env.NAMESPACE }}/renovate:$VERSION > /dev/null 2>&1; then
            echo "Renovate $VERSION already exists in GHCR"
            echo "build=false" >> "$GITHUB_OUTPUT"
          else
            echo "New Renovate version: $VERSION"
            echo "build=true" >> "$GITHUB_OUTPUT"
          fi
        env:
          DOCKER_CLI_EXPERIMENTAL: enabled
```

- [ ] **Step 3: Add the multi-arch build job**

After `merge-flutter`, add the `build-renovate` job (mirrors `build-flutter`, single target):
```yaml
  # ── Renovate + Flutter (per-platform build) ─────────────────────
  build-renovate:
    needs: [changes, check-renovate]
    if: |
      always() && (
        (github.event_name == 'push' && needs.changes.outputs.renovate == 'true') ||
        (github.event_name == 'schedule' && needs.check-renovate.outputs.build == 'true') ||
        github.event_name == 'workflow_dispatch'
      )
    strategy:
      fail-fast: false
      matrix:
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
      - uses: actions/checkout@v6
      - uses: docker/setup-buildx-action@v4
      - uses: docker/login-action@v4
        with:
          registry: ${{ env.REGISTRY }}
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}
      - name: Determine Renovate version
        id: version
        run: |
          VERSION="${{ needs.check-renovate.outputs.version }}"
          if [[ -z "$VERSION" ]]; then
            VERSION=$(curl -fsSL https://api.github.com/repos/renovatebot/renovate/releases/latest \
              | jq -r '.tag_name')
          fi
          echo "version=$VERSION" >> "$GITHUB_OUTPUT"
      - name: Sanitize platform for artifact name
        id: sanitize
        run: echo "suffix=$(echo '${{ matrix.platform }}' | tr '/' '-')" >> "$GITHUB_OUTPUT"
      - name: Build and push by digest
        id: build
        uses: docker/build-push-action@v7
        with:
          context: .
          file: renovate/Dockerfile
          platforms: ${{ matrix.platform }}
          build-args: |
            RENOVATE_VERSION=${{ steps.version.outputs.version }}
            FLUTTER_VERSION=3.44.1
          outputs: type=image,name=${{ env.NAMESPACE }}/renovate,push-by-digest=true,name-canonical=true,push=true
      - name: Export digest
        run: |
          mkdir -p /tmp/digests
          digest="${{ steps.build.outputs.digest }}"
          touch "/tmp/digests/${digest#sha256:}"
      - uses: actions/upload-artifact@v7
        with:
          name: renovate-digest-${{ steps.sanitize.outputs.suffix }}
          path: /tmp/digests/*
          if-no-files-found: error
          retention-days: 1
```

- [ ] **Step 4: Add the manifest-merge job**

After `build-renovate`, add `merge-renovate` (mirrors `merge-flutter`):
```yaml
  # ── Renovate (merge multi-arch manifest) ────────────────────────
  merge-renovate:
    needs: [build-renovate]
    if: always() && needs.build-renovate.result == 'success'
    runs-on: ubuntu-latest
    steps:
      - uses: docker/setup-buildx-action@v4
      - uses: docker/login-action@v4
        with:
          registry: ${{ env.REGISTRY }}
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}
      - uses: actions/download-artifact@v8
        with:
          pattern: renovate-digest-*
          merge-multiple: true
          path: /tmp/digests
      - name: Validate digest count
        run: |
          digest_count=$(find /tmp/digests -maxdepth 1 -type f 2>/dev/null | wc -l | tr -d ' ')
          if [ "$digest_count" -lt 2 ]; then
            echo "Only $digest_count digest(s) for renovate — need at least 2 for multi-arch." >&2
            exit 1
          fi
      - name: Determine tags
        id: tags
        run: |
          VERSION="${{ needs.build-renovate.outputs.version }}"
          echo "tags=${{ env.NAMESPACE }}/renovate:latest,${{ env.NAMESPACE }}/renovate:${VERSION}" >> "$GITHUB_OUTPUT"
      - name: Create multi-arch manifest
        working-directory: /tmp/digests
        run: |
          TAGS=$(echo "${{ steps.tags.outputs.tags }}" | tr ',' '\n' | sed 's/^/-t /' | tr '\n' ' ')
          docker buildx imagetools create $TAGS \
            $(printf '${{ env.NAMESPACE }}/renovate@sha256:%s ' *)
      - name: Inspect published manifest
        run: |
          docker buildx imagetools inspect ${{ env.NAMESPACE }}/renovate:latest
```

- [ ] **Step 5: Lint the workflow**

Run:
```bash
cd /Users/bud/dev/private/server/docker
actionlint .github/workflows/build.yml
```
Expected: no errors. If `actionlint` is not installed, instead run `python3 -c 'import yaml,sys; yaml.safe_load(open(".github/workflows/build.yml")); print("yaml ok")'` and re-read the diff against the `build-flutter`/`merge-flutter` jobs to confirm job names, `needs:`, and `if:` expressions are consistent.

- [ ] **Step 6: Commit**

```bash
cd /Users/bud/dev/private/server/docker
git add .github/workflows/build.yml
git commit -m "ci(renovate): build & publish the Flutter-equipped Renovate image

Adds a renovate/** path filter, a scheduled freshness check against the
latest renovatebot/renovate release, and multi-arch build+merge jobs that
publish ghcr.io/jpjonte/renovate:<version> and :latest.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: Dry-run verification gate (the inferred behaviour)

**Files:** none (verification only — produces a go/no-go, not a commit).

**Interfaces:**
- Consumes: the local `jpjonte/renovate:test` image from Task 1, a Forgejo bot token with read access to `bud/life-tracker` and `bud/pantry`.
- Produces: confirmation that (a) the pub manager uses the `PATH` Flutter under `binarySource: install`, and (b) containerbase still serves pantry.

> **Requires `RENOVATE_TOKEN`** — the Forgejo bot token (sealed in-cluster via `argocd/seal-staging/seal-renovate.sh`). Export it locally for this gate, or hand these commands to the operator who holds it. Do not commit or echo the token.

- [ ] **Step 1: Rebuild the test image at the target Renovate version (if not already present)**

Run:
```bash
cd /Users/bud/dev/private/server/docker
docker build --build-arg RENOVATE_VERSION=43.232.0 --build-arg FLUTTER_VERSION=3.44.1 \
  -f renovate/Dockerfile -t jpjonte/renovate:test .
```
Expected: cached build completes.

- [ ] **Step 2: Dry-run against life-tracker and confirm lockfile handling**

Run:
```bash
docker run --rm \
  -e RENOVATE_TOKEN="$RENOVATE_TOKEN" \
  -e RENOVATE_PLATFORM=forgejo \
  -e RENOVATE_ENDPOINT=https://forge.jpj.dev/api/v1 \
  -e RENOVATE_AUTODISCOVER=false \
  -e RENOVATE_DRY_RUN=full \
  -e LOG_LEVEL=debug \
  jpjonte/renovate:test bud/life-tracker 2>&1 | tee /tmp/rv-life-tracker.log
```
Expected in the log:
- a `flutter pub get` (or `dart pub get`) invocation for the pub manager — proves the `PATH` Flutter is used while `binarySource` is `install`;
- a would-be `pubspec.lock` update on at least one resolvable branch;
- for the `share_plus 13` branch, an **artifact update error** (unresolvable solve) rather than a silent pass.

Grep helpers:
```bash
grep -iE 'flutter pub|dart pub|pubspec.lock|artifact' /tmp/rv-life-tracker.log | head -40
```
If there is NO `flutter pub`/`dart pub` line, the inferred behaviour failed → STOP and switch to the spec's fallback (separate life-tracker CronJob with `binarySource: global`); do not proceed to Task 4.

- [ ] **Step 3: Dry-run against pantry and confirm containerbase is intact**

Run:
```bash
docker run --rm \
  -e RENOVATE_TOKEN="$RENOVATE_TOKEN" \
  -e RENOVATE_PLATFORM=forgejo \
  -e RENOVATE_ENDPOINT=https://forge.jpj.dev/api/v1 \
  -e RENOVATE_AUTODISCOVER=false \
  -e RENOVATE_DRY_RUN=full \
  -e LOG_LEVEL=debug \
  jpjonte/renovate:test bud/pantry 2>&1 | tee /tmp/rv-pantry.log
```
Expected: pantry's managers run normally; if pantry has composer/npm artifacts, the log shows containerbase installing the tool (`install-tool` / `containerbase`) and no regression vs. the stock image. A clean run (no tool-resolution errors) is the pass condition.

- [ ] **Step 4: Record the gate result**

Append a short PASS/FAIL note (with the decisive log lines) to the PR description for the `docker` branch. PASS → proceed. FAIL → fallback per the spec.

---

> **CHECKPOINT — publish the image.** Open the `docker` PR from `feat/renovate-flutter-image` (spec + Tasks 1–2), get it reviewed, and merge. Confirm the `Build Docker images` workflow publishes `ghcr.io/jpjonte/renovate:43.232.0` and `:latest` (workflow_dispatch the build if the push filter did not trigger it). The cluster cannot pull the image until this is done.

---

### Task 4: Repoint the Argo CD Renovate CronJob

**Files:**
- Modify: `apps/renovate/values.yaml` (in the `argocd` repo)

**Interfaces:**
- Consumes: the published `ghcr.io/jpjonte/renovate:43.232.0`.
- Produces: the live CronJob running the Flutter-equipped image; the `customManagers` `image:` regex in `argocd/renovate.json` now tracks `ghcr.io/jpjonte/renovate` tags.

- [ ] **Step 1: Branch off `origin/main`**

Run:
```bash
cd /Users/bud/dev/private/server/argocd
git fetch origin
git checkout -b feat/renovate-flutter-runner origin/main
```

- [ ] **Step 2: Update the image and annotation**

In `apps/renovate/values.yaml`, replace the image block. Change the comment's `depName` and the image path; keep the tag at the current Renovate version (`43.232.0`), since our image is tagged by the upstream Renovate version it is built from:

From:
```yaml
# renovate: datasource=docker depName=ghcr.io/renovatebot/renovate
image: ghcr.io/renovatebot/renovate:43.232.0
```
To:
```yaml
# Custom Renovate image (renovatebot/renovate + baked Flutter) built in the
# docker repo (renovate/Dockerfile). Tagged by the upstream Renovate version it
# is built from, so the customManagers image: regex in renovate.json bumps it
# as new tags are published.
# renovate: datasource=docker depName=ghcr.io/jpjonte/renovate
image: ghcr.io/jpjonte/renovate:43.232.0
```

- [ ] **Step 3: Verify the manifest still renders**

Run:
```bash
cd /Users/bud/dev/private/server/argocd
helm template apps/renovate 2>&1 | grep -E 'image:|name: renovate' | head
```
Expected: the rendered CronJob shows `image: ghcr.io/jpjonte/renovate:43.232.0`. (If `helm template` needs a values path, use `helm template apps/renovate -f apps/renovate/values.yaml`.)

- [ ] **Step 4: Commit and open the PR**

```bash
cd /Users/bud/dev/private/server/argocd
git add apps/renovate/values.yaml
git commit -m "renovate: switch runner to the Flutter-equipped image

Repoints the Renovate CronJob at ghcr.io/jpjonte/renovate so the pub manager
can refresh pubspec.lock for bud/life-tracker. binarySource stays install, so
containerbase still serves bud/pantry. Image tag tracks upstream Renovate.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```
Then open the PR with `fj pr create` (or the repo's usual flow). After merge, confirm Argo CD syncs and the next CronJob run uses the new image (check the pod image and that a life-tracker run produces a `pubspec.lock` update).

---

### Task 5: life-tracker config cleanup + close PR #379

**Files:**
- Modify: `renovate.json5` (in `life-tracker`)
- Modify: `CHANGELOG.md` (in `life-tracker`)

**Interfaces:**
- Consumes: the live Flutter-equipped runner (Task 4 merged).
- Produces: an accurate `lockFileMaintenance` note and a temporary `share_plus` major hold; PR #379 closed.

- [ ] **Step 1: Create the tracking issue and branch**

Run (from the `life-tracker` repo):
```bash
cd /Users/bud/dev/private/projects/life-tracker
fj issue create --title "Refresh Renovate lockfile note; hold share_plus until health is win32-6 compatible" \
  --body "The Renovate runner now bakes in Flutter (ghcr.io/jpjonte/renovate), so it refreshes pubspec.lock. Update the stale lockFileMaintenance NOTE and add a temporary hold on share_plus major (blocked by health 13.3.1 pinning win32 ^5 via device_info_plus). Remove the hold when health moves to win32 6."
# note the issue number it prints, then:
git fetch origin && git checkout -b chore/<issue>-renovate-lockfile-note origin/main
```

- [ ] **Step 2: Refresh the `lockFileMaintenance` NOTE comment**

In `renovate.json5`, replace the NOTE above `lockFileMaintenance` (currently lines ~23–26):

From:
```json5
  // Refresh transitive deps within existing constraints, then automerge once green.
  // NOTE: this depends on the Renovate runner being able to run `flutter pub` to
  // refresh pubspec.lock — verify in the first dry run; disable if the bot lacks
  // Flutter.
  lockFileMaintenance: {
```
To:
```json5
  // Refresh transitive deps within existing constraints, then automerge once green.
  // The runner is the custom ghcr.io/jpjonte/renovate image, which bakes in
  // Flutter so `flutter pub get` can refresh pubspec.lock (see the docker repo's
  // renovate/Dockerfile and the argocd renovate deployment).
  lockFileMaintenance: {
```

- [ ] **Step 3: Add the temporary `share_plus` hold**

In the `packageRules` "Suppressions" block of `renovate.json5`, add (use the real issue number from Step 1):
```json5
    // TEMPORARY: share_plus 13 needs win32 ^6, but health 13.3.1 pins win32 ^5
    // via device_info_plus, so the solve is unsatisfiable (was PR #379). Hold
    // share_plus at its current major until health moves to win32 6, then delete
    // this rule. (#<issue>)
    {
      matchPackageNames: ['share_plus'],
      matchUpdateTypes: ['major'],
      enabled: false,
    },
```

- [ ] **Step 4: Validate the Renovate config**

Run:
```bash
cd /Users/bud/dev/private/projects/life-tracker
npx --yes --package renovate -- renovate-config-validator renovate.json5
```
Expected: `Config validated successfully`.

- [ ] **Step 5: Add the CHANGELOG entry**

In `CHANGELOG.md`, under today's date (`YYYY-MM-DD`; create the day section at the top if absent), add to the `Internal` category (use the real issue number):
```markdown
- Refresh the Renovate lockfile-maintenance note and temporarily hold `share_plus` major until `health` is win32-6 compatible (#<issue>)
```

- [ ] **Step 6: Commit, push, open PR, and close #379**

```bash
cd /Users/bud/dev/private/projects/life-tracker
git add renovate.json5 CHANGELOG.md
git commit -m "#<issue> refresh Renovate lockfile note; hold share_plus major"
git push -u origin chore/<issue>-renovate-lockfile-note
fj pr create --title "#<issue> Renovate lockfile note + share_plus hold" \
  --body "Closes #<issue>"
fj pr close 379
```
Expected: PR opens; PR #379 (`Update dependency share_plus to v13`) is closed.

---

## Self-review

**Spec coverage:**
- §Component 1 (image) → Task 1. ✓
- §Component 2 (pipeline) → Task 2. ✓
- §Component 3 (deployment) → Task 4. ✓
- §Component 4 (life-tracker cleanup + #379) → Task 5. ✓
- §Verification → Task 3 (gate before cutover, with the fallback call-out). ✓
- §Chosen approach constraints (default image, `binarySource: install`, Flutter pin, UID 1000, multi-arch, no pantry regression) → Global Constraints + enforced in Tasks 1–2. ✓

**Placeholder scan:** `<issue>` in Task 5 is a real value produced by Step 1, not a plan gap. No TBD/TODO/"handle edge cases". Dockerfile, both CI jobs, the values.yaml diff, and the renovate.json5 diffs are shown in full.

**Type/name consistency:** image name `ghcr.io/jpjonte/renovate` and tag scheme `:<renovate-version>` + `:latest` are consistent across Tasks 2, 3, 4. Build args `RENOVATE_VERSION` / `FLUTTER_VERSION` match between Dockerfile (Task 1) and the build job (Task 2). Branch `feat/renovate-flutter-image` (docker) holds the spec + Tasks 1–2; `feat/renovate-flutter-runner` (argocd) for Task 4; `chore/<issue>-…` (life-tracker) for Task 5.
