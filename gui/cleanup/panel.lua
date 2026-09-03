-- gui/cleanup/panel.lua
-- The admin Cleanup frame: measurement table, the private thresholds, and the
-- bulk disband action.

local helpers = require("scripts.helpers")
local confirm = require("gui.confirm")
local reaper  = require("scripts.reaper")
local config  = require("scripts.reaper.config")
local markers = require("scripts.reaper.markers")
local scan    = require("scripts.reaper.scan")
local execute = require("scripts.reaper.execute")
local state   = require("gui.cleanup.state")
local rows_mod = require("gui.cleanup.rows")

local M = {}

M.FRAME_NAME = "sb_cleanup_frame"

local function add_summary(parent, result)
    local flow = parent.add{type = "flow", direction = "vertical"}
    flow.style.bottom_margin = 6

    flow.add{type = "label", caption = {"mts-cleanup.summary-mode",
        config.value("auto_disband_enabled") and {"mts-reaper.mode-armed"}
            or {"mts-reaper.mode-shadow"}}}
    flow.add{type = "label", caption = {"mts-cleanup.summary-slots",
        reaper.free_slots(), #(result.rows or {})}}
    flow.add{type = "label", caption = {"mts-cleanup.summary-markers",
        tostring(markers.tier1() or "-"), tostring(markers.tier2() or "-")}}
    -- When armed this is the moment flagged teams go, so say so plainly.
    local wait = helpers.fmt_span(math.max(0, reaper.next_run_tick() - game.tick))
    local next_line
    if config.value("auto_disband_enabled") then
        next_line = {"mts-cleanup.summary-next-armed", wait}
    else
        next_line = {"mts-cleanup.summary-next-shadow", wait}
    end
    flow.add{type = "label", caption = next_line}
end

--- Threshold and marker controls. These live here and NOT in settings.lua
--- because Factorio shows runtime-global settings to every player.
local function add_controls(parent)
    local box = parent.add{type = "frame", direction = "vertical",
        style = "inside_shallow_frame_with_padding"}

    local top = box.add{type = "flow", direction = "horizontal"}
    top.style.vertical_align = "center"
    top.style.horizontal_spacing = 8
    top.add{type = "checkbox", name = "sb_cleanup_arm",
        state   = config.value("auto_disband_enabled") == true,
        caption = {"mts-cleanup.arm-label"},
        tooltip = {"mts-cleanup.arm-tip"}}

    top.add{type = "label", caption = {"mts-cleanup.offline-days-label"}}
    local field = top.add{type = "textfield", name = "sb_cleanup_offline_days",
        text = tostring(config.value("offline_days")), numeric = true,
        allow_decimal = false, allow_negative = false}
    field.style.width = 40

    local marker_row = box.add{type = "flow", direction = "horizontal"}
    marker_row.style.vertical_align = "center"
    marker_row.style.horizontal_spacing = 8
    marker_row.add{type = "label", caption = {"mts-cleanup.markers-label"},
        tooltip = {"mts-cleanup.markers-tip"}}
    for _, tier in ipairs(markers.TIERS) do
        marker_row.add{
            type       = "choose-elem-button",
            name       = "sb_cleanup_marker_" .. tier,
            elem_type  = "item",
            item       = markers[tier == "tier1" and "tier1" or "tier2"](),
            tags       = {mts_cleanup_marker = tier},
        }
    end
    return box
end

local function add_footer(parent, player, rows)
    local selected = #state.selected_rows(player, rows)
    local flow = parent.add{type = "flow", direction = "horizontal"}
    flow.style.top_margin = 6
    flow.style.horizontal_spacing = 8
    flow.style.vertical_align = "center"

    flow.add{type = "button", name = "sb_cleanup_select_suggested",
        caption = {"mts-cleanup.select-suggested"}}
    flow.add{type = "button", name = "sb_cleanup_clear",
        caption = {"mts-cleanup.clear-selection"}}
    flow.add{type = "button", name = "sb_cleanup_refresh",
        caption = {"mts-cleanup.refresh"},
        tooltip = {"mts-cleanup.refresh-tip"}}

    local spacer = flow.add{type = "empty-widget"}
    spacer.style.horizontally_stretchable = true

    local disband = flow.add{type = "button", name = "sb_cleanup_disband",
        caption = {"mts-cleanup.disband-selected", selected},
        style   = "red_button",
        enabled = selected > 0 and not execute.is_running()}
    if execute.is_running() then
        disband.tooltip = {"mts-cleanup.tip-busy", execute.pending()}
    end
end

--- Rows for this player's open panel. A full measurement reads production
--- statistics for every team on every surface it owns, which is far too
--- expensive to repeat on each checkbox click. The panel measures when it is
--- opened or explicitly refreshed, and re-renders from that snapshot.
local function rows_for(player, rescan)
    if rescan or not state.cached(player) then
        state.cache(player, scan.run{full = true})
    end
    return state.cached(player)
end

function M.build(player, rescan)
    if not player.admin then return end

    storage.cleanup_gui_location = storage.cleanup_gui_location or {}
    local frame = helpers.reuse_or_create_frame(
        player, M.FRAME_NAME, storage.cleanup_gui_location, {x = 200, y = 120})

    local title_bar = helpers.add_title_bar(frame, {"mts-cleanup.title"})
    title_bar.add{type = "sprite-button", name = "sb_cleanup_close",
        sprite = "utility/close", style = "close_button",
        tooltip = {"mts-tip.close-panel"}}

    local result = rows_for(player, rescan)

    -- Summary and controls render even when the check is blocked: the marker
    -- override buttons ARE the recovery path for a blocked marker, so they
    -- must not sit behind the very condition they are meant to clear.
    add_summary(frame, result)
    add_controls(frame)
    if not result.ready then
        local blocked = frame.add{type = "label", caption = result.reason}
        blocked.style.single_line   = false
        blocked.style.maximal_width = 720
        blocked.style.top_margin    = 8
        return frame
    end

    local rows = state.apply_sort(player, result.rows)

    local scroll = frame.add{type = "scroll-pane", name = "sb_cleanup_scroll"}
    scroll.style.maximal_height = 520
    scroll.style.minimal_width  = 760
    rows_mod.build(scroll, player, rows)

    add_footer(frame, player, rows)
    return frame
end

--- Live measurement, for decisions rather than rendering. The confirm dialog
--- and the queue must act on the world as it is now, not on a snapshot that
--- may be several clicks old.
function M.current_rows()
    local result = scan.run{full = true}
    return result.ready and result.rows or {}
end

--- Re-render from the cached measurement (checkbox clicks, sorting).
function M.refresh(player)
    if player.gui.screen[M.FRAME_NAME] then M.build(player, false) end
end

--- Re-measure and re-render (the Refresh button, and after a disband sweep).
function M.rescan(player)
    if player.gui.screen[M.FRAME_NAME] then M.build(player, true) end
end

function M.refresh_all()
    for _, player in pairs(game.connected_players) do
        if player.admin then M.rescan(player) end
    end
end

function M.toggle(player)
    if not player.admin then return end
    local frame = player.gui.screen[M.FRAME_NAME]
    if frame then
        storage.cleanup_gui_location = storage.cleanup_gui_location or {}
        storage.cleanup_gui_location[player.index] = frame.location
        frame.destroy()
        state.drop_cache(player)
        return
    end
    -- Measure once on opening, then preselect the armed rule's picks from that
    -- same snapshot so a later re-render never overwrites the admin's edits.
    local result = rows_for(player, true)
    if result.ready then state.preselect(player, result.rows) end
    M.build(player, false)
end

--- Stage the selection and ask for confirmation, naming every team.
function M.request_disband(player)
    local rows     = M.current_rows()
    local selected = state.selected_rows(player, rows)
    if #selected == 0 then return end

    state.stage(player, execute.entries_from_rows(selected))

    -- Name every team, capped so a 40-team sweep does not overflow the dialog.
    -- The overflow count joins the list rather than sitting in the sentence, so
    -- a selection that fits reads without a trailing "and 0 more".
    local names = {}
    for _, row in ipairs(selected) do
        names[#names + 1] = {"mts-cleanup.confirm-line", row.slot,
            row.display_name, row.leader_name or "-"}
        if #names >= 12 then break end
    end
    local extra = #selected - #names
    if extra > 0 then names[#names + 1] = {"mts-cleanup.confirm-more", extra} end

    confirm.show(player, {
        title        = {"mts-cleanup.confirm-title", #selected},
        message      = {"mts-cleanup.confirm-message", #selected,
                        helpers.ls_join(names, "\n")},
        confirm_text = {"mts-cleanup.confirm-ok"},
        cancel_text  = {"mts-confirm.cancel"},
        action       = "cleanup_bulk",
    })
end

confirm.register("cleanup_bulk", function(player, _data)
    local entries = state.take_staged(player)
    if not entries or #entries == 0 then return end
    local ok = execute.enqueue(entries, {
        admin_index = player.index,
        admin_name  = player.name,
        source      = "manual",
        recheck     = true,
        inactive    = true,
    })
    if not ok then player.print({"mts-cleanup.busy"}); return end
    player.print({"mts-cleanup.started", #entries})
    M.rescan(player)
end)

return M
