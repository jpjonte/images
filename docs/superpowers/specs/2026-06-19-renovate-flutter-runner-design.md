# Renovate runner with Flutter — design

> **SUPERSEDED (2026-06-19).** Built on a wrong premise — that Renovate's containerbase
> has no Flutter tool. It does (`containerbase/flutter-prebuild`, incl. 3.44.x), so the
> stock runner already installs Flutter and refreshes `pubspec.lock` given a
> `GITHUB_COM_TOKEN` (which the cluster already has). The custom image was unnecessary and
> has been removed; no cutover ever happened. `share_plus 13`'s missing lockfile was just an
> unresolvable solve, not a blind runner. Kept for the record — see the `renovate-flutter-runner`
> memory and the SDD progress ledger.

**Date:** 2026-06-19
**Status:** Approved, pending implementation
**Repos touched:** `docker` (image + pipeline), `argocd` (deploy), `bud/life-tracker` (cleanup)

## Problem

Renovate raised `life-tracker` PR #379 (`share_plus ^12.0.2` → `^13.0.0`). The PR
changed only `pubspec.yaml`; it never touched `pubspec.lock`. CI then failed at
`flutter pub get` with an unsatisfiable version solve:

- `health 13.3.1` (newest in `^13.3.1`) → `device_info_plus ^12.1.0` → `win32 ^5.x`
- `share_plus ^13.0.0` → `win32 ^6.0.0`
- `win32` 5 vs 6 → no solution.

Root cause is structural, not specific to this PR. Renovate runs as a Kubernetes
CronJob on the `sora` cluster using the stock `ghcr.io/renovatebot/renovate`
image. Its `pub` manager can refresh `pubspec.lock`, but only when a `dart` or
`flutter` binary is on `PATH`. Renovate's containerbase tool installer (the
mechanism behind the default `binarySource: install`) has **no Dart/Flutter
tool** — it is not in the install-tool catalog — so no Renovate image ships
Flutter and it cannot fetch it at runtime. The runner is therefore blind to pub
resolvability: it rewrites version constraints in `pubspec.yaml` without ever
running a solve. CI is the first place `pub get` executes.

The same blindness makes the repo's `lockFileMaintenance` config a no-op (it
cannot refresh a lockfile without the toolchain), exactly as the inline NOTE in
`renovate.json5` warned.

## Goal

Give the Renovate runner a Flutter toolchain so it runs `flutter pub get` when
preparing a branch. Outcomes:

1. Resolvable pub bumps update `pubspec.lock` in the PR (the stated need:
   "pubspec.lock reflects the changes made in pubspec.yaml").
