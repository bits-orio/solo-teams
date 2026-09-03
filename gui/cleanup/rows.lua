-- gui/cleanup/rows.lua
-- The Cleanup table: sortable header plus one row per occupied team slot.

local helpers = require("scripts.helpers")
local counts  = require("gui.stats.counts")
local state   = require("gui.cleanup.state")
local markers = require("scripts.reaper.markers")

local M = {}

local VERDICT_COLOR = {
    reap = {1.0, 0.45, 0.4},
    keep = {0.45, 1.0, 0.45},
    skip = {0.7,  0.7,  0.7},
}

local VERDICT_LABEL = {
    reap = {"mts-cleanup.verdict-reap"},
    keep = {"mts-cleanup.verdict-keep"},
    skip = {"mts-cleanup.verdict-skip"},
}

-- caption: locale key. sort: sort key, nil = not sortable. icon: function
-- returning an item name to draw in place of the caption (the two progress
-- marker columns are items, so they show the flask rather than a word).
local COLUMNS = {
    {caption = {"mts-cleanup.col-pick"}},
    {caption = {"mts-cleanup.col-verdict"},  sort = "verdict"},
    {caption = {"mts-cleanup.col-slot"},     sort = "slot"},
    {caption = {"mts-cleanup.col-team"}},
    {caption = {"mts-cleanup.col-leader"}},
    {caption = {"mts-cleanup.col-members"}},
    {caption = {"mts-cleanup.col-offline"},  sort = "offline"},
    {caption = {"mts-cleanup.col-playtime"}, sort = "team_hours"},
    {caption = {"mts-cleanup.col-tier1"},    sort = "tier1", icon = markers.tier1},
    {caption = {"mts-cleanup.col-tier2"},    sort = "tier2", icon = markers.tier2},
    {caption = {"mts-cleanup.col-entities"}, sort = "entities"},
}

M.COLUMN_COUNT = #COLUMNS

local function fmt_offline(row)
    if row.connected then return {"mts-cleanup.offline-online"} end
    if not row.offline_ticks then return {"mts-cleanup.offline-never"} end
    return helpers.fmt_span(row.offline_ticks)
end

local function add_sort_button(cell, column, active, ascending)
    local marker = active and (ascending and " \xE2\x96\xB2" or " \xE2\x96\xBC") or ""
    local button = cell.add{
        type    = "button",
        caption = {"", column.caption, marker},
        tags    = {mts_cleanup_sort = column.sort},
    }
    -- Styled inline rather than via a prototype: a data-stage style would
    -- force a full game restart for a header tweak.
    button.style.font          = "default-bold"
    button.style.height        = 24
    button.style.minimal_width = 40
    button.style.padding       = 0
end

local function add_icon_sort_button(cell, column, item, active, ascending)
    local flow = cell.add{type = "flow", direction = "horizontal"}
    flow.style.vertical_align = "center"
    local button = flow.add{
        type    = "sprite-button",
        sprite  = "item/" .. item,
        toggled = active,
        tooltip = {"mts-cleanup.col-marker-tip", prototypes.item[item].localised_name},
        tags    = {mts_cleanup_sort = column.sort},
    }
    button.style.size    = 28
    button.style.padding = 2
    if active then
        flow.add{type = "label", caption = ascending and "\xE2\x96\xB2" or "\xE2\x96\xBC"}
    end
end

local function add_header(tbl, player)
    local sort = state.sort(player)
    for _, column in ipairs(COLUMNS) do
        local active = column.sort ~= nil and sort.key == column.sort
        local item   = column.icon and column.icon()
        if item and prototypes.item[item] then
            add_icon_sort_button(tbl, column, item, active, sort.ascending)
        elseif column.sort then
            add_sort_button(tbl, column, active, sort.ascending)
        else
            local label = tbl.add{type = "label", caption = column.caption}
            label.style.font = "default-bold"
        end
    end
end

--- One row. A team with anybody online is rendered unpickable rather than
--- merely unticked, so a select-all can never sweep an active team in.
local function add_row(tbl, player, row)
    local pickable = not row.connected and row.member_count > 0

    local box = tbl.add{
        type    = "checkbox",
        state   = pickable and state.is_selected(player, row.force_name) or false,
        enabled = pickable,
        tags    = {mts_cleanup_pick = row.force_name,
                   mts_cleanup_gen  = row.generation},
        tooltip = pickable and nil or {"mts-cleanup.tip-locked"},
    }
    box.style.horizontally_stretchable = false

    local verdict = tbl.add{type = "label", caption = VERDICT_LABEL[row.verdict]}
    verdict.style.font_color = VERDICT_COLOR[row.verdict] or helpers.WHITE

    tbl.add{type = "label", caption = tostring(row.slot)}

    -- Team name plus a map button that spectates the team, so a judgement
    -- call can be made by looking at the base rather than at a row of numbers.
    local team_cell = tbl.add{type = "flow", direction = "horizontal"}
    team_cell.style.vertical_align = "center"
    local team = team_cell.add{type = "label", caption = helpers.team_tag(row.force_name)}
    team.style.maximal_width = 150
    local ping = team_cell.add{
        type    = "sprite-button",
        sprite  = "utility/map",
        style   = "mini_button",
        tooltip = {"mts-cleanup.ping-tip"},
        tags    = {mts_cleanup_ping = row.force_name},
    }
    ping.style.left_margin = 4

    tbl.add{type = "label", caption = row.leader_name or "-"}
    tbl.add{type = "label", caption = tostring(row.member_count)}
    tbl.add{type = "label", caption = fmt_offline(row)}
    tbl.add{type = "label", caption = helpers.fmt_span(row.team_ticks or 0)}
    tbl.add{type = "label", caption = counts.fmt(row.tier1 or 0)}
    tbl.add{type = "label", caption = counts.fmt(row.tier2 or 0)}
    tbl.add{type = "label",
        caption = row.entities and counts.fmt(row.entities) or "-"}
end

function M.build(parent, player, rows)
    local tbl = parent.add{
        type = "table", name = "sb_cleanup_table",
        column_count = M.COLUMN_COUNT, draw_horizontal_lines = true,
    }
    tbl.style.horizontal_spacing = 8
    tbl.style.vertical_spacing   = 2

    add_header(tbl, player)
    for _, row in ipairs(rows) do add_row(tbl, player, row) end
    return tbl
end

return M
