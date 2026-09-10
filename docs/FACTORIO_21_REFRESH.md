# Factorio 2.1 refresh (2026-09-08)

Fresh due diligence for the MTS 2.1 effort, done against the current engine release rather than the July snapshot. Everything marked *measured* was run today on headless servers (Factorio 2.0.72 and 2.1.17 over RCON); everything marked *JSON* comes from machine-diffing the official `runtime-api.json` / `prototype-api.json` of 2.0.77, 2.1.11 and 2.1.17. Every MTS Lua file on master was read in full by one of eight reviewers, each finding was re-verified by a second reviewer against the API JSON, and the five hard breakages were then reproduced live. Nothing below rests on memory of the docs.

## Headline

- The current Factorio release is **2.1.17** (2026-08-26). Every earlier MTS 2.1 verification, the local `~/factorio-2.1` install and its bundled docs are **2.1.11** (2026-07-14). Six patch releases landed in between. Nothing in them touches an API the factorio-2.1 branch already uses; what they add is in section 5.
- MTS **master loads and initialises on 2.1.17** (settings, data stage, data-final-fixes, on_init, all clean, *measured*) and fails only at runtime, at **five call sites**: three throw, two fail silently. Each has a fix that runs unchanged on both engines or needs a two-line branch (section 2).
- The **factorio-2.1 branch also loads on 2.1.17** (*measured*). It still carries two of the silent failures (science milestone, reaper markers) because the July port only fixed what threw.
- Factorio's own mod-structure doc states a mod is compatible with exactly one major version, so two zips are unavoidable. The one-tree layout proposed in section 3 was declined on 2026-09-09: two branches stay until 2.1 is stable (it is experimental today; stable is 2.0.77), with the merge discipline recorded in the plan.
- Every companion mod (open-discord-bridge, brave-new-mts, mts-dimension-warp, mts-expanse, diggy) declares `factorio_version "2.0"`, and two of them carry their own 2.1 breakages (section 4).

## Merge status (2026-09-09)

Master (0.6.3, 39 commits) has been merged into factorio-2.1 with `git merge --no-commit`; the result is staged and **uncommitted** for an in-game test. What the resolution did:

- Ten conflicts resolved: both sides kept in data.lua, gui/teams.lua, remote_api.lua (bridge labels and catalogue now carry team_paused, team_resumed and chat), player_lifecycle.lua (master's joined-game handler, then the branch's leader-colour adoption), commands/admin.lua (master's localised prints plus the branch's alert and event calls), admin_flags.lua (all three flags, the two branch flags given ls_label/ls_tooltip twins), locale.cfg (both sections, em-dash removed from the alert text). events/ticks.lua takes master's 60-tick clock refresh without the colour poll, which the on_player_color_changed event replaces on 2.1. info.json is master's file stamped 0.7.0, factorio_version 2.1, base >= 2.1.
- gui/stats_data.lua is gone (master split it); the recipe fix lives in gui/stats/discovery.lua as `recipe_in_category`, a pcall probe that reads `categories` on 2.1 and falls back to `category` on 2.0.
- Science packs come from the labs' inputs via the new scripts/science_packs.lua, shared by the stats module and the science milestone (finding 4 fixed).
- Pin tooltips and the two new flags use locale keys; the eight new keys exist in en, de, es-ES and ru; the key manifest was regenerated. New branch files carry the MIT header. The 0.7.0 changelog entry sits above 0.6.3.
- Checks: locale audit 584/584 keys, 136/136 Lua files parse under Lua 5.2, reaper tests 214 passed. On the 2.1.17 rig the merged tree loads, initialises, answers ensure_passive_radar, pause_team/unpause_team and the pause event ids, and the stats discovery, science set (12 packs) and reaper markers (tier 1 automation, tier 2 logistic) all resolve. The same tree stamped for 2.0 fails at on_init because on_player_color_changed is nil there; that is the first guard on the one-tree list and is expected for a tree that targets 2.1 only.
- Not done in the merge, still open from section 2: the teleport controller reassert (finding 6, GUI test first) and the 500-character Run Info cap.

