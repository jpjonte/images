# Multi-Arch PHP Images Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Publish `ghcr.io/jpjonte/php:8.4` and `ghcr.io/jpjonte/php:8.5` as multi-arch manifest lists (`linux/amd64` + `linux/arm64`) so consumers on Apple Silicon pull a native arm64 image and no QEMU emulation is required.

**Architecture:** The Dockerfiles (`php/8.4/Dockerfile`, `php/8.5/Dockerfile`) already inherit from `php:X-fpm-alpine`, which is upstream multi-arch, and `install-php-extensions` supports arm64. The problem is purely CI: `build-php` in `.github/workflows/build.yml` runs only on `ubuntu-latest` (amd64) and pushes a single-arch image. The fix mirrors the proven pattern already shipping for `build-flutter`: a `(version × platform)` matrix that pushes each arch as a detached digest, then a per-version `merge-php` job that composes the digests into a manifest list. Legacy `.gitlab-ci.yml` is not modified in this plan; the GitHub Actions workflow is the source of truth.

**Tech Stack:** GitHub Actions, `docker/build-push-action@v6`, `docker/buildx`, `docker buildx imagetools`, GHCR (`ghcr.io/jpjonte/*`), Alpine PHP-FPM base, `mlocati/docker-php-extension-installer`.

**Repo under change:** `/Users/bud/dev/private/server/docker` (the main branch is `main`).

**Downstream consumer to verify:** `/Users/bud/dev/private/projects/pantry` (`api` service in `docker-compose.yml`; derived image `pantry/php:latest` built from `api/api/Dockerfile` which inherits from `ghcr.io/jpjonte/php:8.5`).

---

## Background (read before starting)

### Why this plan exists

On an Apple Silicon Mac (arm64), running Pantry's `api` service via `docker compose up api` produces:

```
api-1  | qemu-x86_64: QEMU internal SIGSEGV {code=MAPERR, addr=0xffff79d10300}
```

`docker manifest inspect ghcr.io/jpjonte/php:8.5` currently returns a single `manifest.v2+json` with `platform.architecture=amd64` — no arm64 variant. Docker Desktop therefore emulates x86_64, and on hosts where the Rosetta backend is not active the emulator is plain QEMU, whose TCG engine SIGSEGVs once `php-fpm` forks worker processes.

### Why this is *only* a CI problem

- `php/8.5/Dockerfile` line 1: `FROM php:8.5-fpm-alpine` — **upstream multi-arch** (amd64, arm64, arm/v7, …).
- `php/scripts/extensions.sh` uses `install-php-extensions` (mlocati/docker-php-extension-installer) — **multi-arch** (supports arm64).
- `php/scripts/packages.sh` installs `curl`, `acl`, `bash` via `apk` — all available on arm64.

Nothing in the Dockerfile is architecture-specific. Building it on an arm64 runner produces a working arm64 image. The existing `build-php` job just never builds on arm64.

### Why mirror the Flutter job?

`build-flutter` in the same workflow already solves the multi-arch problem cleanly:

- Matrix: `{ platform: linux/amd64, runner: ubuntu-latest }` and `{ platform: linux/arm64, runner: ubuntu-24.04-arm }`.
- Each build pushes by digest (`outputs: type=image,...,push-by-digest=true,name-canonical=true,push=true`).
- Digests are uploaded as artifacts.
- A `merge-flutter` job downloads both digest artifacts and runs `docker buildx imagetools create` to publish the manifest list.

This plan applies the same pattern to `build-php`, extended with an outer `version` dimension (`8.4`, `8.5`), and adds a `merge-php` job.

### What we are NOT changing

- `php/scripts/*.sh` — untouched.
- `php/8.4/Dockerfile`, `php/8.5/Dockerfile` — untouched.
- `.gitlab-ci.yml` — out of scope. Called out at the end if you want a follow-up.
- `kubectl` image — still single-arch. Not driving the Pantry QEMU crash. Follow-up issue.
- Pantry's `api/api/Dockerfile` — untouched. Once the base is multi-arch, derived image is multi-arch transparently.

---

## File Structure

