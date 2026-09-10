-- scripts/reaper/execute.lua
-- Staged bulk disband. Tearing 20 teams down in one tick deletes 20 surfaces
-- at once and freezes the server for seconds, so the selection is queued and
-- drained a team at a time.

local teardown    = require("scripts.team_teardown")
local journal     = require("scripts.reaper.journal")
local members_mod = require("scripts.reaper.members")
local scan        = require("scripts.reaper.scan")
local helpers     = require("scripts.helpers")

local M = {}

-- Ticks between teardowns: a 20-team sweep stays under five seconds while the
-- surface deletions remain well separated.
--
-- The period must be one NO other handler in the mod uses. Factorio keeps
-- exactly one on_nth_tick handler per period per mod, so a shared period means
-- whichever registers last silently replaces the other. 15 belongs to
-- gui/platform_hub.lua; tests/tick_periods.py enforces uniqueness.
M.DRAIN_INTERVAL = 12

-- Players get a full minute's warning before the first teardown, repeated at
-- 30 and 10 seconds and counted down from 3: deleting surfaces stalls the
-- server briefly, and an unannounced stall reads as a crash. Each team is then
-- named as its teardown STARTS, never on completion.
M.WARNING_TICKS = 60 * 60
M.ANNOUNCE_AT_SECONDS = {60, 30, 10, 3, 2, 1}

local function queue()
    return storage.reaper_queue
end

function M.is_running() return queue() ~= nil end

--- Abandon a sweep. Used by /mts-reaper cancel, and by disarming (an armed
--- sweep must actually stop when the admin turns the feature off). Everyone
--- heard the warning, so everyone hears the cancellation.
function M.cancel(source)
    local q = queue()
    if not q then return 0 end
    if source and q.opts.source ~= source then return 0 end
    local left = #q.items - q.cursor
    storage.reaper_queue = nil
    helpers.broadcast({"mts-chat.bulk-disband-cancelled", left})
    log("[multi-team-support:reaper] queue cancelled with " .. left .. " pending")
    return left
end

function M.pending()
    local q = queue()
    return q and (#q.items - q.cursor) or 0
end

--- Queue a selection. Each entry carries the slot generation captured when the
--- admin selected it (or when the cycle judged it), so a slot recycled while
--- the queue drained is skipped rather than destroyed.
--- opts.admin_index - who to report back to
--- opts.inactive    - members are told the team was deemed inactive
--- opts.source      - "auto" or "manual", for the journal
function M.enqueue(entries, opts)
    if M.is_running() then return false end
    if not entries or #entries == 0 then return false end
    opts = opts or {}
    storage.reaper_queue = {
        items      = entries,
        cursor     = 0,
        opts       = opts,
        done       = 0,
        skipped    = {},
        tags       = {},
        start_tick = game.tick + M.WARNING_TICKS,
    }
    return true
end

local function finish(q)
    storage.reaper_queue = nil

    if q.done > 0 then
        helpers.broadcast({"mts-chat.teams-disbanded-bulk", q.done})
    end

    local admin = q.opts.admin_index and game.get_player(q.opts.admin_index)
    if admin and admin.valid then
        admin.print({"mts-reaper.bulk-done", q.done, #q.skipped})
        for _, entry in ipairs(q.skipped) do
            admin.print({"mts-reaper.bulk-skipped", entry.force_name, entry.reason})
        end
    end
    log("[multi-team-support:reaper] bulk disband finished: "
        .. q.done .. " disbanded, " .. #q.skipped .. " skipped")
end

--- Fire whichever scheduled warning has just come due. The smallest due
--- entry wins and everything larger is marked spent, so a queue that resumes
--- from a save mid-countdown says one thing rather than six at once.
local function announce(q)
    local remaining_s = math.ceil((q.start_tick - game.tick) / 60)
    if remaining_s < 1 then return end
    q.announced = q.announced or {}
    local due
    for _, s in ipairs(M.ANNOUNCE_AT_SECONDS) do
        if remaining_s <= s and not q.announced[s] and (not due or s < due) then due = s end
    end
    if not due then return end
    for _, s in ipairs(M.ANNOUNCE_AT_SECONDS) do
        if s >= due then q.announced[s] = true end
    end
    if due > 3 then
        helpers.broadcast({"mts-chat.bulk-disband-in", #q.items, due})
    else
        helpers.broadcast({"mts-chat.bulk-disband-countdown", due})
    end
end

--- Tear down at most one team. Called from the staged tick handler.
function M.tick()
    local q = queue()
    if not q then return end
    if game.tick % M.DRAIN_INTERVAL ~= 0 then return end
    if game.tick < (q.start_tick or 0) then announce(q); return end

    q.cursor = q.cursor + 1
    local entry = q.items[q.cursor]
    if not entry then finish(q); return end

    -- A verdict can be hours old by the time the queue reaches it, and a queue
    -- persisted in the save can resume after a restart with a verdict older
    -- still. Re-derive it against the live world rather than trusting the
    -- snapshot: this re-checks the offline window and the science reading, not
    -- just whether somebody is connected this instant.
    if q.opts.recheck then
        local verdict = scan.judge_force(entry.force_name)
        if verdict ~= scan.REAP then
            q.skipped[#q.skipped + 1] =
                {force_name = entry.force_name, reason = "no-longer-inactive"}
            local list = members_mod.by_force()[entry.force_name] or {}
            if members_mod.any_connected(list) and list[1] then
                journal.note_return(list[1], entry.force_name, entry.slot)
            end
            if q.cursor >= #q.items then finish(q) end
            return
        end
    end

    -- Name the team as its teardown starts. Checked first so a slot recycled
    -- since the verdict is skipped silently rather than announced and skipped.
    if teardown.check(entry.force_name, entry.generation) then
        helpers.broadcast({"mts-chat.disbanding-team",
            helpers.team_tag_with_leader(entry.force_name)})
    end

    local ok, result = teardown.teardown(entry.force_name, {
        expected_generation = entry.generation,
        silent   = true,             -- one summary line, not N broadcasts
        inactive = q.opts.inactive,
    })

    if ok then
        q.done = q.done + 1
        q.tags[#q.tags + 1] = result
        if q.opts.source == "auto" then
            journal.note_executed(entry.force_name, entry.slot, entry.snapshot)
        else
            journal.note_manual_disband(entry.force_name, entry.slot,
                q.opts.admin_name or "admin")
        end
    else
        q.skipped[#q.skipped + 1] = {force_name = entry.force_name, reason = result}
    end

    if q.cursor >= #q.items then finish(q) end
end

--- Build queue entries from scan rows.
function M.entries_from_rows(rows)
    local out = {}
    for _, row in ipairs(rows) do
        out[#out + 1] = {
            force_name = row.force_name,
            slot       = row.slot,
            generation = row.generation,
            snapshot   = {
                offline_ticks = row.offline_ticks,
                tier1         = row.tier1,
                team_ticks    = row.team_ticks,
                display_name  = row.display_name,
            },
        }
    end
    return out
end

return M