## Where things stand

| Item | State |
|---|---|
| `master` | 0.6.3, `factorio_version 2.0`, 39 commits past the merge base 572121d: reaper, cleanup panel, stats split into `gui/stats/*`, localisation, MIT relicense, releases 0.5.0 to 0.6.3 |
| `factorio-2.1` | was 0.4.60 base plus 10 commits (port 098f921, docs and ADRs, Phases 1/2/4/5/6, two colour-readability commits); now carries master's 39 commits as an uncommitted merge at 0.7.0 (see Merge status) |
| Files touched on both sides | control.lua, data.lua, events/player_lifecycle.lua, events/ticks.lua, gui/pen_info_panel.lua, gui/pen_ops.lua, gui/stats_data.lua (deleted on master, split into gui/stats/), gui/team_card.lua, gui/teams.lua, info.json, locale/en/locale.cfg, scripts/admin_flags.lua, scripts/color_fix.lua, scripts/commands/admin.lua, scripts/pause/power.lua, scripts/remote_api.lua, scripts/team_slots.lua |
| Local installs | `~/factorio-2.0` 2.0.77; `~/factorio-2.1` 2.1.11 (behind); `~/factorio-dev/factorio-headless` 2.0.72; new today `~/factorio-dev/headless-2.1.17` (credential-free headless tarball) with a reusable rig in `~/factorio-dev/rig/` (start/stop scripts, RCON client, API diff tool, README) |

## What breaks MTS master on 2.1.17

| # | Call site | Symbol | Failure on 2.1.17 | Dual-compat fix | Evidence |
|---|---|---|---|---|---|
| 1 | `scripts/pause/power.lua:84` | `LuaEntity::active` write | Throws `LuaEntity::active is read only` inside `set_sources_on_surface`, aborting the freeze mid-loop: sources after the first are never toggled, accumulators are never zeroed, the pause marker is never set. Every `pause_team` / `unpause_team` call fails | `disabled_by_script = not active`. RW on both engines; on 2.0 the `active` write was already a deprecated alias for this flag (2.0.77 doc string, "since 2.0.26") | *measured*: the rig freeze on 2.1.17 threw at power.lua:84; the identical call on 2.0 froze and thawed cleanly |
| 2 | `scripts/remote_api.lua:785` | `LuaEntity::minable` write | Throws inside `ensure_passive_radar`, the mts-v1 call every consumer uses when it sets up a team surface | `minable_flag = false` (RW on both) | *measured*: `remote.call("mts-v1","ensure_passive_radar",...)` threw on 2.1.17 and returned the radar on 2.0 and on the 2.1 branch |
| 3 | `gui/pen_info_panel.lua:64` | `LuaEntity::minable` write | Throws the first time the landing pen is built (first player join) | `minable_flag = false` | *JSON*, plus the same error text as #2; needs a player to reproduce |
| 4 | `milestones/config.lua:64` | `prototypes.item[*].type == "tool"` | **Silent.** Science packs are plain items on 2.1 (0 items of type `tool`, *measured*), so the science milestone discovers nothing and "first team to produce science" never fires. The reaper reads science through `gui/stats/discovery.lua` too, so its tier markers stay unset and every scan skips as "not-ready" (safe direction: it never disbands) | Derive packs from `LuaEntityPrototype::lab_inputs` over `type == "lab"` entities, exactly as `gui/stats/discovery.lua:233` already does (12 inputs on the vanilla lab on both engines, *measured*) | changelog 2.1.7 "Changed all science packs to be plain items" |
| 5 | `gui/stats/discovery.lua:244` | `LuaRecipePrototype::category` | Throws the first time any stats tab is built (`columns.lua:81` calls `proto_lists()` without a pcall); `scripts/reaper/markers.lua:36` pcalls the same function and degrades silently | No common attribute: `category` is 2.0-only, `categories` is 2.1-only (*measured* both ways). Branch on `recipe.categories ~= nil` behind a pcall probe, or on the engine helper. On 2.1 treat `categories` as a set; 64 vanilla+SA recipes carry more than one | the July port fixed this in `gui/stats_data.lua`, a file master has since deleted, so the fix does not carry across a merge |
| 6 | `scripts/spectator/ops.lua:81` and ten other teleport sites | `LuaPlayer::teleport` semantics | **Behaviour.** Since 2.1.7 `teleport()` no longer implicitly exits remote view. Only `scripts/force_utils.lua:92` guards on the controller type and `spectator/ops.lua` restores the controller first; `gui/landing_pen.lua:64,130`, `gui/buddy_requests.lua:235,245`, `compat/compat_utils.lua:103,121`, `compat/platformer.lua:106`, `events/player_surface.lua:85` can move a spectating player's body while the camera stays put | Reassert the character controller explicitly where the player must land in-body | changelog 2.1.7; needs a GUI-client test |
| 7 | `scripts/locale_audit.lua:28` | `request_translations` return | Not a break: the nil-return guard is dead code on 2.1 (ids are returned even for offline players) | Check `player.connected` explicitly | hygiene |

