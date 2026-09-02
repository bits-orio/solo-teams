-- scripts/reaper/scan.lua
-- Reads the world and returns a verdict per occupied team slot. Pure
-- measurement: nothing here destroys anything.

local surface_utils = require("scripts.surface_utils")
local force_utils   = require("scripts.force_utils")
local team_clock    = require("scripts.team_clock")
local helpers       = require("scripts.helpers")
local members_mod   = require("scripts.reaper.members")
local markers       = require("scripts.reaper.markers")
local config        = require("scripts.reaper.config")

local M = {}

M.REAP = "reap"
M.KEEP = "keep"
M.SKIP = "skip"

-- Bounds the per-surface entity sweep. Rows only need "none / a few / lots",
-- so an exact count on a mature base is wasted work.
local ENTITY_SCAN_LIMIT = 3000

local owned_surfaces = surface_utils.owned_surfaces_by_force

--- All-time produced totals for `names`, summed across the team's surfaces.
--- input_counts is read ONCE per surface and every wanted name looked up in
--- it, rather than a statistics call per item (the pattern gui/stats/counts
--- settled on). A force reads zero on surfaces it does not own.
--- Returns (totals, measured). `measured` is false when NO surface could be
--- read: an empty owned-surface list, or every statistics call failing.
---
--- The distinction is the whole point. A team that genuinely produced nothing
--- and a team we could not measure both yield zero, and only the first should
--- ever be destroyed. Without this, a transient API failure or a team whose
--- surfaces have not resolved reads as "never got going".
local function production(force, surfaces, names)
    local totals, measured = {}, false
    for _, name in ipairs(names) do totals[name] = 0 end
    for _, surface in ipairs(surfaces) do
        local ok, counts = pcall(function()
            return force.get_item_production_statistics(surface).input_counts
        end)
        if ok and counts then
            measured = true
            for _, name in ipairs(names) do
                totals[name] = totals[name] + (counts[name] or 0)
            end
        end
    end
    return totals, measured
end
M.production = production

--- Totals banked from surfaces the team no longer owns.
---
--- Production statistics live ON the surface, so deleting one discards them
--- permanently. MTS ships retire_team_surface (mts-v1), and mts-dimension-warp
--- calls it on every warp, so a warping team's science would otherwise reset to
--- zero and condemn it. accrue_from_surface banks the numbers first.
local function slot_generation(slot)
    return (storage.team_slot_generation or {})[slot] or 0
end

--- The bank is stamped with the slot generation it was written under, so a
--- stale entry can never be read by a later team on the same slot.
local function retired_totals(force_name)
    local bank = (storage.reaper_produced or {})[force_name]
    if not bank then return {} end
    local slot = helpers.team_slot(force_name)
    if not slot or bank.generation ~= slot_generation(slot) then return {} end
    return bank.totals or {}
end

--- Bank a surface's marker totals under an EXPLICIT owner, before the engine
--- throws them away. This is the path retire_team_surface calls (via the hook
--- control.lua injects) while ownership is still attributable.
---
--- Refuses for an unoccupied slot: cleanup_force_surfaces deletes surfaces
--- asynchronously, so the engine's pre-delete events arrive AFTER
--- release_team_slot has already freed the slot, and a bank written then would
--- be inherited by whoever claims it next.
function M.bank_surface(force_name, surface)
    if not (surface and surface.valid) then return false end
    if not (force_name and force_utils.is_team_force(force_name)) then return false end
    local slot = helpers.team_slot(force_name)
    if not slot or (storage.team_pool or {})[slot] ~= "occupied" then return false end
    local force = game.forces[force_name]
    if not (force and force.valid) then return false end

    markers.ensure()
    local names = {markers.tier1(), markers.tier2()}
    if not names[1] then return false end
    local totals = production(force, {surface}, names)

    local generation = slot_generation(slot)
    storage.reaper_produced = storage.reaper_produced or {}
    local bank = storage.reaper_produced[force_name]
    if not bank or bank.generation ~= generation then
        bank = {generation = generation, totals = {}}
    end
    for _, name in ipairs(names) do
        if name then
            bank.totals[name] = (bank.totals[name] or 0) + (totals[name] or 0)
        end
    end
    storage.reaper_produced[force_name] = bank
    return true
end

--- Event-path wrapper for on_pre_surface_deleted, attributing by ownership.
--- Only reaches a deletion that did NOT go through retire_team_surface (which
--- strips ownership first); it is defence for a third-party direct delete.
function M.accrue_from_surface(surface)
    if not (surface and surface.valid) then return false end
    return M.bank_surface(surface_utils.get_owner(surface), surface)
end

--- Drop a released slot's bank so a NEW team claiming it starts from zero.
function M.clear_retired(force_name)
    if storage.reaper_produced then storage.reaper_produced[force_name] = nil end
end