2. Unresolvable bumps (like #379) are *flagged* as artifact errors instead of
   passing silently to CI.
3. No regression for the other repo this runner manages (`bud/pantry`), and PHP
   support for pantry/future repos is preserved.

Non-goal: making #379 mergeable. The `health`/`win32` conflict is genuinely
unsatisfiable today; #379 will be flagged and closed until `health` moves to
`win32 6`.

## Constraints that shaped the design

- **Shared runner.** One CronJob serves both `bud/pantry` and `bud/life-tracker`.
  Anything that changes tool resolution affects both.
- **PHP, soon.** The runner must support PHP/Composer for pantry (and future PHP
  repos). PHP and Composer *are* containerbase-managed tools (unlike
  Dart/Flutter), so keeping `binarySource: install` covers PHP on demand at no
  extra cost. This is a reason to preserve containerbase, not bypass it.
- **No gradle lockfiles** in life-tracker, so the gradle / gradle-wrapper /
  github-actions managers need no pre-installed toolchain.
- **`binarySource` is a global self-hosted setting**, not per-repo. We cannot
  scope it to one repository.

## Chosen approach: one combined image, keep containerbase

Build `ghcr.io/jpjonte/renovate` as the stock Renovate image with the Flutter
SDK baked onto `PATH`. Leave `binarySource` at its default (`install`).

Why this is expected to work without bypassing containerbase: the `pub` manager
has no containerbase-managed dart/flutter tool, so under `binarySource: install`
there is nothing for containerbase to install and the `flutter pub get` exec
resolves `flutter` from the image `PATH`. Meanwhile containerbase continues to
auto-install PHP/Composer/etc. for every other manager and repo. One CronJob,
one config, pantry untouched. This `PATH`-fallback is the one inferred point in
the design (the docs describe `install` falling back to `global` outside a
containerbase environment, but are not explicit about per-tool fallback inside
one) and is confirmed in the Verification step below.

### Alternatives considered

- **Separate life-tracker-only CronJob** with a Flutter image + `binarySource:
  global`. Cleanest blast-radius isolation, but a whole second deployment and
  duplicated config to maintain. Held as the fallback if verification (below)
  shows the pub manager will not use the `PATH` Flutter under
  `binarySource: install`.
- **Combined image + `binarySource: global` everywhere.** Simplest config, but
  drops containerbase for pantry too, so every tool pantry needs (PHP, Composer,
  …) would have to be baked and version-managed by hand. Rejected.

## Component 1 — image (`docker` repo)

New `docker/renovate/Dockerfile`:

```dockerfile
ARG RENOVATE_VERSION
ARG FLUTTER_VERSION=3.44.1
FROM ghcr.io/renovatebot/renovate:${RENOVATE_VERSION}

USER root
ENV FLUTTER_HOME=/opt/flutter
ENV PATH="${FLUTTER_HOME}/bin:${FLUTTER_HOME}/bin/cache/dart-sdk/bin:${PATH}"
RUN git clone --branch "${FLUTTER_VERSION}" --depth 1 \
      https://github.com/flutter/flutter.git "${FLUTTER_HOME}" \
    && git config --system --add safe.directory "${FLUTTER_HOME}" \
    && flutter config --no-analytics \
    && flutter precache --universal --no-android --no-ios --no-linux \
       --no-windows --no-macos --no-web \
    && flutter --version \
    && chown -R 1000:1000 "${FLUTTER_HOME}"
USER 1000
```

Decisions:

- **Base = the default (slim) Renovate image**, not `-full`. The default image is
  the containerbase one already in use; keeping it preserves `binarySource:
  install` and PHP-on-demand. We graft on only the one tool containerbase lacks.
- **Flutter pinned to `3.44.1`** (life-tracker's `.fvmrc`). The runner never
  builds — only `flutter pub get` for resolution — so it only needs a Flutter
  whose bundled Dart satisfies `pubspec`'s `environment.sdk: '>=3.12.0 <4.0.0'`.
  Pinning mirrors how the CI Flutter image is pinned. The only sync obligation is
  loose: keep the image's Flutter ≥ life-tracker's. A bump is a one-line ARG
  change.
- **Keep `.git`** in the clone (Flutter self-identifies via `git rev-parse`) and
  `flutter precache --universal` so the Dart SDK is baked, not downloaded on
  every cron run. `safe.directory` is set defensively against git's
  dubious-ownership check.
- **Run as UID 1000** (matches the CronJob `runAsUser`), with `/opt/flutter`
  owned by 1000 so Flutter's cache writes succeed. Renovate's entrypoint/CMD are
  left untouched.

## Component 2 — build pipeline (`docker` repo)

A `build-renovate` job in `.github/workflows/build.yml`, mirroring the existing
`build-flutter` pattern (multi-arch amd64+arm64, build-by-digest then
merge-manifest):

- **Triggers:**
  - push when `renovate/**` changes (via the `changes` paths-filter job);
  - the daily schedule: a freshness check that reads the latest
    `renovatebot/renovate` release and builds only if
    `ghcr.io/jpjonte/renovate:<that-version>` does not already exist (same shape
    as the Flutter freshness check);
  - `workflow_dispatch`.
- **Build args:** `RENOVATE_VERSION=<upstream latest>`, `FLUTTER_VERSION=3.44.1`.
- **Tags:** `ghcr.io/jpjonte/renovate:<renovate-version>` (e.g. `43.232.0`) plus a
  moving `:latest`. Tagging by the upstream Renovate version is what lets the
  argocd bot track and bump it.

## Component 3 — deployment (`argocd` repo)

In `apps/renovate/values.yaml`, one functional change:

- `image: ghcr.io/renovatebot/renovate:43.232.0`
  → `image: ghcr.io/jpjonte/renovate:43.232.0`, and update the adjacent
  `# renovate:` comment so its `depName` reflects `ghcr.io/jpjonte/renovate`.

The existing `customManagers` `image:` regex in `argocd/renovate.json` then
auto-bumps our tag whenever the `docker` repo publishes a new
`jpjonte/renovate:<version>`. The update chain becomes:

> upstream Renovate release → `docker` repo rebuilds `jpjonte/renovate:<v>` →
> argocd bot bumps the pin in `values.yaml`.

No change to the `config.js` ConfigMap, `binarySource`, schedule, or resources.
Pantry is unaffected.

## Component 4 — life-tracker cleanup + PR #379

A small, separate change in `bud/life-tracker` (its own branch/PR), tracked as a
follow-up to the infra work:

- Update the stale `lockFileMaintenance` NOTE comment in `renovate.json5` (its
  "disable if the bot lacks Flutter" caveat is now satisfied). No functional
  config change is required — Renovate refreshes `pubspec.lock` automatically
  once Flutter is on the runner.
- **Close PR #379.** It cannot resolve until `health` moves to `win32 6`.
- Add a **temporary `packageRule` holding `share_plus` to its current major**
  until `health` is `win32 6`-compatible, with a comment and a "remove when
  unblocked" note, so Renovate stops re-raising a flagged PR every cycle.

## Verification (the one inferred behavior)

The single assumption not directly documented is that the `pub` manager uses the
`PATH` Flutter while `binarySource` stays `install`. Before rollout, run the
built image as a one-shot `RENOVATE_DRY_RUN=full` against both repos and confirm:

1. **life-tracker** — a resolvable pub bump updates `pubspec.lock`, and the
   `share_plus 13` bump is flagged as an artifact error (not silently passed).
2. **pantry** — composer (and any other containerbase tool) still resolves via
   containerbase, i.e. `binarySource: install` is intact.

If (1) fails, fall back to the separate-CronJob alternative
(`binarySource: global`, life-tracker only). Expectation is that it passes.

## Out of scope

- Migrating pantry off containerbase or baking PHP (containerbase covers it).
- Any change to life-tracker's pub constraints to force #379 through.
- Matching the runner's Flutter to life-tracker's exact version for build
  fidelity (the runner does not build).