Small degrade: 2.1 gives the display panel a `max_text_length` (default 500) and discards the rest (*measured*: a 600-character write reads back as 600 on 2.0 and 500 on 2.1). The admin Run Info box in `gui/admin.lua:353` has no cap, so a long run description is cut mid-sentence on the pen panel. Cap the box at 500.

Checked and cleared: the removed `defines.input_action.translate_string` (both permission lists nil-check every name); `display_panel_text` (2.1 accepts strings only, *measured*, and MTS already passes a plain string, so the panel text can never be localised on 2.1); `script.feature_flags.quality` (key still present); `apply_starter_pack` (gained an optional argument); `player.opened` (type broadened); `proto.group.order` (`LuaItemGroup` kept `order`). Data stage is clean: none of the removed prototype properties (recipe `category`, product `probability`, `braking_power`, tile `collision_mask` shape) appear in `data.lua`, `settings.lua`, `prototypes/` or the sea block and belt-ban compat files; `prototypes/entities/passive-radar.lua:54` sets the prototype's `minable` table, not the runtime attribute; the 2.1 branch's `alert-anchor` prototype also loads on 2.1.17. There is no `migrations/` directory, and nothing in the 2.1 changelog changes the locale file format.

## One tree, two zips (proposed; declined 2026-09-09 in favour of two branches until 2.1 is stable)

Decision: `master` stays the 2.0 line and `factorio-2.1` the 2.1 line until Factorio 2.1 is the stable release, then the branch is merged into master and 2.0 is dropped. The discipline is in `docs/FACTORIO_21_PLAN.md`, "Branch policy". The guard table below is kept for reference only; none of it needs to ship under the two-branch layout. The engine-neutral forms (first three rows) are still worth applying on master to keep merges small.


Factorio loads a mod only when `factorio_version` matches the running major.minor ("Mods can only be compatible with one major version, not multiple", `doc-html/auxiliary/mod-structure.html`, identical in the 2.0 and 2.1 doc trees). So two zips are unavoidable. Two *branches* are not: every 2.1-only API the branch uses can be feature-detected at runtime, and the two attributes that lost write access have replacements that already existed and were already the real implementation on 2.0.

**Engine helper.** `helpers.compare_versions(script.active_mods.base, "2.1.0") >= 0` (*measured*: -1 on 2.0, 1 on 2.1.17). `helpers.stage` is 2.1-only, do not use it for detection. Data stage: `mods["base"]` the same way.

**Per-API strategy** (from the per-commit analyses of the six 2.1-branch commits):