```
/Users/bud/dev/private/server/docker/
├── .github/workflows/build.yml         # MODIFY: replace build-php, add merge-php
└── docs/superpowers/plans/
    └── 2026-04-19-multi-arch-php-images.md   # this plan
```

One file touched. The plan is deliberately small-surface — everything else (Dockerfiles, scripts, registry, consumers) already works.

---

## Prerequisites

- GitHub Actions `ubuntu-24.04-arm` runner is available for this org (it is — `build-flutter` already uses it).
- GHCR push credentials via `GITHUB_TOKEN` (already configured — same job uses it).
- Local tooling for pre-merge verification: Docker Desktop ≥ 4.24 with buildx; `docker buildx ls` shows a builder that can cross-compile (the default `desktop-linux` on Apple Silicon is fine via QEMU — this is the one place QEMU is acceptable because we only want to prove the build succeeds, not run the result).

---

## Task 1: Baseline — capture current manifest state

**Files:**
- No file changes. This task records evidence before we alter anything.

- [ ] **Step 1: Record current `php:8.5` manifest**

Run:
```bash
docker manifest inspect ghcr.io/jpjonte/php:8.5 --verbose | tee /tmp/php-85-before.json | head -c 600
```

Expected: a single `manifest.v2+json` (NOT `manifest.list.v2+json`) with `Descriptor.platform.architecture=amd64`. Save `/tmp/php-85-before.json` for diff at the end.

- [ ] **Step 2: Record current `php:8.4` manifest**

Run:
```bash
docker manifest inspect ghcr.io/jpjonte/php:8.4 --verbose | tee /tmp/php-84-before.json | head -c 600
```

Expected: single-arch amd64, same as 8.5.

- [ ] **Step 3: Confirm upstream base is multi-arch (sanity)**

Run:
```bash
docker manifest inspect php:8.5-fpm-alpine | jq '.manifests[].platform'
```

Expected output includes both:
```json
{ "architecture": "amd64", "os": "linux" }
{ "architecture": "arm64", "os": "linux" }
```

If arm64 is missing, STOP — the premise of this plan (upstream is multi-arch) is false and you need to pick a different base image. As of writing, Docker Official Images publish arm64 for all maintained PHP tags, so this should pass.

- [ ] **Step 4: Commit the plan itself**

Run:
```bash
cd /Users/bud/dev/private/server/docker
git checkout -b multi-arch-php
git add docs/superpowers/plans/2026-04-19-multi-arch-php-images.md
git commit -m "docs: add multi-arch PHP images plan"
```

---

## Task 2: Locally verify the Dockerfile builds on arm64

**Why:** Before we touch CI, prove the Dockerfile itself (unchanged) builds successfully when `--platform=linux/arm64` is requested. If it fails, CI will also fail, and we need to fix the Dockerfile first. This task is cheap insurance — maybe 5–10 min of build time per version.

**Files:**
- No file changes.

- [ ] **Step 1: Create a disposable buildx builder with multi-platform support**

Run:
```bash
docker buildx create --name pantry-multiarch --driver docker-container --bootstrap
docker buildx use pantry-multiarch
docker buildx inspect | grep -i platforms
```

Expected: `Platforms` line includes `linux/amd64` and `linux/arm64` (plus possibly others via QEMU).

- [ ] **Step 2: Build `php:8.5` for arm64 locally, no push**

Run from `/Users/bud/dev/private/server/docker`:
```bash
docker buildx build \
  --platform linux/arm64 \
  --file php/8.5/Dockerfile \
  --tag local/php:8.5-arm64-test \
  --load \
  .
```

Expected: build completes without error. `install-php-extensions` should print each extension installing successfully. If any extension errors with "not supported on aarch64" — STOP and open an upstream issue with `mlocati/docker-php-extension-installer`; this plan is blocked.

- [ ] **Step 3: Smoke-test the arm64 image actually runs**

Run:
```bash
docker run --rm --platform linux/arm64 local/php:8.5-arm64-test php -v
docker run --rm --platform linux/arm64 local/php:8.5-arm64-test php -m | sort
```