--- Real (non-ghost) entities the force owns. A blueprint paste can leave
--- hundreds of ghosts on a team that produced nothing, so counting ghosts
--- would overstate how much a dead team has to lose.
local function entity_count(force, surfaces)
    local total = 0
    for _, surface in ipairs(surfaces) do
        local ok, all = pcall(function()
            return surface.count_entities_filtered{force = force, limit = ENTITY_SCAN_LIMIT}
        end)
        local okg, ghosts = pcall(function()
            return surface.count_entities_filtered{
                force = force, type = "entity-ghost", limit = ENTITY_SCAN_LIMIT}
        end)
        -- Both counts are capped independently, so subtracting a capped ghost
        -- count from a capped total can report 0 for a mature base. At the cap
        -- the base is plainly substantial: report the cap rather than a
        -- subtraction that has lost its meaning.
        if ok and all then
            if all >= ENTITY_SCAN_LIMIT then
                total = total + all
            else
                total = total + math.max(0, all - ((okg and ghosts) or 0))
            end
        end
    end
    return total
end

--- Measure one team. `deep` also reads production and entity counts; the
--- cycle leaves it off for teams that fail the free offline test, since
--- input_counts builds a dictionary per surface.
local function snapshot_of(force_name, member_list, deep)
    local force    = game.forces[force_name]
    local surfaces = deep and owned_surfaces(force_name) or nil
    local last     = members_mod.last_seen_tick(member_list)
    local rep      = members_mod.representative(member_list)
    local names    = {markers.tier1(), markers.tier2()}
    local totals, measured = {}, false
    if deep and names[1] then
        totals, measured = production(force, surfaces, names)
    end
    local retired = retired_totals(force_name)
    -- Banked production from retired surfaces is measurement too.
    if next(retired) ~= nil then measured = true end

    return {
        force_name   = force_name,
        slot         = helpers.team_slot(force_name),
        display_name = helpers.display_name(force_name),
        leader_name  = rep and rep.name or nil,
        member_count = #member_list,
        connected    = members_mod.any_connected(member_list),
        last_seen    = last,
        offline_ticks = last and (game.tick - last) or nil,
        team_ticks   = team_clock.online_ticks(force_name),
        tier1        = (totals[names[1]] or 0) + (retired[names[1]] or 0),
        tier2        = names[2]
            and ((totals[names[2]] or 0) + (retired[names[2]] or 0)) or 0,
        entities     = deep and entity_count(force, surfaces) or nil,
        surfaces     = surfaces and #surfaces or nil,
        generation   = (storage.team_slot_generation or {})[helpers.team_slot(force_name)] or 0,
        deep         = deep and true or false,
        measured     = measured,
    }
end

--- The armed rule, in one place so the GUI preselection, the shadow verdict
--- and the live reaper can never disagree:
---   every member offline for the configured window, zero tier-1 science,
---   and at least one member on the team.
local function judge(snap)
    if snap.member_count == 0 then return M.SKIP, "no-members" end
    if snap.connected      then return M.KEEP, "online" end
    if not snap.offline_ticks then return M.SKIP, "never-seen" end
    if snap.offline_ticks < config.offline_ticks() then return M.KEEP, "recent" end
    if not snap.deep       then return M.SKIP, "not-measured" end
    -- "Could not measure" is not "produced nothing". Hand it to an admin.
    if not snap.measured   then return M.SKIP, "unmeasurable" end
    if snap.tier1 > 0      then return M.KEEP, "producing" end
    return M.REAP, "inactive"
end
M.judge = judge

--- Scan every occupied slot. opts.full measures production and entities for
--- ALL teams (what the Cleanup GUI renders); the default measures them only
--- for teams that already failed the offline test.
function M.run(opts)
    opts = opts or {}
    if not markers.ready() then
        return {ready = false, reason = markers.blocked_reason(), rows = {}}
    end

    local buckets   = members_mod.by_force()
    local threshold = config.offline_ticks()
    local rows      = {}

    for slot = 1, force_utils.max_teams() do
        local force_name = "team-" .. slot
        if (storage.team_pool or {})[slot] == "occupied" then
            local list = buckets[force_name] or {}
            -- Cheap gate: a team with somebody online, or seen inside the
            -- window, can never be reaped, so skip the expensive reads.
            local last  = members_mod.last_seen_tick(list)
            local stale = last ~= nil and (game.tick - last) >= threshold
                and not members_mod.any_connected(list)
            local deep  = opts.full or stale
            local snap  = snapshot_of(force_name, list, deep)
            snap.verdict, snap.reason = judge(snap)
            rows[#rows + 1] = snap
        end
    end

    return {ready = true, rows = rows}
end

--- Re-measure and re-judge ONE team. A queued disband may be acting on a
--- verdict hours old, or on one written before the save was last closed, so the
--- drain re-derives it against the live world instead of trusting the snapshot.
function M.judge_force(force_name)
    if not markers.ready() then return M.SKIP, "not-ready" end
    local list = members_mod.by_force()[force_name] or {}
    local snap = snapshot_of(force_name, list, true)
    local verdict, reason = judge(snap)
    return verdict, reason, snap
end

--- Teams the armed rule would destroy right now.
function M.reapable(result)
    local out = {}
    for _, row in ipairs(result.rows or {}) do
        if row.verdict == M.REAP then out[#out + 1] = row end
    end
    return out
end

return M
