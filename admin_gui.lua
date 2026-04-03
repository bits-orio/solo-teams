-- Solo Teams - admin_gui.lua
-- Author: bits-orio
-- License: MIT
--
-- Admin control panel: collapsible window with tabs for runtime configuration.
-- Only shown to players with admin privileges (player.admin).
--
-- Tab: Feature Flags
--   landing_pen_enabled  — whether new players land in the pen or spawn directly

local M = {}

-- ---------------------------------------------------------------------------
-- Flag definitions
-- ---------------------------------------------------------------------------

-- Ordered list of all feature flags shown in the Feature Flags tab.
local FLAGS = {
    {
        key     = "landing_pen_enabled",
        label   = "Landing Pen",
        tooltip = "When enabled, new players wait in the Landing Pen before spawning into the game.",
    },
}

-- Defaults used on first init.
local FLAG_DEFAULTS = {
    landing_pen_enabled = true,
}

-- ---------------------------------------------------------------------------
-- Storage helpers
-- ---------------------------------------------------------------------------

--- Return the admin_flags table, initialising defaults for any missing keys.
function M.get_flags()
    storage.admin_flags = storage.admin_flags or {}
    for k, v in pairs(FLAG_DEFAULTS) do
        if storage.admin_flags[k] == nil then
            storage.admin_flags[k] = v
        end
    end
    return storage.admin_flags
end

--- Read a single flag value.
function M.flag(key)
    return M.get_flags()[key]
end

-- ---------------------------------------------------------------------------
-- GUI
-- ---------------------------------------------------------------------------

--- Returns true when this player should see the admin panel.
local function is_admin(player)
    return player.admin
end

local function is_collapsed(player)
    storage.admin_gui_collapsed = storage.admin_gui_collapsed or {}
    return storage.admin_gui_collapsed[player.index] or false
end

--- Build (or rebuild) the admin panel for one player.
--- No-ops if the player is not an admin.
function M.build_admin_gui(player)
    if not is_admin(player) then return end

    local screen = player.gui.screen
    storage.admin_gui_location = storage.admin_gui_location or {}

    -- Reuse existing frame (preserves drag state); create only if absent
    local frame = screen.sb_admin_frame
    if frame then
        storage.admin_gui_location[player.index] = frame.location
        frame.clear()
    else
        frame = screen.add{
            type      = "frame",
            name      = "sb_admin_frame",
            direction = "vertical",
        }
        if storage.admin_gui_location[player.index] then
            frame.location = storage.admin_gui_location[player.index]
        else
            frame.location = {x = 270, y = 200}
        end
    end

    local collapsed = is_collapsed(player)

    -- Title bar
    local title_bar = frame.add{type = "flow", direction = "horizontal"}
    title_bar.style.vertical_align = "center"
    title_bar.drag_target = frame
    title_bar.add{type = "label", caption = "Admin", style = "frame_title"}
    local spacer = title_bar.add{type = "empty-widget", style = "draggable_space_header"}
    spacer.style.horizontally_stretchable = true
    spacer.style.height = 24
    spacer.drag_target = frame
    title_bar.add{
        type    = "sprite-button",
        name    = "sb_admin_toggle",
        caption = collapsed and "+" or "-",
        style   = "close_button",
        tooltip = collapsed and "Expand" or "Collapse",
    }

    if collapsed then return end

    frame.style.minimal_width = 280

    -- Tabbed pane
    local tabs = frame.add{type = "tabbed-pane", name = "sb_admin_tabs"}
    tabs.style.top_margin = 4

    -- Tab: Feature Flags
    local flags_tab     = tabs.add{type = "tab",  caption = "Feature Flags"}
    local flags_content = tabs.add{type = "flow", direction = "vertical", name = "sb_admin_flags_content"}
    flags_content.style.left_padding   = 8
    flags_content.style.right_padding  = 8
    flags_content.style.top_padding    = 8
    flags_content.style.bottom_padding = 8
    flags_content.style.vertical_spacing = 6
    tabs.add_tab(flags_tab, flags_content)
    tabs.selected_tab_index = 1

    local flags = M.get_flags()
    for _, def in ipairs(FLAGS) do
        local row = flags_content.add{type = "flow", direction = "horizontal"}
        row.style.vertical_align    = "center"
        row.style.horizontal_spacing = 8
        row.add{
            type    = "checkbox",
            state   = flags[def.key] == true,
            tags    = {sb_admin_flag = def.key},
            tooltip = def.tooltip,
        }
        local lbl = row.add{type = "label", caption = def.label, tooltip = def.tooltip}
        lbl.style.minimal_width = 160
    end
end

--- Ensure the admin panel exists for all connected admins; destroy it for non-admins.
--- Only creates the panel if it doesn't exist yet — periodic rebuilds are unnecessary
--- because flag changes already trigger their own rebuild via checkbox handlers.
function M.update_all()
    for _, player in pairs(game.players) do
        if player.connected then
            if is_admin(player) then
                if not player.gui.screen.sb_admin_frame then
                    M.build_admin_gui(player)
                end
            elseif player.gui.screen.sb_admin_frame then
                player.gui.screen.sb_admin_frame.destroy()
            end
        end
    end
end

--- Handle click events. Returns true if consumed.
function M.on_gui_click(event)
    local el = event.element
    if not el or not el.valid then return false end

    if el.name == "sb_admin_toggle" then
        local player = game.get_player(event.player_index)
        if player and is_admin(player) then
            storage.admin_gui_collapsed = storage.admin_gui_collapsed or {}
            storage.admin_gui_collapsed[player.index] = not is_collapsed(player)
            M.build_admin_gui(player)
        end
        return true
    end

    return false
end

--- Handle checkbox changes.
--- Returns the changed flag key (truthy = consumed) so the caller can apply
--- side effects, or false if the event was not an admin flag change.
function M.on_gui_checked_state_changed(event)
    local el = event.element
    if not el or not el.valid then return false end
    if not (el.tags and el.tags.sb_admin_flag) then return false end

    local player = game.get_player(event.player_index)
    if not (player and is_admin(player)) then return false end

    local key = el.tags.sb_admin_flag
    local flags = M.get_flags()
    flags[key] = el.state
    log("[solo-teams] admin flag changed by " .. player.name .. ": " .. key .. " = " .. tostring(el.state))

    -- Return the key so control.lua can apply immediate side effects.
    return key
end

--- Toggle the admin panel open/closed for a player.
function M.toggle(player)
    if not is_admin(player) then return end
    local frame = player.gui.screen.sb_admin_frame
    if frame then
        storage.admin_gui_location = storage.admin_gui_location or {}
        storage.admin_gui_location[player.index] = frame.location
        frame.destroy()
    else
        M.build_admin_gui(player)
    end
end

--- No nav bar button — the admin panel is shown automatically by the
--- 60-tick update_all cycle for the host player (index 1).  Adding a
--- button during on_player_created caused multiplayer desyncs because
--- player.admin is not synchronised at that point.
function M.on_player_created(_player)
    -- intentionally empty
end

return M
