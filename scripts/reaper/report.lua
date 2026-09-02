-- scripts/reaper/report.lua
-- Admin commands for the reaper: run a cycle on demand, read the shadow
-- evidence, dump it as CSV, and arm or tune it.
--
-- NOTE: `helpers` here is Factorio's GLOBAL helpers table (write_file). MTS's
-- own scripts/helpers is aliased to mts_helpers to avoid shadowing it.

local mts_helpers = require("scripts.helpers")
local reaper      = require("scripts.reaper")
local config      = require("scripts.reaper.config")
local markers     = require("scripts.reaper.markers")
local journal     = require("scripts.reaper.journal")
local scan        = require("scripts.reaper.scan")
local execute     = require("scripts.reaper.execute")

local M = {}

local CSV_FILE = "mts-reaper-audit.csv"

local function ticks_to_days(ticks)
    return ticks and (ticks / config.TICKS_PER_DAY) or -1
end

local function ticks_to_hours(ticks)
    return (ticks or 0) / config.TICKS_PER_HOUR
end

-- ─── CSV ───────────────────────────────────────────────────────────────

local function csv_cell(text)
    return '"' .. tostring(text or ""):gsub('"', "'") .. '"'
end

local function csv_row(row)
    return table.concat({
        tostring(row.slot),
        csv_cell(row.display_name),
        csv_cell(row.leader_name),
        tostring(row.member_count),
        string.format("%.2f", ticks_to_days(row.offline_ticks)),
        string.format("%.2f", ticks_to_hours(row.team_ticks)),
        tostring(row.entities or -1),
        tostring(row.surfaces or -1),
        tostring(row.tier1 or 0),
        tostring(row.tier2 or 0),
        row.verdict,
        row.reason,
    }, ",")
end

--- Write the full measurement to script-output, in the same shape the design
--- was validated against, so a later run can be analysed the same way.
function M.dump_csv(player)
    local result = scan.run{full = true}
    if not result.ready then return nil, result.reason end

    local lines = {"slot,name,leader,members,offline_days,team_hours,entities,"
        .. "surfaces," .. (markers.tier1() or "tier1") .. ","
        .. (markers.tier2() or "tier2") .. ",verdict,reason"}
    for _, row in ipairs(result.rows) do lines[#lines + 1] = csv_row(row) end

    -- for_player = 0 writes to the SERVER only. Omitting it writes the file to
    -- every connected player's disk, and this CSV carries every team's leader
    -- name, playtime and last-seen time.
    local text = table.concat(lines, "\n") .. "\n"
    helpers.write_file(CSV_FILE, text, false, 0)
    if player then helpers.write_file(CSV_FILE, text, false, player.index) end
    return #result.rows
end

-- ─── Text report ───────────────────────────────────────────────────────

local function print_markers(out)
    local t1, t2 = markers.tier1(), markers.tier2()
    out({"mts-reaper.report-markers",
        tostring(t1 or "-"), tostring(t2 or "-"),
        markers.is_override("tier1") and "*" or ""})
    if not markers.ready() then out(markers.blocked_reason()) end
end

local function print_stats(out)
    local s = journal.stats()
    out({"mts-reaper.report-mode",
        config.value("auto_disband_enabled") and {"mts-reaper.mode-armed"}
            or {"mts-reaper.mode-shadow"},
        config.value("offline_days"), config.value("cycle_hours")})
    out({"mts-reaper.report-counts", s.cycles, s.flagged, reaper.free_slots()})
    out({"mts-reaper.report-evidence",
        s.resurrections, s.agreements, s.disagreements, s.executed})
end

local function print_resurrections(out)
    local recent = journal.recent(journal.RESURRECTION, 5)
    if #recent == 0 then return end
    out({"mts-reaper.report-returns-header"})
    for _, entry in ipairs(recent) do
        out({"mts-reaper.report-return-line", entry.slot,
            entry.player_name or "?",
            string.format("%.1f", ticks_to_days(entry.stood_ticks))})
    end
end

function M.report(player)
    local function out(msg) player.print(msg) end
    print_markers(out)
    print_stats(out)
    print_resurrections(out)
end

-- ─── Commands ──────────────────────────────────────────────────────────

local SETTABLE = {offline_days = true, cycle_hours = true, slot_pressure_min = true}

local function handle_set(player, args)
    local key, raw = args[2], tonumber(args[3])
    if not (key and SETTABLE[key] and raw) then
        player.print({"mts-reaper.set-usage"}); return
    end
    local stored = config.set_number(key, raw)
    player.print({"mts-reaper.set-done", key, tostring(stored)})
end

local function handle_arm(player, on)
    if on and not markers.ready() then
        player.print(markers.blocked_reason()); return
    end
    -- Disarming must actually stop an armed sweep already draining, otherwise
    -- "off" only prevents the NEXT one.
    if not on then
        local dropped = execute.cancel("auto")
        if dropped > 0 then player.print({"mts-reaper.cancel-done", dropped}) end
    end
    config.set_flag("auto_disband_enabled", on)
    player.print(on and {"mts-reaper.armed"} or {"mts-reaper.disarmed"})
    log("[multi-team-support:reaper] auto disband "
        .. (on and "ARMED" or "disarmed") .. " by " .. player.name)
end

local function handle_scan(player)
    local result = reaper.run_cycle{full = true}
    if not result.ready then player.print(result.reason); return end
    player.print({"mts-reaper.scan-done", #result.rows, result.flagged or 0,
        result.enqueued or 0})
end

local function handle_dump(player)
    local count, reason = M.dump_csv(player)
    if not count then player.print(reason); return end
    player.print({"mts-reaper.dump-done", count, CSV_FILE})
end

--- /mts-reaper marker <tier1|tier2> <item-name|auto>. The GUI offers the same
--- control; this exists so a blocked marker can always be fixed from chat.
local function handle_marker(player, args)
    local tier, item = args[2], args[3]
    if not ((tier == "tier1" or tier == "tier2") and item) then
        player.print({"mts-reaper.marker-usage"}); return
    end
    local ok = markers.set_override(tier, item ~= "auto" and item or nil)
    if not ok then player.print({"mts-reaper.marker-rejected", item}); return end
    player.print({"mts-reaper.marker-set", tier, tostring(markers[tier]() or "-")})
end

local SUBCOMMANDS = {
    report = function(player) M.report(player) end,
    scan   = handle_scan,
    dump   = handle_dump,
    arm    = function(player) handle_arm(player, true) end,
    disarm = function(player) handle_arm(player, false) end,
    reset  = function(player)
        journal.reset(); player.print({"mts-reaper.reset-done"})
    end,
    cancel = function(player)
        local dropped = execute.cancel()
        player.print(dropped > 0 and {"mts-reaper.cancel-done", dropped}
            or {"mts-reaper.cancel-none"})
    end,
}

local function split(text)
    local out = {}
    for word in tostring(text or ""):gmatch("%S+") do out[#out + 1] = word end
    return out
end

function M.register()
    commands.add_command("mts-reaper", {"mts-reaper.help"}, function(cmd)
        local player = cmd.player_index and game.get_player(cmd.player_index)
        if not player then game.print({"mts-cmd.player-only"}); return end
        if not player.admin then player.print({"mts-reaper.admin-only"}); return end

        local args = split(cmd.parameter)
        local sub  = args[1] or "report"
        if sub == "set"    then handle_set(player, args); return end
        if sub == "marker" then handle_marker(player, args); return end

        local fn = SUBCOMMANDS[sub]
        if not fn then player.print({"mts-reaper.usage"}); return end
        fn(player)
    end)
end

return M
