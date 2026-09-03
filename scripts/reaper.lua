-- scripts/reaper.lua
-- Facade for the inactive-team reaper. Owns the cycle clock, the join hook and
-- the arming decision; the measurement, evidence and destruction live in
-- scripts/reaper/.
--
-- Shipping order: the cycle records verdicts and changes nothing until an admin
-- turns on auto_disband_enabled. Shadow evidence first, arming second.

local config      = require("scripts.reaper.config")
local markers     = require("scripts.reaper.markers")
local scan        = require("scripts.reaper.scan")
local journal     = require("scripts.reaper.journal")
local execute     = require("scripts.reaper.execute")
local members_mod = require("scripts.reaper.members")
local helpers     = require("scripts.helpers")
local force_utils = require("scripts.force_utils")
local spectator   = require("scripts.spectator")

local M = {}

M.config  = config
M.markers = markers
M.scan    = scan
M.journal = journal
M.execute = execute

function M.on_init()
    markers.resolve()
    journal.stats()
end

function M.on_configuration_changed()
    markers.resolve()
    -- A bulk sweep half-drained when the save was last closed is abandoned
    -- rather than resumed across a mod update: its queued snapshots describe a
    -- world that may no longer exist. Nothing is lost, the next cycle re-flags.
    storage.reaper_queue = nil
end

-- ─── Cycle ─────────────────────────────────────────────────────────────

--- One measurement pass. Always records verdicts; destroys only when armed.
--- opts.force_auto - run the armed path even mid-interval (manual command)
function M.run_cycle(opts)
    opts = opts or {}
    local result = scan.run{full = opts.full}
    if not result.ready then return result end

    local flagged = journal.record_cycle(result.rows)
    result.flagged = flagged

    if config.value("auto_disband_enabled") and flagged > 0
       and not execute.is_running() then
        local rows = scan.reapable(result)
        execute.enqueue(execute.entries_from_rows(rows), {
            inactive = true,
            source   = "auto",
            recheck  = true,
        })
        result.enqueued = #rows
    end

    M.notify_admins(result)
    return result
end

--- Fixed hourly wake-up that acts only when cycle_hours have elapsed. The
--- period is a constant so on_load re-registers identically; the interval is
--- the configurable part.
function M.heartbeat()
    if game.tick == 0 then return end
    local due = (storage.reaper_last_run or 0)
        + config.value("cycle_hours") * config.TICKS_PER_HOUR
    if game.tick < due then return end
    M.run_cycle()
end

--- The tick the next cycle will actually run. The heartbeat fires on fixed
--- boundaries and runs the cycle when it finds the interval elapsed, so the
--- real moment is the first boundary at or after the due tick, not the due
--- tick itself.
function M.next_run_tick()
    local due = (storage.reaper_last_run or 0)
        + config.value("cycle_hours") * config.TICKS_PER_HOUR
    local hb  = config.HEARTBEAT_TICKS
    local earliest = math.max(due, game.tick + 1)
    return math.ceil(earliest / hb) * hb
end

-- ─── Reminders ─────────────────────────────────────────────────────────

function M.free_slots()
    local free = 0
    local pool = storage.team_pool or {}
    for slot = 1, force_utils.max_teams() do
        if pool[slot] ~= "occupied" then free = free + 1 end
    end
    return free
end

--- Teams the armed rule would take right now, from the standing verdicts.
--- Cheap enough for a GUI badge: it reads the last cycle, it does not rescan.
function M.badge_count()
    local n = 0
    for slot, entry in pairs(storage.reaper_verdicts or {}) do
        if journal.standing_reap(slot, entry.force_name) then n = n + 1 end
    end
    return n
end

local function admins()
    local out = {}
    for _, player in pairs(game.connected_players) do
        if player.admin then out[#out + 1] = player end
    end
    return out
end

--- Tell connected admins what the cycle found. Silent when there is nothing
--- to act on, so a quiet server never nags.
function M.notify_admins(result)
    local flagged = result.flagged or 0
    if flagged == 0 then return end
    local free = M.free_slots()
    for _, admin in ipairs(admins()) do
        admin.print({"mts-reaper.cycle-summary", flagged, free})
    end
end

--- Slot pressure, dispatched from the team created/released events rather than
--- polled. Fires once per crossing of the threshold, not on every claim.
function M.on_team_changed()
    local free = M.free_slots()
    local threshold = config.value("slot_pressure_min")
    local was_low = storage.reaper_pressure_low or false
    local is_low  = free <= threshold
    storage.reaper_pressure_low = is_low
    if not is_low or was_low then return end

    local reapable = M.badge_count()
    if reapable == 0 then return end
    for _, admin in ipairs(admins()) do
        admin.print({"mts-reaper.slot-pressure", free, reapable})
    end
end

-- ─── Surfaces and slots ────────────────────────────────────────────────

--- Bank a team's production before the engine discards it with the surface.
--- Registered on on_pre_surface_deleted: by on_surface_deleted the statistics
--- are already gone.
function M.on_pre_surface_deleted(event)
    local surface = event and event.surface_index and game.surfaces[event.surface_index]
    if surface then scan.accrue_from_surface(surface) end
end

--- Hook target for team_surfaces.retire_team_surface: bank the surface while
--- its owner is still known. See scan.bank_surface for why the engine event
--- cannot cover this path.
function M.on_surface_retiring(force_name, surface)
    scan.bank_surface(force_name, surface)
end

--- A released slot's banked production must not follow the force name onto the
--- next team that claims it.
function M.on_team_released(event)
    local force_name = event and event.force_name
    if force_name then scan.clear_retired(force_name) end
    M.on_team_changed()
end

-- ─── Player join ───────────────────────────────────────────────────────

--- Two jobs on join: tell a returning player their team was disbanded, and
--- record a resurrection if the reaper had condemned the team they came back
--- to. The second is the measurement that proves the threshold safe or not.
function M.on_player_joined(player)
    if not (player and player.valid) then return end

    local notices = storage.reaper_notice
    if notices and notices[player.index] then
        notices[player.index] = nil
        player.print({"mts-chat.team-disbanded-inactive"})
    end

    -- Effective force, not player.force: a spectating player physically sits on
    -- the spectator force, and every other reaper read resolves it this way.
    local force_name = spectator.get_effective_force(player)
    if not (force_name and force_utils.is_team_force(force_name)) then return end
    local slot = helpers.team_slot(force_name)
    if slot then journal.note_return(player, force_name, slot) end
end

return M
