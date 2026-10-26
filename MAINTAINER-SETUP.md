# Jellyfin KOReader Sync Plugin — Maintainer Setup

## What this is

This repository is maintained by an automated agent loop acting on GitHub as
**jakepi-bot**, under Jake's supervision. The loop triages issues, watches
upstream Jellyfin for changes that could regress the plugin, and ships
regression-tested releases.

## Weekly loop

- **Job**: Hermes cron `be7b62bea0f5` — "JKSync weekly maintainer"
- **Schedule**: Mondays 09:00 America/Chicago (`0 9 * * 1`)
- **Model**: pinned `deepseek-v4.1-flash` via `opencode-go`
- **Monitor script**: `~/.hermes/scripts/jksync-watch.sh` — a stable-output
  probe (open issues, plugin manifest head, latest Jellyfin stable, plugin
  template commits, NuGet version tail). Its output is hash-compared each
  tick; **the agent runs only when that state changed**. Healthy weeks are
  intentionally silent (Jake's channel rule: Discord carries only newly-found
  critical material; failures surface through the job's failure delivery).
- **Delivery**: Discord DM (`discord:1558054081325695037`)
- **Skill**: `jellyfin-koreadersync-maintenance` — the authoritative operating
  manual (repo facts, versioning rules, QA harness, release recipe, lessons).

When the monitor detects a change, the agent: triages any open issues and
responds under them; checks the upstream data against the plugin's
`targetAbi`; fixes or prepares updates locally; runs the full local QA matrix;
and only then pushes — as jakepi-bot.

## Hard rules

1. **Every push is gated on the full local QA matrix** (below) on the exact
   artifact being pushed, on BOTH the latest stable Jellyfin and the prior
   stable. No exceptions, including metadata-only releases.
2. **Version has ONE source of truth**: `<Version>` in `Directory.Build.props`.
   The git tag is a label. Never derive the version from a tag, and never feed
   an ABI-shaped value into `AssemblyVersion` — Jellyfin reports
   `PluginInfo.Version` from the assembly version and fetches the plugin icon
   from `/Plugins/<Id>/<Version>/Image`; a mismatch 404s the tile.
3. **`manifest.json` is the catalog**: newest version first; `targetAbi` =
   latest Jellyfin stable as `MAJOR.MINOR.0.0`; `checksum` = md5 of the
   PUBLISHED zip. Publish the exact artifact that passed QA — local rebuilds
   are not byte-identical. A published release whose checksum is absent or
   does not match the asset is treated as a supply-chain concern: stop and
   verify before trusting it.
4. **Release numbering**: each Jellyfin minor gets a patch-level plugin bump
   (2.0.4.1→12.0, 2.0.4.2→12.1, 2.0.4.3→12.2, 2.0.4.4→12.3).

## QA matrix (`jks-qa/` in the maintainer workspace)

Harness location: `/home/jake/.hermes/code-management/jks-qa/` — kept OUTSIDE
this repo so scaffolding can never be committed. Files: `qa-driver.sh`
(phase-capable full matrix: `PHASE=setup|protocol|full`), `common.sh` (shared
functions), `make-epubs.py` (deterministic test books + KOReader partial-MD5
document hashes), `partial_md5.py` (the hash algorithm, mirroring the
plugin's `CalculateBinaryHash`), `check-script.py` (compile-safety gate).

Runs against pinned Docker images (`jellyfin/jellyfin:12.3` and `:12.2`) on
16xxx host ports with per-run config, media, scratch, and state dirs.
Coverage — all must pass with FAILED 0:

- plugin loads and reports the expected assembly version; no compatibility
  rejection in the server log
- all four `/plugins/koreader/v1` endpoints
- header-fallback auth (200), Basic auth (200), wrong Basic password (401),
  missing headers (401)
- furthest-wins conflict resolution (a lower percentage is rejected and the
  stored timestamp is unchanged)
- persistence across a full server restart
- the native Jellyfin progress bridge (PlaybackPositionTicks for the matched
  library item)
- per-user isolation, on-disk progress files, clean error logs

In a healthy environment the whole matrix runs as two phase calls per server
(`setup` then `protocol`). On the agent host, one long call may exceed the
tool timeout, so phases can be driven as short steps — the driver's sections
map 1:1 onto them and all state is on disk, so a killed step simply re-runs.

## Release process (summary; details in the skill)

1. Bump `Directory.Build.props`; prepend the manifest entry (targetAbi,
   placeholder checksum) — the build refuses to run otherwise.
2. Build with `--NoPublish`; confirm the built assembly version equals the
   plugin version.
3. Run the QA matrix on that exact zip, both Jellyfin versions.
4. Branch → PR → merge; then tag, create the GitHub release, upload that same
   zip, and update `manifest.json`'s checksum from the published file.
5. Verify the shipped artifact: download it, confirm md5 == manifest checksum.

## Not automated (deliberate follow-ups)

- **.NET 10 migration**: `Jellyfin.Controller` 12.x NuGet packages are
  net10.0-only (verified 2026-10-15: NU1202 against net9.0; re-verified
  2026-10-26 for 12.3.0 — the nupkg's only lib target is net10.0). The plugin
  compiles against the 10.11 packages while declaring a 12.x `targetAbi`,
  which is the shipping pattern across the 12.x line; a true net10.0 retarget
  is a separate migration release.
- Web-based plugin configuration UI and audiobook progress tracking remain
  open feature areas (see README Contributing).

---
*Loop established 2026-10-15. Supersedes the earlier OpenClaw monthly job.*