| API | 2.0 status | Strategy |
|---|---|---|
| `minable_flag`, `disabled_by_script` | RW on both | Use unconditionally, no branch |
| `LuaRecipePrototype::categories` | absent | Branch: `categories` as a set on 2.1, `category` on 2.0 |
| `lab_inputs` for science discovery | present on both | Use unconditionally |
| `on_player_color_changed` (fc6ae26) | absent | `if defines.events.on_player_color_changed then` register the event `else` keep the 60-tick colour poll the commit deleted from `events/ticks.lua`. Both paths stay in the tree |
| `LuaPlayer::disable_space_map` (57b75c4) | absent | Already pcall-wrapped in `gui/pen_ops.lua`; on 2.0 the pen keeps the vanilla space map. Unknown-attribute writes raise a catchable error on 2.0 (*measured* with another attribute), so the pcall holds |
| `LuaEntity::protected` (d12daf6, 7ef8758) | absent | **Unguarded today** in `gui/pen_info_panel.lua`, `scripts/remote_api.lua` `harden()` and `scripts/pause/notify.lua` `ensure_anchor()`: bare writes that throw on 2.0. Gate on the helper or pcall |
| `LuaForce` unlock and limit copies (d12daf6) | absent | Already per-property pcall in `team_slots.lua`; correct as is |
| `LuaForce::add_custom_alert` / `remove_alert` (7ef8758) | absent | Only some entry paths are pcall-wrapped; `notify.show` and the primary `remove_alert` branch are bare. Gate the alert half of `notify.lua` on the helper. The mts-v1 `on_team_paused` / `on_team_resumed` events and the Discord mirror are engine-core and ship on both |
| `LuaPlayer::get_pins` / `LuaPin` (2c448c6) | absent | Skip the pins feature as a whole on 2.0 (gate `team_pins.lua`, hide the Pin button). The current pcall-and-nil degrade makes `is_pinned` permanently false and would re-pin on every join |

**Releases.** The portal does not take two releases with the same version number (flib and even-distribution, both shipping 2.0 and 2.1 lines, carry distinct versions per line). The 2.1 line takes the next minor, or 1.0 as the house release rules already call for once a line is stable; the 2.0 line stays on 0.6.x for maintenance. `tools/release.sh` gets a target flag that stamps `factorio_version` and the `base` dependency into the zip's `info.json` and leaves the tree untouched.

**Merge.** Bring master into the 2.1 work (or rebase the five feature commits onto master). Hotspots from the per-commit dry runs against the merge base: `events/player_lifecycle.lua` and `events/ticks.lua` (moderate; fc6ae26 deletes the poll the 2.0 path still needs), `scripts/admin_flags.lua` and `scripts/commands/admin.lua` (rewrite; master localised every flag and string), `gui/stats_data.lua` (rewrite; the file is gone, re-apply the recipe fix in `gui/stats/discovery.lua`), `locale/en/locale.cfg` (moderate). Everything else is trivial or a clean add. New 2.1-branch files still carry `GPL-3.0-or-later` headers and need master's MIT header. The dry runs were made against master as of today's 8f7fcb8.

## Companion mods

Quick grep of the same breaking symbols (not a full read):

| Mod | Declared | 2.1 breakages found |
|---|---|---|
| open-discord-bridge | 2.0 | none |
| brave-new-mts 0.1.3 | 2.0 | `LuaEntity::minable` writes at `scripts/starter_base.lua:387`, `:409`, `:553`; a `display_panel_text` write at `:392` (string-only on 2.1) |
| mts-dimension-warp 0.8.13 | 2.0 | `LuaEntity::active` writes at `scripts/platforms/dimensions.lua:93` and `scripts/platforms/surface.lua:481`; six `fluidbox` uses (`LuaFluidBox` and `LuaEntity::fluidbox` are removed outright in 2.1) at `scripts/entities/logistics.lua:156`, `scripts/entities/warpgate.lua:151`, `scripts/platforms/surface.lua:318`, `scripts/platforms/harvesters.lua:174,197,307`, the warp-gate pipe-linking mechanism; replacement is `LuaEntity::add_fluid_box_linked_connection` and siblings called on the entity |
| mts-expanse 0.1.9, diggy 0.2.2 | 2.0 | not grepped (optional dependency on MTS) |

