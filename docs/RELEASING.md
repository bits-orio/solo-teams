# Releasing for Factorio 2.0 and 2.1 together

Two release lines, two branches, until Factorio 2.1 is the stable release (policy: `docs/FACTORIO_21_PLAN.md`, "Branch policy").

| Line | Branch | Versions | Factorio | Who gets it |
|---|---|---|---|---|
| 2.0 | `master` | 0.6.x | 2.0, stable | Almost every player and server today |
| 2.1 | `factorio-2.1` | 0.7.x | 2.1, experimental | Testers; becomes the only line when 2.1 goes stable |

The portal keeps both: each release carries its own `factorio_version`, the in-game mod browser shows a player only the release that matches their game, and the website lists both. Two rules follow from how the portal works:

- **No version number may appear on both lines.** The portal rejects a duplicate version outright. 0.6.x stays on the 2.0 line, 0.7.x on the 2.1 line.
- **Release 2.0 first, 2.1 second, same day.** The portal page (description, metadata, Changelog tab) is deployed from whichever tag ran last. `docs/portal.md` and `tools/portal_meta.json` must be identical on both branches (edit on master, merge forward), and the 2.1 branch's `changelog.txt` is a superset of master's (it carries every 0.6.x entry plus the 0.7.x ones), so finishing with the 2.1 release leaves the complete changelog on the page.

## The paired release, step by step

**A. The 2.0 release, on `master`**

1. Everything that is not 2.1-specific lands on master. Test on 2.0: `~/factorio-test/players start 2 2.0` (the launcher warns if the tree is on the wrong branch).
2. Bump per `.claude/skills/bump-version.md`: patch bump in `info.json` (0.6.3 to 0.6.4), changelog entry at the top of `changelog.txt`, README and welcome-panel check, commit.
3. Push master, then `./tools/release.sh`. It checks the clean tree, the changelog entry, the locale keys and that HEAD is on origin, then pushes the tag `v0.6.4`. GitHub Actions builds the zip, publishes the GitHub release with the changelog entries since the previous 0.6.x release, posts to Discord, uploads the 2.0 release to the portal and syncs the portal page.
4. Confirm: `python3 tools/portal_check.py`, or `curl -s https://mods.factorio.com/api/mods/multi-team-support/full` and look for 0.6.4 with `"factorio_version": "2.0"`.

**B. The 2.1 release, on `factorio-2.1`**

5. `git checkout factorio-2.1 && git merge master`. Two files conflict on every paired release and always resolve the same way: `info.json` keeps the branch's own version and `factorio_version 2.1` and `base >= 2.1` (take master's other fields); `changelog.txt` keeps the 0.7.x entries on top, then master's new 0.6.x entry, then the rest.
6. Checks: `python3 tools/check_locale.py`, `python3 tests/syntax_check.py`, `python3 tests/run.py`, then load on the 2.1.17 headless rig (`~/factorio-dev/rig/start-server.sh 2.1 ...`) or straight into the clients: `~/factorio-test/players start 2 2.1`. Test in-game on 2.1.
7. Bump on the branch: 0.7.x patch bump (0.7.0 to 0.7.1), changelog entry that names what changed on the 2.1 line and says which 0.6.x release it includes, commit.
8. Push the branch, then `./tools/release.sh`. It warns that you are not on master; that is expected for the 2.1 line. Tag `v0.7.1`, the same workflow runs, and the portal receives the 2.1 release.
9. Confirm both releases on the portal: the newest 0.6.x with `factorio_version 2.0` and the newest 0.7.x with `2.1`.

**C. Companions, the same day as the first 2.1 release**

- open-discord-bridge: only `companion-mod/info.json` changes (`factorio_version 2.1`, `base >= 2.1`); its own two-line rule applies. Without it a 2.1 server loses every Discord announcement.
- brave-new-mts and mts-dimension-warp need their own 2.1 ports first (see `docs/FACTORIO_21_REFRESH.md`, "Companion mods").

## Cadence and exceptions

- One paired release per week at most, per the house release discipline; same-day patches only for crash fixes.
- A fix that only matters on 2.1 may ship alone on the 2.1 line. A fix on master must be merged forward before the next 2.1 release; never leave the branch behind master for long, that is how the July layout drifted.
- The first 2.1 release is 0.7.0, already committed on the branch. Its release notes are the 0.7.0 entry alone, because the workflow looks for the previous release on the same line and finds none.

## What the workflow does per tag, and what to check when it fails

`.github/workflows/release.yml` on the tagged commit: read `info.json`, find the previous published GitHub release on the same line (same `vMAJOR.MINOR.` prefix), extract the changelog entries down to it, build the zip (tools, docs, tests and scripts stripped), create the GitHub release, post the changelog to Discord, upload to the portal, sync the portal page, post the "live on the portal" ping. Both Discord titles name the Factorio version so a 2.0 player is not told about a 0.7.x release.

- Portal upload failed: the tag and GitHub release stand; re-run the "Upload to Mod Portal" workflow, it is idempotent.
- Wrong changelog on the portal page: release order was reversed; re-run the 2.1 tag's page sync (`tools/sync_portal_details.sh` from the branch) or the "Sync Portal Details" workflow.
- Release notes contain the whole changelog: the previous release on that line was not found (first release on a line, or the tag prefix changed); harmless, edit the GitHub release text.

## When 2.1 becomes stable

Merge `factorio-2.1` into `master`, make master the 0.7.x line with `factorio_version 2.1`, stop releasing 0.6.x, delete the branch. The last 0.6.x release stays on the portal for players who have not updated.
