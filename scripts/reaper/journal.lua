-- scripts/reaper/journal.lua
-- Shadow-mode evidence: what the reaper decided, and whether reality agreed.
--
-- Two questions decide whether the rule is safe to arm, and neither can be
-- answered by argument:
--   resurrection - of the teams flagged REAP, how many came back online?
--   agreement    - when the admin disbands by hand, had the reaper flagged it?
-- Both are recorded from events (join, disband), not polled.

local config = require("scripts.reaper.config")

local M = {}

M.RESURRECTION = "resurrection"
M.AGREEMENT    = "agreement"
M.DISAGREEMENT = "disagreement"
M.EXECUTED     = "executed"

local function verdicts()
    storage.reaper_verdicts = storage.reaper_verdicts or {}
    return storage.reaper_verdicts
end

local function history()
    storage.reaper_history = storage.reaper_history or {}
    return storage.reaper_history
end

function M.stats()
    storage.reaper_stats = storage.reaper_stats or
        {cycles = 0, flagged = 0, resurrections = 0, agreements = 0,
         disagreements = 0, executed = 0}
    return storage.reaper_stats
end

--- Append to a bounded ring buffer. A save that runs for months must not grow
--- an unbounded log, and only the most recent events are ever read.
local function append(kind, data)
    local log   = history()
    local limit = config.value("history_limit")
    data.kind, data.tick = kind, game.tick
    log[#log + 1] = data
    while #log > limit do table.remove(log, 1) end
end
M.append = append

--- Replace the standing verdict set with this cycle's. Keyed by slot and
--- stamped with the slot generation, so a verdict can never be attributed to
--- the NEXT team that claims the slot.
function M.record_cycle(rows)
    local store = {}
    local flagged = 0
    for _, row in ipairs(rows) do
        store[row.slot] = {
            verdict    = row.verdict,
            reason     = row.reason,
            generation = row.generation,
            force_name = row.force_name,
            at         = game.tick,
            snapshot   = {
                offline_ticks = row.offline_ticks,
                team_ticks    = row.team_ticks,
                tier1         = row.tier1,
                tier2         = row.tier2,
                entities      = row.entities,
                member_count  = row.member_count,
                leader_name   = row.leader_name,
                display_name  = row.display_name,
            },
        }
        if row.verdict == "reap" then flagged = flagged + 1 end
    end
    storage.reaper_verdicts = store

    local stats = M.stats()
    stats.cycles  = stats.cycles + 1
    stats.flagged = flagged
    storage.reaper_last_run = game.tick
    return flagged
end

function M.verdict_for(slot)
    return verdicts()[slot]
end

--- True when the standing verdict still describes the team occupying that slot
--- (guards against a slot recycled since the verdict was written).
local function standing_reap(slot, force_name)
    local entry = verdicts()[slot]
    if not entry or entry.verdict ~= "reap" then return nil end
    if force_name and entry.force_name ~= force_name then return nil end
    local current = (storage.team_slot_generation or {})[slot] or 0
    if entry.generation ~= current then return nil end
    return entry
end
M.standing_reap = standing_reap

--- A player returning to a team the reaper had condemned is the one measurement
--- that proves the threshold too aggressive. Called from the join event.
function M.note_return(player, force_name, slot)
    local entry = standing_reap(slot, force_name)
    if not entry then return false end

    entry.verdict = "keep"
    entry.reason  = "returned"
    M.stats().resurrections = M.stats().resurrections + 1
    append(M.RESURRECTION, {
        slot = slot, force_name = force_name, player_name = player.name,
        stood_ticks = game.tick - (entry.at or game.tick),
        snapshot = entry.snapshot,
    })
    return true
end

--- Did the reaper agree with a disband the admin made by hand?
function M.note_manual_disband(force_name, slot, admin_name)
    local entry = verdicts()[slot]
    local agreed = standing_reap(slot, force_name) ~= nil
    local stats = M.stats()
    if agreed then stats.agreements = stats.agreements + 1
    else           stats.disagreements = stats.disagreements + 1 end
    append(agreed and M.AGREEMENT or M.DISAGREEMENT, {
        slot = slot, force_name = force_name, admin = admin_name,
        verdict = entry and entry.verdict or "none",
        snapshot = entry and entry.snapshot or nil,
    })
    verdicts()[slot] = nil
end

--- The reaper destroyed a team itself (phase 3, armed).
function M.note_executed(force_name, slot, snapshot)
    M.stats().executed = M.stats().executed + 1
    append(M.EXECUTED, {slot = slot, force_name = force_name, snapshot = snapshot})
    verdicts()[slot] = nil
end

function M.recent(kind, count)
    local out = {}
    local log = history()
    for i = #log, 1, -1 do
        local entry = log[i]
        if not kind or entry.kind == kind then
            out[#out + 1] = entry
            if count and #out >= count then break end
        end
    end
    return out
end

function M.reset()
    storage.reaper_history  = {}
    storage.reaper_verdicts = {}
    storage.reaper_stats    = nil
    M.stats()
end

return M
