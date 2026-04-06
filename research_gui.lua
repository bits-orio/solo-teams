-- Solo Teams - research_gui.lua
-- Author: bits-orio
-- License: MIT
--
-- Research comparison panel.
--
-- OVERVIEW MODE (default)
--   One block per player force. Header shows player name (colored),
--   research count, play time, and expand/collapse button.
--   Collapsed (default): single row of tech icons.
--   Expanded: all icons flow in a table sized to the frame width.
--
--   Clicking a tech icon opens that technology in the tech tree.
--   Clicking the diff button on another player's header opens diff mode.
--
-- DIFF MODE  (click diff button on a player header)
--   Shows:
--     - Context line: who started earlier and by how much
--     - "You both have researched" - shared techs
--     - "<player> has, you don't" - ordered by their research timestamp
--     - "You have, <player> doesn't" - ordered by your research timestamp
--     - Infinite tech level differences (label rows)
--     - [Back] button returns to overview
--
--   Pressing Escape in diff mode returns to overview.
--
-- Storage used (read-only here; written by control.lua):
--   storage.player_clock_start[player_index] = game.tick of first real spawn
--   storage.tech_research_ticks[force_name][tech_name] = game.tick researched

local nav = require("nav")

local M = {}

-- ---------------------------------------------------------------------------
-- Constants
-- ---------------------------------------------------------------------------

local NAV_BTN    = "sb_research_btn"
local FRAME_NAME = "sb_research_frame"
local FRAME_W    = 560
local FRAME_H    = 580

-- Number of icon columns for a single collapsed row (fits ~460px content area)
local COLLAPSED_COLS = 12

-- ---------------------------------------------------------------------------
-- Per-player GUI state
-- ---------------------------------------------------------------------------

-- storage.research_gui_expanded[viewer_index][owner_name] = true/false
-- storage.research_gui_diff_target[viewer_index] = owner_name or nil

local function get_expanded(viewer_index, owner)
    local t = (storage.research_gui_expanded or {})[viewer_index]
    return t and t[owner] or false
end

local function set_expanded(viewer_index, owner, state)
    storage.research_gui_expanded = storage.research_gui_expanded or {}
    storage.research_gui_expanded[viewer_index] = storage.research_gui_expanded[viewer_index] or {}
    storage.research_gui_expanded[viewer_index][owner] = state
end

local function get_diff_target(viewer_index)
    return (storage.research_gui_diff_target or {})[viewer_index]
end

local function set_diff_target(viewer_index, target)
    storage.research_gui_diff_target = storage.research_gui_diff_target or {}
    storage.research_gui_diff_target[viewer_index] = target
end

-- ---------------------------------------------------------------------------
-- Time formatting
-- ---------------------------------------------------------------------------

--- Convert a tick count to a human-readable duration string ("1h 23m 45s").
local function fmt_duration(ticks)
    local s = math.floor(ticks / 60)
    local h = math.floor(s / 3600); s = s % 3600
    local m = math.floor(s / 60);   s = s % 60
    if h > 0 then return string.format("%dh %02dm %02ds", h, m, s) end
    if m > 0 then return string.format("%dm %02ds", m, s) end
    return string.format("%ds", s)
end

--- Format play time since spawn (elapsed from clock_start to now).
local function fmt_play_time(clock_tick)
    if not clock_tick then return "not yet spawned" end
    local elapsed = game.tick - clock_tick
    if elapsed < 0 then elapsed = 0 end
    return fmt_duration(elapsed) .. " playing"
end

-- ---------------------------------------------------------------------------
-- Tech data helpers
-- ---------------------------------------------------------------------------

--- Return the research-timestamp table for a force (may be empty table).
local function force_ticks(force)
    return (storage.tech_research_ticks or {})[force.name] or {}
end