The July constraint ("MTS 2.1 must ship paired with an open-discord-bridge companion release") widens: each hard-dependency companion needs its own 2.1 release on the same one-tree pattern, and mts-dimension-warp has real porting work in its fluid code.

## What changed between 2.1.11 and 2.1.17

Runtime (*JSON* diff, 73 lines) and changelog 2.1.12 to 2.1.17:

- `LuaGroup` replaced by `LuaItemGroup` and `LuaItemSubGroup` (2.1.15). MTS reads `proto.group.order` in `gui/stats/discovery.lua:198` and `:276`; `LuaItemGroup` keeps `order`, `name`, `order_in_recipe` and `subgroups`, so nothing changes.
- New events: `on_next_day_started` (2.1.15; MTS has no game-day logic and the pen is `always_day`), `on_player_super_forced_selected_area` (2.1.13; an editor selection tool, no MTS surface).
- New: `LuaForce::get_space_platforms(location)` (2.1.13; MTS wants every platform on a force, not one location's subset), `LuaRecipePrototype::on_crafted_event` with data-stage `RecipePrototype::raise_on_crafted` and `ScriptTriggerEffectItem::custom_event` (2.1.15, see section 6), `LuaEntity::local_effect` / `potential_effects`, `LuaQualityPrototype::get_roll_chances()` / `roll_quality()` (no MTS use; `gui/stats/quality.lua` only enumerates the chain), `LuaBootstrap::get_event_name()` (reverse lookup for mts-v1 event ids, diagnostics only), `LuaPlayer::editor_settings`, `LuaSpacePlatform::completed_trips`, `LuaEntityPrototype::allows_flipping`, `LuaBurnerPrototype::burner_usage` / `hide_from_stats` and `LuaFluidEnergySourcePrototype::hide_from_stats` (worth adding to the `hidden_from_flow_stats` filter in `gui/stats/discovery.lua:241` when that code is touched).
- `LuaControl::opened` can now open the alerts GUI, the permissions GUI, the server config GUI and the player management GUI (2.1.15).
- `get_section` / `remove_section` on three logistic classes gained a typed `LogisticSectionIndex`; MTS does not call them. The "Concepts removed" lines in the diff (`InventoryIndex`, `ModuleEffectValue`, `ModuleEffects`) are type labels, not runtime symbols; nothing to grep for.
- Gameplay: an alert fires when an enemy expansion base is built inside active radar coverage (2.1.13, `defines.alert_type.expansion_base_built`). It is force-scoped, so each team sees only its own. MTS's radar passivisation shrinks the sector scan (vanilla 14 chunks down to 3; the passive radar ships 8), so the alert covers a smaller ring on MTS servers. Also 2.1.13: "fulfilled platform construction requests will no longer block platform-to-platform transfers", which strengthens the shared-location concern in section 6.
- Prototype stage: `circuit_connector_layer` fields moved to `CircuitConnectorSprites` (2.1.15), `EntityPrototype::ghost_build_sound`, `RecipePrototype::raise_on_crafted`. None touches MTS prototypes.

Nothing the factorio-2.1 branch already uses (`on_player_color_changed`, `disable_space_map`, `protected`, force alerts, `LuaPin`, the force unlock properties) changed in this window.

## New capabilities worth MTS's attention

Six reviewers each re-derived MTS uses from a slice of the 2.0.77 to 2.1.17 diff and the changelog, then a synthesis pass deduplicated and checked every claim against the JSON and the July catalogue (`docs/FACTORIO_21_OPPORTUNITIES.md` on the factorio-2.1 branch). Items the catalogue already covers (A1 to A6, B1 to B23) came back with no new facts and their verdicts stand; the six adopted ones are shipped on the branch.

New since the catalogue, ranked by the catalogue's own lenses (deletes code first):

1. **`LuaFlowStatistics::input_quality_counts` / `output_quality_counts` (2.1.7).** One attribute read returns the whole `{quality -> {item -> count}}` map, replacing the per-quality `get_input_count` loop at `gui/stats/counts.lua:160` and the normal-versus-merged gate at `:136`. ADOPT, gated on a numbers-match test; the timed axis still needs `get_flow_count` per quality, so the function shrinks rather than disappears. SA-gated, already behind `quality.multi_enabled()`.
2. **`LuaEntity::providing_to_other_platforms` (2.1.10, RW on the platform hub).** The only per-hub switch that can close the cross-team platform-to-platform transfer path opened by 2.1.7 (orbital requests from other platforms) and 2.1.13 (transfers at non-planet locations such as `solar-system-edge`, which `prototypes/connections.lua:14-22` deliberately shares across teams and `planet_map`'s reactive rewrite never sees, since `import_from` stays a `SpaceLocationID`). Investigate now, build once the leak is reproduced (GUI test list).
3. **info.json dependency modifier `+` (2.1.7).** `"+ open-discord-bridge"` makes a downloaded-but-unticked bridge enable by default while staying optional. ADOPT, one line, in the same release as the companion bump.
4. **`LuaControl::opened` accepting `defines.gui_type` on write (2.1.15).** An "Open alert settings" button beside the Phase 5 pause alerts is the one real use. DEFER; "when allowed" needs a test.
5. **Mod locale can define new language codes (2.1.7).** Lifts the "50 base-game codes" ceiling in `docs/locale/PLAN.md:24`. DEFER to locale phase 2.
6. **`defines.alert_type.expansion_base_built` (2.1.13).** Free and already force-correct; no work.
7. **Radar "universe" circuit mode (2.1.7).** Documented as "radars on the same force with the same channel", so it cannot cross team boundaries. No work; one line in `docs/MTS_API.md` for consumers building cross-surface automation.
8. **`LuaSpacePlatform::completed_trips` (2.1.15, RW).** A genuinely new per-team metric, but `milestones/engine.lua` renders through `[item=X]`; a stats column is the cheaper home. DEFER.
9. Rejected on MTS's own rules: `LuaEntity::local_effect` (teams play under identical rules, `scripts/team_modifiers.lua`), `LuaForce::get_space_platforms` (redundant), `LuaPlayer::editor_settings` (no pain point). `LuaDebugAdapter` is development tooling, worth knowing when debugging, not a work item.

Catalogued items whose facts changed:

- **Milestones.** The catalogue says "2.1 adds no production-threshold event". `RecipePrototype::raise_on_crafted` plus `LuaRecipePrototype::on_crafted_event` (2.1.15) do give a per-craft event. The verdict stays REJECT on corrected grounds: the doc says it fires only for crafting-machine crafts (a team's first science pack is routinely hand-crafted), MTS owns none of the recipes so it would have to flag other mods' prototypes in data-final-fixes, and at 20 teams the event volume exceeds the 300-tick poll it cannot replace. Verify the hand-craft exclusion before ever reopening this.
- **A1's risk widened past the picker** (item 2 above).
- **Display panel cap** (section 2).
- **A6 `disable_space_map`** shipped with its pcall never exercised on a real 2.0 engine; the mechanism is confirmed by measurement with another attribute, the exact call is not.

Engine changes that improve MTS with no work: programmable speaker Global/Universe playback no longer plays for every force (a cross-team audio leak MTS could not script around); remote view gained chunk activation on zoom, easier clicking on moving entities and steadier multiplayer drag, which the whole spectate and follow-cam stack sits on.

## Engine facts measured today

Rig: Factorio 2.0.72 headless and 2.1.17 headless, freeplay scenario, RCON. Every row is a measured result.

| Fact | 2.0.72 | 2.1.17 |
|---|---|---|
| `LuaEntity::active` write | allowed; on a steam engine it sets `disabled_by_script=true` | error "LuaEntity::active is read only." |
| `LuaEntity::minable` write | allowed | error "LuaEntity::minable is read only." |
| `minable_flag = false` | `minable` reads false | `minable` reads false |
| `display_panel_text = "string"` / `= {"locale.key"}` | both accepted | string accepted; table raises "string expected, got table" |
| display panel, 600-character write | 600 kept | 500 kept |
| `defines.input_action.translate_string` | 240 | nil |
| `defines.events.on_player_color_changed` / `on_next_day_started` | nil / nil | 204 / 223 |
| `helpers.compare_versions(script.active_mods.base, "2.1.0")` | -1 | 1 |
| `helpers.stage` | absent | present |
| `LuaRecipePrototype.category` / `.categories` | "smelting" / absent | absent / `{"smelting"}`; 64 recipes carry more than one |
| `prototypes.item["automation-science-pack"].type`; items of type `tool` | "tool"; 12 | "item"; 0 |
| `prototypes.entity["lab"].lab_inputs` | 12, first `automation-science-pack` | same |
| `LuaItemPrototype::used_by_labs`, `used-by-labs` filter | absent | present, 12 items |
| `LuaForce` `add_custom_alert` / `remove_alert` / `get_space_platforms` / `unlock_logistic_network` / `set_script_visible` / `is_visible` / `play_music` | all absent | all present |
| `script.feature_flags` | no `expansion` key | `expansion = true` |
| Unknown attribute write on a LuaEntity | raises "doesn't contain key", caught by pcall | same |
| Steam engine, `disabled_by_script = true` | output stops (radar `no_power`) | same |
| Nuclear reactor, `disabled_by_script = true` | temperature stops rising, fuel stops burning | same |
| Electric energy interface, `disabled_by_script = true` | frozen (buffer stays 0) | same; `output_flow_limit = 0` also works, EEI only |
| Solar panel, `disabled_by_script = true` | flag reads back false, full output continues | same |
| Solar panel, `active = false` | full output continues | n/a (read only) |
| `surface.solar_power_multiplier = 0` | radar `no_power` within 90 ticks; `= 1` restores | same |
| MTS master `pause_team` on entities owned by a team | freezes and thaws cleanly | throws at power.lua:84, accumulators left charged |
| MTS master `ensure_passive_radar` | returns the radar | throws at remote_api.lua:785 |

The solar rows confirm the existing design in `scripts/pause/power.lua:142-155` (the entity flag never touched solar; MTS zeroes the surface multiplier), not a gap.

## Still needs a GUI client (Steam build, 2.1.17)

- Spectate exit and the other teleport sites after the 2.1.7 remote-view change (finding 6).
- Landing pen first build on 2.1 after the `minable_flag` fix (finding 3).
- Phases 2/4/5/6 checklists in `docs/FACTORIO_21_PLAN.md` were never run in a client: V3 colour event firing, V4 alert rendering, V5 pins, V7 space-map gate; also the `disable_space_map` pcall on a real 2.0 client.
- Shared-location platform transfer: park two teams' platforms at `solar-system-edge`, request from team A's hub while team B's hub holds the item, watch whether it transfers; then test `providing_to_other_platforms = false`.
- The expansion-base alert versus passivised radars: trigger a base inside and just outside the nearby ring.
- Stats science tab, science milestone and reaper markers after the `lab_inputs` change, with and without Space Age.
- `input_quality_counts` equality against the per-quality `get_input_count` loop on a save with real non-normal production.
- `player.opened = defines.gui_type.player_management` as admin and non-admin.
- `"+ open-discord-bridge"` with the bridge downloaded but disabled, and with it absent.

## Recommended order of work

1. Decide the one-tree layout and the version convention for the two lines.
2. Merge master into the 2.1 work; re-apply the recipe fix in `gui/stats/discovery.lua`; fix findings 1 to 5 in their dual-compat forms; add the engine helper; apply the guard table; cap the Run Info box.
3. Update `~/factorio-2.1` to 2.1.17 from the expansion channel (the `factorio-switch` skill records the download path) so the GUI list runs against the current engine.
4. Run the GUI list above.
5. Companion releases: open-discord-bridge (clean), brave-new-mts (minable writes), mts-dimension-warp (active writes and the fluidbox rework), on the same one-tree pattern.
