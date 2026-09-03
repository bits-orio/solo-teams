-- gui/cleanup/rows.lua
-- The Cleanup table: sortable header plus one row per occupied team slot.

local helpers = require("scripts.helpers")
local counts  = require("gui.stats.counts")
local state   = require("gui.cleanup.state")

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

-- caption key, sort key (nil = not sortable)
local COLUMNS = {
    {"mts-cleanup.col-pick",     nil},
    {"mts-cleanup.col-verdict",  "verdict"},
    {"mts-cleanup.col-slot",     "slot"},
    {"mts-cleanup.col-team",     nil},
    {"mts-cleanup.col-leader",   nil},
    {"mts-cleanup.col-members",  nil},
    {"mts-cleanup.col-offline",  "offline"},
    {"mts-cleanup.col-playtime", "team_hours"},
    {"mts-cleanup.col-tier1",    "tier1"},
    {"mts-cleanup.col-tier2",    nil},
    {"mts-cleanup.col-entities", "entities"},
}

M.COLUMN_COUNT = #COLUMNS

local function fmt_offline(row)
    if row.connected then return {"mts-cleanup.offline-online"} end
    if not row.offline_ticks then return {"mts-cleanup.offline-never"} end
    return helpers.fmt_duration_coarse(row.offline_ticks)
end

local function add_header(tbl, player)
    local sort = state.sort(player)
    for _, column in ipairs(COLUMNS) do
        local caption, sort_key = column[1], column[2]
        if not sort_key then
            local label = tbl.add{type = "label", caption = {caption}}
            label.style.font = "default-bold"
        else
            local marker = (sort.key == sort_key)
                and (sort.ascending and " \xE2\x96\xB2" or " \xE2\x96\xBC") or ""
            local button = tbl.add{
                type    = "button",
                caption = {"", {caption}, marker},
                tags    = {mts_cleanup_sort = sort_key},
            }
            -- Styled inline rather than via a prototype: a data-stage style
            -- would force a full game restart for a header tweak.
            button.style.font          = "default-bold"
            button.style.height        = 24
            button.style.minimal_width = 40
            button.style.padding       = 0
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

    local team = tbl.add{type = "label", caption = helpers.team_tag(row.force_name)}
    team.style.maximal_width = 150

    tbl.add{type = "label", caption = row.leader_name or "-"}
    tbl.add{type = "label", caption = tostring(row.member_count)}
    tbl.add{type = "label", caption = fmt_offline(row)}
    tbl.add{type = "label",
        caption = helpers.fmt_duration_coarse(row.team_ticks or 0)}
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