--- Return sorted list of researched techs for a force.
--- Each entry: { name, localised, tick, order }
--- Sorted by tick ascending; techs with no tick appended last by tech.order.
local function get_researched(force)
    local ticks   = force_ticks(force)
    local stamped = {}
    local unstamp = {}
    for name, tech in pairs(force.technologies) do
        if tech.researched then
            local t = ticks[name]
            if t then
                stamped[#stamped + 1] = {name = name, localised = tech.localised_name, tick = t, order = tech.order}
            else
                unstamp[#unstamp + 1] = {name = name, localised = tech.localised_name, tick = nil, order = tech.order}
            end
        end
    end
    table.sort(stamped,  function(a, b) return a.tick  < b.tick  end)
    table.sort(unstamp,  function(a, b) return a.order < b.order end)
    for _, v in ipairs(unstamp) do stamped[#stamped + 1] = v end
    return stamped
end

--- Build a tooltip string for a tech icon.
local function tech_tooltip(entry, clock_start)
    local name_line = entry.localised
    if not entry.tick then
        return {"", name_line, "\nResearched: (before tracking began)"}
    end
    if not clock_start then
        return {"", name_line, "\nResearched: tick " .. entry.tick}
    end
    local elapsed = entry.tick - clock_start
    if elapsed < 0 then elapsed = 0 end
    return {"", name_line, "\nResearched: " .. fmt_duration(elapsed) .. " after spawn"}
end

-- ---------------------------------------------------------------------------
-- Icon grid rendering (shared by overview and diff)
-- ---------------------------------------------------------------------------

--- Add tech icons to a table element. Each icon opens the tech tree on click.
local function add_tech_icons(grid, tech_list, clock_start)
    for _, entry in ipairs(tech_list) do
        grid.add{
            type    = "sprite-button",
            sprite  = "technology/" .. entry.name,
            tooltip = tech_tooltip(entry, clock_start),
            style   = "slot_button",
            tags    = {sb_research_open_tech = entry.name},
        }
    end
end

-- ---------------------------------------------------------------------------
-- Player block helpers (overview)
-- ---------------------------------------------------------------------------

--- Derive the owner name and force from the same logic as platforms_gui.
--- Returns an ordered list of { owner, force, color, online, clock_start }.
local function get_player_forces()
    local result = {}
    local seen   = {}
    for _, force in pairs(game.forces) do
        if force.name ~= "enemy" and force.name ~= "neutral"
           and force.name ~= "player" and force.name ~= "spectator" then
            local owner = force.name:match("^player%-(.+)$") or force.name
            if not seen[owner] then
                seen[owner] = true
                local color   = {1, 1, 1}
                local online  = false
                for _, p in pairs(force.players) do
                    if p.connected and (p.name == owner or force.name == "player") then
                        color  = p.chat_color
                        online = true
                        break
                    end
                end
                local player_index
                for _, p in pairs(game.players) do
                    if p.name == owner then player_index = p.index; break end
                end
                result[#result + 1] = {
                    owner        = owner,
                    force        = force,
                    color        = color,
                    online       = online,
                    clock_start  = player_index and (storage.player_clock_start or {})[player_index] or nil,
                    player_index = player_index,
                }
            end
        end
    end
    table.sort(result, function(a, b)
        local ca = a.clock_start or math.huge
        local cb = b.clock_start or math.huge
        if ca ~= cb then return ca < cb end
        return a.owner < b.owner
    end)
    return result
end

-- ---------------------------------------------------------------------------
-- Overview mode
-- ---------------------------------------------------------------------------

local function draw_overview(content_frame, viewer_force, viewer_clock, viewer_index)
    local forces = get_player_forces()

    if #forces == 0 then
        content_frame.add{type = "label", caption = "No players found."}
        return
    end

    local own_owner = viewer_force.name:match("^player%-(.+)$") or viewer_force.name

    for _, info in ipairs(forces) do
        local techs    = get_researched(info.force)
        local expanded = get_expanded(viewer_index, info.owner)

        -- Section frame per player
        local section = content_frame.add{
            type      = "frame",
            direction = "vertical",
            style     = "inside_shallow_frame",
        }
        section.style.horizontally_stretchable = true
        section.style.margin  = 4
        section.style.padding = 6

        -- Header row: bullet + name + count + play time + diff btn + expand btn
        local hdr = section.add{type = "flow", direction = "horizontal"}
        hdr.style.vertical_align = "center"

        -- Bullet
        local bullet = hdr.add{type = "label", caption = "\xE2\x97\x8F"}
        bullet.style.font_color   = info.online and info.color or {0.45, 0.45, 0.45}
        bullet.style.right_margin = 4

        -- Name
        local name_lbl = hdr.add{type = "label", caption = info.owner}
        name_lbl.style.font       = "default-bold"
        name_lbl.style.font_color = info.online and info.color or {0.65, 0.65, 0.65}
        if not info.online then
            local off = hdr.add{type = "label", caption = " (offline)"}
            off.style.font       = "default-small"
            off.style.font_color = {0.45, 0.45, 0.45}
        end

        -- Research count
        local count_lbl = hdr.add{type = "label", caption = "  [" .. #techs .. "]"}
        count_lbl.style.font       = "default-small"
        count_lbl.style.font_color = {0.7, 0.7, 0.7}

        -- Spacer
        local spacer = hdr.add{type = "empty-widget"}
        spacer.style.horizontally_stretchable = true

        -- Play time
        local start_lbl = hdr.add{type = "label", caption = fmt_play_time(info.clock_start)}
        start_lbl.style.font       = "default-small"
        start_lbl.style.font_color = {0.6, 0.8, 0.6}

        -- Diff button (for other players)
        if info.owner ~= own_owner then
            local diff_btn = hdr.add{
                type    = "sprite-button",
                sprite  = "utility/search_icon",
                style   = "mini_button",
                tooltip = "Compare: you vs " .. info.owner,
                tags    = {sb_research_diff_target = info.owner},
            }
            diff_btn.style.left_margin = 4
        end

        -- Expand/collapse button (double chevron: » down = expand, « up = collapse)
        if #techs > COLLAPSED_COLS then
            local toggle_btn = hdr.add{
                type    = "button",
                caption = expanded and "\xE2\x96\xB2\xE2\x96\xB2" or "\xE2\x96\xBC\xE2\x96\xBC",
                style   = "tool_button",
                tooltip = expanded and "Collapse" or "Expand all " .. #techs .. " technologies",
                tags    = {sb_research_expand_toggle = info.owner},
            }
            toggle_btn.style.width       = 28
            toggle_btn.style.height      = 28
            toggle_btn.style.left_margin = 4
            toggle_btn.style.font        = "default-bold"
        end

        -- Separator
        section.add{type = "line"}.style.top_margin = 2

        -- Tech icon grid
        if #techs == 0 then
            local none = section.add{type = "label", caption = "(no research yet)"}
            none.style.font_color = {0.5, 0.5, 0.5}
            none.style.top_margin = 2
        else
            local cols = COLLAPSED_COLS
            local display_techs = techs
            if not expanded and #techs > COLLAPSED_COLS then
                display_techs = {}
                for i = 1, COLLAPSED_COLS do
                    display_techs[i] = techs[i]
                end
            end

            local grid = section.add{type = "table", column_count = cols}
            grid.style.horizontal_spacing = 0
            grid.style.vertical_spacing   = 0
            grid.style.top_margin         = 2

            add_tech_icons(grid, display_techs, info.clock_start)
        end
    end
end

-- ---------------------------------------------------------------------------
-- Diff mode
-- ---------------------------------------------------------------------------

local function draw_diff(content_frame, viewer_force, viewer_clock, target_owner)
    -- Resolve target force
    local target_force_name = "player-" .. target_owner
    local target_force = game.forces[target_force_name]
    if not target_force then
        content_frame.add{type = "label", caption = "Player '" .. target_owner .. "' not found."}
        return
    end

    -- Target clock start
    local target_clock
    for _, p in pairs(game.players) do
        if p.name == target_owner then
            target_clock = (storage.player_clock_start or {})[p.index]
            break
        end
    end

    -- Back button
    local back_btn = content_frame.add{
        type    = "button",
        name    = "sb_research_back",
        caption = "< Back",
        style   = "back_button",
    }
    back_btn.style.bottom_margin = 6

    -- Context: who started earlier
    local viewer_owner = viewer_force.name:match("^player%-(.+)$") or viewer_force.name
    if viewer_clock and target_clock then
        local diff_ticks = math.abs(viewer_clock - target_clock)
        local context
        if viewer_clock < target_clock then
            context = "You started " .. fmt_duration(diff_ticks) .. " earlier than " .. target_owner
        elseif target_clock < viewer_clock then
            context = target_owner .. " started " .. fmt_duration(diff_ticks) .. " earlier than you"
        else
            context = "You both started at the same time"
        end
        local ctx_lbl = content_frame.add{type = "label", caption = context}
        ctx_lbl.style.font         = "default-bold"
        ctx_lbl.style.font_color   = {0.7, 0.9, 0.7}
        ctx_lbl.style.bottom_margin = 8
    end

    -- Compute diff sets
    local viewer_ticks = force_ticks(viewer_force)
    local target_ticks = force_ticks(target_force)

    -- both_have: researched by both
    local both_have = {}
    -- they_have: researched by target but NOT by viewer
    local they_have = {}
    -- you_have: researched by viewer but NOT by target
    local you_have  = {}

    for name, tech in pairs(target_force.technologies) do
        if tech.researched then
            if viewer_force.technologies[name] and viewer_force.technologies[name].researched then
                both_have[#both_have + 1] = {
                    name      = name,
                    localised = tech.localised_name,
                    tick      = target_ticks[name],
                    order     = tech.order,
                }
            else
                they_have[#they_have + 1] = {
                    name      = name,
                    localised = tech.localised_name,
                    tick      = target_ticks[name],
                    order     = tech.order,
                }
            end
        end
    end

    for name, tech in pairs(viewer_force.technologies) do
        if tech.researched and not (target_force.technologies[name] and target_force.technologies[name].researched) then
            you_have[#you_have + 1] = {
                name      = name,
                localised = tech.localised_name,
                tick      = viewer_ticks[name],
                order     = tech.order,
            }
        end
    end

    -- Sort each set by timestamp (then tech.order for unstamped)
    local function sort_diff(list)
        local stamped, unstamped = {}, {}
        for _, e in ipairs(list) do
            if e.tick then stamped[#stamped+1] = e else unstamped[#unstamped+1] = e end
        end
        table.sort(stamped,   function(a, b) return a.tick  < b.tick  end)
        table.sort(unstamped, function(a, b) return a.order < b.order end)
        for _, v in ipairs(unstamped) do stamped[#stamped+1] = v end
        return stamped
    end
    both_have = sort_diff(both_have)
    they_have = sort_diff(they_have)
    you_have  = sort_diff(you_have)

    local cols = COLLAPSED_COLS

    local function diff_section(title, list, clock_for_tooltip)
        local hdr = content_frame.add{type = "label", caption = title .. "  (" .. #list .. ")"}
        hdr.style.font          = "default-bold"
        hdr.style.top_margin    = 6
        hdr.style.bottom_margin = 2

        if #list == 0 then
            local none = content_frame.add{type = "label", caption = "(none)"}
            none.style.font_color = {0.5, 0.5, 0.5}
        else
            local grid = content_frame.add{type = "table", column_count = cols}
            grid.style.horizontal_spacing = 0
            grid.style.vertical_spacing   = 0
            add_tech_icons(grid, list, clock_for_tooltip)
        end
    end

    -- Use viewer's clock for shared techs tooltip (arbitrary choice; both valid)
    diff_section("You both have researched", both_have, viewer_clock)
    diff_section(target_owner .. " has, you don't", they_have, target_clock)
    diff_section("You have, " .. target_owner .. " doesn't", you_have, viewer_clock)

    -- Infinite tech level differences
    local inf_diffs = {}
    for name, v_tech in pairs(viewer_force.technologies) do
        local t_tech = target_force.technologies[name]
        if v_tech.researched and t_tech and t_tech.researched then
            local vl = (v_tech.level  or 1)
            local tl = (t_tech.level  or 1)
            if vl ~= tl then
                inf_diffs[#inf_diffs + 1] = {
                    name   = name,
                    v_lvl  = vl,
                    t_lvl  = tl,
                    loc    = v_tech.localised_name,
                }
            end
        end
    end

    if #inf_diffs > 0 then
        table.sort(inf_diffs, function(a, b)
            return tostring(a.name) < tostring(b.name)
        end)
        local hdr2 = content_frame.add{type = "label", caption = "Infinite tech level differences"}
        hdr2.style.font         = "default-bold"
        hdr2.style.top_margin   = 8
        hdr2.style.bottom_margin = 2

        local inf_tbl = content_frame.add{type = "table", column_count = 3}
        inf_tbl.style.horizontal_spacing = 12
        inf_tbl.style.vertical_spacing   = 2
        -- Header row
        local function hd(txt)
            local l = inf_tbl.add{type = "label", caption = txt}
            l.style.font = "default-bold"
        end
        hd("Technology"); hd("You"); hd(target_owner)
        for _, d in ipairs(inf_diffs) do
            inf_tbl.add{type = "label", caption = d.loc}
            local vl = inf_tbl.add{type = "label", caption = "Lv " .. d.v_lvl}
            local tl = inf_tbl.add{type = "label", caption = "Lv " .. d.t_lvl}
            if d.v_lvl > d.t_lvl then
                vl.style.font_color = {0.4, 1, 0.4}
            else
                tl.style.font_color = {0.4, 1, 0.4}
            end
        end
    end
end

-- ---------------------------------------------------------------------------
-- Frame construction
-- ---------------------------------------------------------------------------

local function build_frame(player, diff_target)
    local screen = player.gui.screen
    storage.research_gui_location = storage.research_gui_location or {}

    -- Reuse existing frame to preserve drag state
    local frame = screen[FRAME_NAME]
    if frame then
        storage.research_gui_location[player.index] = frame.location
        frame.clear()
    else
        frame = screen.add{
            type      = "frame",
            name      = FRAME_NAME,
            direction = "vertical",
        }
        if storage.research_gui_location[player.index] then
            frame.location = storage.research_gui_location[player.index]
        else
            frame.location = {x = 300, y = 100}
        end
    end

    frame.style.width  = FRAME_W
    frame.style.height = FRAME_H

    -- Persist diff target for Escape handling
    set_diff_target(player.index, diff_target)

    -- Title bar
    local title_bar = frame.add{type = "flow", direction = "horizontal"}
    title_bar.style.vertical_align = "center"
    title_bar.drag_target = frame

    title_bar.add{type = "label",
        caption = diff_target and ("Research: You vs " .. diff_target) or "Research",
        style   = "frame_title",
    }
    local title_spacer = title_bar.add{type = "empty-widget", style = "draggable_space_header"}
    title_spacer.style.horizontally_stretchable = true
    title_spacer.style.height = 24
    title_spacer.drag_target = frame

    title_bar.add{
        type    = "sprite-button",
        name    = "sb_research_close",
        sprite  = "utility/close",
        style   = "close_button",
        tooltip = "Close",
    }

    -- Scroll pane for content
    local scroll = frame.add{
        type = "scroll-pane",
        name = "sb_research_scroll",
        direction = "vertical",
        vertical_scroll_policy = "auto-and-reserve-space",
        horizontal_scroll_policy = "never",
    }
    scroll.style.horizontally_stretchable = true
    scroll.style.vertically_stretchable   = true

    local viewer_force = player.force
    local viewer_clock = (storage.player_clock_start or {})[player.index]

    if diff_target then
        draw_diff(scroll, viewer_force, viewer_clock, diff_target)
    else
        draw_overview(scroll, viewer_force, viewer_clock, player.index)
    end

    -- Allow Esc to navigate back from diff or close
    player.opened = frame
end

-- ---------------------------------------------------------------------------
-- Toggle
-- ---------------------------------------------------------------------------

function M.toggle(player)
    if player.gui.screen[FRAME_NAME] then
        storage.research_gui_location = storage.research_gui_location or {}
        storage.research_gui_location[player.index] = player.gui.screen[FRAME_NAME].location
        player.gui.screen[FRAME_NAME].destroy()
    else
        build_frame(player, nil)
    end
end

-- ---------------------------------------------------------------------------
-- Click handler
-- ---------------------------------------------------------------------------

function M.on_gui_click(event)
    local el = event.element
    if not (el and el.valid) then return false end

    -- Close button
    if el.name == "sb_research_close" then
        local player = event.player or game.get_player(event.player_index)
        if player then M.toggle(player) end
        return true
    end

    -- Back button (diff -> overview)
    if el.name == "sb_research_back" then
        local player = event.player or game.get_player(event.player_index)
        if player then build_frame(player, nil) end
        return true
    end

    -- Diff button (sb_research_diff_target tag)
    if el.tags and el.tags.sb_research_diff_target then
        local player = event.player or game.get_player(event.player_index)
        if player then build_frame(player, el.tags.sb_research_diff_target) end
        return true
    end

    -- Expand/collapse toggle
    if el.tags and el.tags.sb_research_expand_toggle then
        local player = event.player or game.get_player(event.player_index)
        if player then
            local owner = el.tags.sb_research_expand_toggle
            set_expanded(player.index, owner, not get_expanded(player.index, owner))
            build_frame(player, nil)
        end
        return true
    end

    -- Tech icon click -> open tech tree
    if el.tags and el.tags.sb_research_open_tech then
        local player = event.player or game.get_player(event.player_index)
        if player then
            player.open_technology_gui(el.tags.sb_research_open_tech)
        end
        return true
    end

    return false
end

-- ---------------------------------------------------------------------------
-- Escape handler (called from control.lua on_gui_closed)
-- ---------------------------------------------------------------------------

--- Handle Escape key on the research frame.
--- If in diff mode: go back to overview.
--- If any player section is expanded: collapse all.
--- Otherwise: close the frame.
--- Returns true if the event was consumed.
function M.on_gui_closed(event)
    local player = game.get_player(event.player_index)
    if not player then return false end
    local frame = player.gui.screen[FRAME_NAME]
    if not (frame and frame.valid) then return false end
    -- Check if Factorio is closing our frame
    if event.element ~= frame then return false end

    -- If in diff mode, go back to overview
    local diff_target = get_diff_target(player.index)
    if diff_target then
        build_frame(player, nil)
        return true
    end

    -- If any section is expanded, collapse all
    local had_expanded = false
    local expanded_map = (storage.research_gui_expanded or {})[player.index]
    if expanded_map then
        for owner, state in pairs(expanded_map) do
            if state then
                had_expanded = true
                expanded_map[owner] = false
            end
        end
    end
    if had_expanded then
        build_frame(player, nil)
        return true
    end

    -- Otherwise close the frame
    storage.research_gui_location[player.index] = frame.location
    frame.destroy()
    return true
end

-- ---------------------------------------------------------------------------
-- Refresh for open panels
-- ---------------------------------------------------------------------------

function M.update_all()
    for _, player in pairs(game.players) do
        if player.connected and player.gui.screen[FRAME_NAME] then
            local diff_target = get_diff_target(player.index)
            build_frame(player, diff_target)
        end
    end
end

-- ---------------------------------------------------------------------------
-- Nav bar registration
-- ---------------------------------------------------------------------------

function M.on_player_created(player)
    nav.add_top_button(player, {
        name    = NAV_BTN,
        sprite  = "item/lab",
        tooltip = "Research Comparison",
    })
    nav.on_click(NAV_BTN, function(e)
        M.toggle(e.player)
    end)
end

return M