Expected: `php -v` prints `PHP 8.5.x (cli)` without a QEMU SIGSEGV (the native arm64 binary needs no emulation; if *this* fails with SIGSEGV, Docker Desktop is still using QEMU for amd64 — but since we built for arm64, it shouldn't be). `php -m` should include: `apcu`, `bcmath`, `bz2`, `calendar`, `exif`, `gd`, `gmp`, `imagick`, `imap`, `intl`, `mysqli`, `opcache`, `pcntl`, `pcov`, `pdo_mysql`, `pdo_pgsql`, `pgsql`, `redis`, `soap`, `xsl`, `zip`.

- [ ] **Step 4: Repeat for `php:8.4`**

Run:
```bash
docker buildx build \
  --platform linux/arm64 \
  --file php/8.4/Dockerfile \
  --tag local/php:8.4-arm64-test \
  --load \
  .
docker run --rm --platform linux/arm64 local/php:8.4-arm64-test php -v
```

Expected: prints `PHP 8.4.x`.

- [ ] **Step 5: Tear down the builder**

Run:
```bash
docker buildx use default
docker buildx rm pantry-multiarch
docker image rm local/php:8.5-arm64-test local/php:8.4-arm64-test
```

No commit — this task is verification only.

---

## Task 3: Rewrite `build-php` as a per-platform matrix

**Files:**
- Modify: `.github/workflows/build.yml` — replace the existing `build-php` job (around lines 160–188, verify with `grep`).

**Context for the replacement:** The current job has a 2-row version matrix with `exclude` entries that skip versions whose paths didn't change. The replacement keeps that semantics but adds an inner platform dimension, so the effective matrix is up to `(2 versions) × (2 platforms) = 4 jobs`, still filtered by `paths-filter` outputs.

- [ ] **Step 1: Locate the current `build-php` block**

Run:
```bash
grep -n '^  build-php:' /Users/bud/dev/private/server/docker/.github/workflows/build.yml
```

Expected: a single match around line 161. Everything from that line through the end of the `uses: docker/build-push-action@v6` step (the `tags:` line) is the current job.

- [ ] **Step 2: Replace the `build-php` job**

Edit `.github/workflows/build.yml`. Replace the entire existing `build-php` job (from `  # ── PHP ──...` header through the closing of its last step, inclusive) with this exact block. Preserve the `# ── PHP ──` banner.

```yaml
  # ── PHP (per-platform build) ────────────────────────────────────
  build-php:
    needs: [changes]
    if: |
      always() && (
        (github.event_name == 'push' && (needs.changes.outputs.php-8_4 == 'true' || needs.changes.outputs.php-8_5 == 'true')) ||
        github.event_name == 'workflow_dispatch'
      )
    strategy:
      fail-fast: false
      matrix:
        version: ['8.4', '8.5']
        platform:
          - linux/amd64
          - linux/arm64
        include:
          - platform: linux/amd64
            runner: ubuntu-latest
          - platform: linux/arm64
            runner: ubuntu-24.04-arm
        exclude:
          - version: ${{ github.event_name == 'push' && needs.changes.outputs.php-8_4 != 'true' && '8.4' || 'never' }}
          - version: ${{ github.event_name == 'push' && needs.changes.outputs.php-8_5 != 'true' && '8.5' || 'never' }}
    runs-on: ${{ matrix.runner }}
    steps:
      - uses: actions/checkout@v4
      - uses: docker/setup-buildx-action@v3
      - uses: docker/login-action@v3
        with:
          registry: ${{ env.REGISTRY }}
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}
      - name: Build and push by digest
        id: build
        uses: docker/build-push-action@v6
        with:
          context: .
          file: php/${{ matrix.version }}/Dockerfile
          platforms: ${{ matrix.platform }}
          outputs: type=image,name=${{ env.NAMESPACE }}/php,push-by-digest=true,name-canonical=true,push=true
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
          name: php-${{ matrix.version }}-digest-${{ steps.sanitize.outputs.suffix }}
          path: /tmp/digests/*
          if-no-files-found: error
          retention-days: 1
```

> **Note on matrix semantics:** `platform` must be declared as a top-level matrix key so it cross-products with `version`. If you try to introduce it solely via `include:`, the entries become standalone rows instead of expanding existing rows (GHA `include:` only augments existing rows when its keys match the top-level matrix).

**Notes on the diff:**
- `strategy.matrix` declares both `version` and `platform` as top-level keys, producing a `(version × platform)` cross-product of 4 rows. The `include` entries then match on `platform` to inject the corresponding `runner` field into each row. The `exclude` rules are preserved — they still act on `version` alone, which is the behavior we want (skipping 8.4 when only 8.5 changed skips *both* its platform builds).
- `fail-fast: false` — if arm64 flakes, we still want the amd64 digest to exist for the merge. Flutter's version doesn't set this explicitly; adding it here is safer for the wider cross-product.
- `docker/setup-buildx-action@v3` is now required because push-by-digest needs buildx.
- The artifact name uses `linux-amd64` / `linux-arm64` (slashes sanitized) to keep artifacts distinct per (version, platform) and to match what the merge job downloads.

- [ ] **Step 3: Verify the YAML parses**

Run:
```bash
python3 -c 'import yaml,sys; yaml.safe_load(open(".github/workflows/build.yml"))' && echo OK
```
From the docker repo root. Expected: `OK`. If `yaml.safe_load` raises, fix indentation/quoting before continuing. Do NOT commit broken YAML.

- [ ] **Step 4: Commit**

Run:
```bash
git add .github/workflows/build.yml
git commit -m "ci: build PHP images per-platform for multi-arch manifest"
```

---

## Task 4: Add the `merge-php` job

**Files:**
- Modify: `.github/workflows/build.yml` — insert a new job immediately after `build-php`.

- [ ] **Step 1: Append the `merge-php` job after `build-php`**

Edit `.github/workflows/build.yml`. Insert this block immediately after the `build-php` job closes and before the `# ── kubectl ──` banner.

```yaml
  # ── PHP (merge multi-arch manifest) ─────────────────────────────
  merge-php:
    needs: [build-php]
    if: |
      always() && needs.build-php.result == 'success'
    runs-on: ubuntu-latest
    strategy:
      fail-fast: false
      matrix:
        version: ['8.4', '8.5']
    steps:
      - uses: docker/setup-buildx-action@v3
      - uses: docker/login-action@v3
        with:
          registry: ${{ env.REGISTRY }}
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}
      - uses: actions/download-artifact@v4
        with:
          pattern: php-${{ matrix.version }}-digest-*
          merge-multiple: true
          path: /tmp/digests
      - name: Bail if no digests were produced for this version
        run: |
          if ! ls /tmp/digests/* >/dev/null 2>&1; then
            echo "No digests for PHP ${{ matrix.version }} — build-php was skipped by change detection."
            exit 0
          fi
          echo "has_digests=true" >> "$GITHUB_ENV"
      - name: Create multi-arch manifest
        if: env.has_digests == 'true'
        working-directory: /tmp/digests
        run: |
          docker buildx imagetools create \
            -t ${{ env.NAMESPACE }}/php:${{ matrix.version }} \
            $(printf '${{ env.NAMESPACE }}/php@sha256:%s ' *)
      - name: Inspect published manifest
        if: env.has_digests == 'true'
        run: |
          docker buildx imagetools inspect ${{ env.NAMESPACE }}/php:${{ matrix.version }}
```

**Notes on the diff:**
- `needs: [build-php]` — waits for every matrix cell of `build-php` to finish. With `fail-fast: false` and `needs.build-php.result == 'success'`, we only merge when *all* platform builds for *some* version succeeded. If one version's builds were excluded and the other's succeeded, `build-php.result` is still `success` overall — the "Bail if no digests" step handles the per-version early-out.
- The "Bail if no digests" step exists because `download-artifact` with `pattern: php-X.Y-digest-*` is non-fatal if nothing matches — it just produces an empty directory. Without the bail, `docker buildx imagetools create` would be called with no digests and fail confusingly.
- `Inspect published manifest` step is a belt-and-braces sanity check in CI log: you see the final manifest list right there.

- [ ] **Step 2: Verify YAML parses**

Run:
```bash
python3 -c 'import yaml,sys; yaml.safe_load(open(".github/workflows/build.yml"))' && echo OK
```
Expected: `OK`.

- [ ] **Step 3: Commit**

Run:
```bash
git add .github/workflows/build.yml
git commit -m "ci: merge per-platform PHP digests into multi-arch manifest"
```

---

## Task 5: Push the branch and trigger the workflow

**Files:**
- No file changes.

- [ ] **Step 1: Push branch**

Run:
```bash
cd /Users/bud/dev/private/server/docker
git push -u origin multi-arch-php
```

- [ ] **Step 2: Open a PR**

Run:
```bash
gh pr create \
  --title "ci: multi-arch PHP images (amd64 + arm64)" \
  --body "$(cat <<'EOF'
## Summary
- Rebuild `ghcr.io/jpjonte/php:8.4` and `:8.5` as multi-arch manifest lists (amd64 + arm64)
- Mirrors the matrix+merge pattern already proven in `build-flutter`
- Dockerfiles and scripts unchanged — upstream `php:*-fpm-alpine` is already multi-arch

## Why
Apple Silicon consumers (e.g. Pantry on M1) pull the amd64 image and crash inside QEMU with `QEMU internal SIGSEGV` when php-fpm forks workers.

## Test plan
- [x] `docker buildx build --platform linux/arm64 -f php/8.5/Dockerfile .` builds locally
- [x] `php -v` runs inside arm64 image without SIGSEGV
- [ ] After merge: `docker manifest inspect ghcr.io/jpjonte/php:8.5` shows both amd64 and arm64 entries
- [ ] After merge: Pantry `docker compose up api` no longer prints `qemu-x86_64` and reaches php-fpm steady state
EOF
)"
```

- [ ] **Step 3: Trigger the workflow manually (since file changes may not hit `paths-filter`)**

The `paths-filter` job only emits `php-8_4=true` / `php-8_5=true` when `php/8.4/**`, `php/8.5/**`, or `php/scripts/**` changed. Our diff is in `.github/workflows/build.yml` only, so change detection will mark both as `false` and the whole `build-php` job will be excluded. We need `workflow_dispatch` to actually exercise the new code path.

Run:
```bash
gh workflow run "Build Docker images" --ref multi-arch-php
```

Then watch:
```bash
gh run watch --exit-status
```

Expected: four `build-php` jobs (`8.4 × {amd64, arm64}`, `8.5 × {amd64, arm64}`) succeed, then two `merge-php` jobs (one per version) succeed. If a build fails with `no space left on device` or runner capacity issues, rerun it; it's transient. If a build fails with a compile error, STOP — you have an arm64-specific Dockerfile issue and must fix it before proceeding.

- [ ] **Step 4: Merge the PR**

Once CI is green:
```bash
gh pr merge --squash --delete-branch
```

---

## Task 6: Verify published manifest is multi-arch

**Files:**
- No file changes.

- [ ] **Step 1: Inspect each tag's manifest**

Run:
```bash
docker buildx imagetools inspect ghcr.io/jpjonte/php:8.5
docker buildx imagetools inspect ghcr.io/jpjonte/php:8.4
```

Expected, for each: a `Manifests:` section with **at least two rows**, one per platform:
```
Name:       ghcr.io/jpjonte/php:8.5@sha256:...
MediaType:  application/vnd.docker.distribution.manifest.list.v2+json

Manifests:
  Name:       ghcr.io/jpjonte/php:8.5@sha256:...
  Platform:   linux/amd64

  Name:       ghcr.io/jpjonte/php:8.5@sha256:...
  Platform:   linux/arm64
```

If the output is still a single-arch `manifest.v2+json` (no `Manifests:` section), the merge step either didn't run or failed silently — re-check the `merge-php` job log.

- [ ] **Step 2: Diff against baseline**

Run:
```bash
docker manifest inspect ghcr.io/jpjonte/php:8.5 --verbose > /tmp/php-85-after.json
diff <(jq -r '.Descriptor.mediaType' /tmp/php-85-before.json) <(jq -r '.Descriptor.mediaType' /tmp/php-85-after.json)
```

Expected:
```
< application/vnd.docker.distribution.manifest.v2+json
> application/vnd.docker.distribution.manifest.list.v2+json
```

---

## Task 7: Downstream verification in Pantry

**Files:**
- No file changes in docker repo. This task is in `/Users/bud/dev/private/projects/pantry`.

- [ ] **Step 1: Purge the cached amd64 derived image**

Run (from anywhere):
```bash
docker image rm pantry/php:latest || true
docker image rm ghcr.io/jpjonte/php:8.5 || true
```

This forces `docker compose build` to re-pull the base from GHCR and pick up the new arm64 variant of the manifest list (Docker selects the variant matching the host platform automatically).

- [ ] **Step 2: Rebuild Pantry's `api` image**

Run:
```bash
cd /Users/bud/dev/private/projects/pantry/.worktrees/175-delete-account
docker compose build api
```

Expected: Docker pulls `ghcr.io/jpjonte/php:8.5` and reports pulling an `arm64` layer (`=> pulling from jpjonte/php … linux/arm64`). If it still pulls amd64, double-check Step 1 actually removed the cached amd64 variant.

- [ ] **Step 3: Verify the derived image is arm64**

Run:
```bash
docker image inspect pantry/php:latest --format '{{.Os}}/{{.Architecture}}'
```

Expected: `linux/arm64`. If it says `linux/amd64`, the base pull used the amd64 variant — investigate why. Could be a stale buildx cache; `docker buildx prune` and retry.

- [ ] **Step 4: Start the `api` service and confirm no QEMU output**

Run:
```bash
docker compose up api 2>&1 | tee /tmp/pantry-api.log &
sleep 30
grep -i 'qemu' /tmp/pantry-api.log && echo "FAIL: QEMU still in use" || echo "PASS: no QEMU output"
grep -E '(php-fpm|ready)' /tmp/pantry-api.log | head -20
docker compose down
```

Expected: `PASS: no QEMU output`, plus php-fpm startup log lines ("ready to handle connections" from php-fpm master).

- [ ] **Step 5: No commit needed**

This task is verification only; nothing changes in the Pantry repo.

---

## Rollback

If anything published by this plan is broken, the rollback is straightforward: GHCR retains the previous amd64-only manifest behind the digest. To revert:

```bash
# Find the pre-change amd64 digest from /tmp/php-85-before.json (Descriptor.digest)
# Then retag:
docker buildx imagetools create \
  -t ghcr.io/jpjonte/php:8.5 \
  ghcr.io/jpjonte/php@sha256:<previous-amd64-digest>
```

Revert the workflow change with `git revert <commit>` and push.

---

## Follow-ups (explicitly out of scope)

- **`.gitlab-ci.yml`** still builds single-arch via Kaniko. If the GitLab pipeline is no longer used, delete it. If it is used, rework it to either `kaniko+crane` multi-arch or retire it in favor of GHA.
- **kubectl image** is still amd64-only. Same pattern applies if you want it multi-arch; low priority since it's rarely run on arm64 interactively.
- **Derived image hardening**: Pantry's `api/api/Dockerfile` has an `apk add --no-cache --virtual .build-deps linux-headers autoconf g++ build-base` step for xdebug/pcov — this will work on arm64 but adds build time. Consider prebuilding xdebug+pcov into the base image so the downstream dev Dockerfile doesn't need to compile them.
- **Renovate/Dependabot for base images**: once multi-arch, automated `FROM php:X-fpm-alpine` bumps become safer to accept.

---

## Self-review notes

Spec coverage: the long-term fix requested was "build a native arm64 image so no emulation is needed." Tasks 1–7 cover investigation, Dockerfile verification, CI rewrite, merge, publish, and downstream validation. No gaps identified.

Placeholder scan: every step has either an exact shell command or a complete YAML block. No "TBD", no "similar to", no "write tests for the above" without code.

Type/name consistency: artifact naming `php-${version}-digest-${sanitized-platform}` is used identically in the upload step (Task 3, Step 2) and the download step (Task 4, Step 1). Job names `build-php` and `merge-php` are referenced consistently. `env.NAMESPACE` is the existing workflow env var — not redefined.
