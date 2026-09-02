-- gui/cleanup.lua
-- Facade for the admin Cleanup panel: event routing, the nav badge, and the
-- command that opens it. Frame construction lives in gui/cleanup/panel.lua.

local panel  = require("gui.cleanup.panel")
local state  = require("gui.cleanup.state")
local config = require("scripts.reaper.config")
local markers = require("scripts.reaper.markers")
local reaper = require("scripts.reaper")
local nav    = require("gui.nav")

local M = {}

M.FRAME_NAME = panel.FRAME_NAME

-- The admin panel's top-bar button, addressed by name rather than by requiring
-- gui.admin: that module sits inside the admin_flags require chain and pulling
-- it in here would close a load-time cycle.
local ADMIN_NAV_BUTTON = "sb_admin_btn"

M.toggle          = panel.toggle
M.refresh         = panel.refresh
M.rescan          = panel.rescan
M.refresh_all     = panel.refresh_all
M.request_disband = panel.request_disband

--- Show how many teams the armed rule would take, on the admin's existing
--- top-bar button. Zero clears the badge rather than showing a nought.
function M.refresh_badge(player)
    if not (player and player.valid and player.connected and player.admin) then return end
    local button = player.gui.top[ADMIN_NAV_BUTTON]
    if not (button and button.valid) then return end
    local count = reaper.badge_count()
    button.number = count > 0 and count or nil
end

function M.refresh_badges_all()
    for _, player in pairs(game.connected_players) do M.refresh_badge(player) end
end

-- ─── Events ────────────────────────────────────────────────────────────

local function admin_from(event)
    local player = game.get_player(event.player_index)
    if player and player.admin then return player end
    return nil
end

--- Returns true when the click was consumed.
function M.on_gui_click(event)
    local element = event.element
    if not (element and element.valid) then return false end

    if element.name == "sb_cleanup_close" then
        local player = game.get_player(event.player_index)
        if player then panel.toggle(player) end
        return true
    end

    local player = admin_from(event)
    if not player then return false end

    if element.name == "sb_cleanup_select_suggested" then
        state.preselect(player, panel.current_rows())
        panel.refresh(player)
        return true
    end

    if element.name == "sb_cleanup_refresh" then
        panel.rescan(player)
        return true
    end

    if element.name == "sb_cleanup_clear" then
        state.clear(player)
        panel.refresh(player)
        return true
    end

    if element.name == "sb_cleanup_disband" then
        panel.request_disband(player)
        return true
    end

    if element.tags and element.tags.mts_cleanup_sort then
        state.set_sort(player, element.tags.mts_cleanup_sort)
        panel.refresh(player)
        return true
    end

    return false
end

function M.on_gui_checked_state_changed(event)
    local element = event.element
    if not (element and element.valid) then return false end
    local player = admin_from(event)
    if not player then return false end

    if element.tags and element.tags.mts_cleanup_pick then
        state.set(player, element.tags.mts_cleanup_pick,
            element.state and element.tags.mts_cleanup_gen or nil)
        panel.refresh(player)
        return true
    end

    if element.name == "sb_cleanup_arm" then
        if element.state and not markers.ready() then
            player.print(markers.blocked_reason())
            panel.refresh(player)
            return true
        end
        config.set_flag("auto_disband_enabled", element.state)
        log("[multi-team-support:reaper] auto disband "
            .. (element.state and "ARMED" or "disarmed") .. " by " .. player.name)
        panel.refresh(player)
        return true
    end

    return false
end

function M.on_gui_elem_changed(event)
    local element = event.element
    if not (element and element.valid) then return false end
    if not (element.tags and element.tags.mts_cleanup_marker) then return false end
    local player = admin_from(event)
    if not player then return false end

    markers.set_override(element.tags.mts_cleanup_marker, element.elem_value)
    panel.refresh(player)
    return true
end

function M.on_gui_confirmed(event)
    local element = event.element
    if not (element and element.valid) then return false end
    if element.name ~= "sb_cleanup_offline_days" then return false end
    local player = admin_from(event)
    if not player then return false end

    -- An empty or unparsable field keeps the current window. Defaulting to 1
    -- would silently move the setting to its most aggressive value.
    local typed = tonumber(element.text)
    if not typed then panel.refresh(player); return true end
    local stored = config.set_number("offline_days", typed)
    if stored then player.print({"mts-reaper.set-done", "offline_days", tostring(stored)}) end
    panel.refresh(player)
    return true
end

-- The admin panel draws this button but cannot require this module (cycle via
-- gui.teams), so the handler is claimed by element name here.
nav.on_click("sb_admin_cleanup_btn", function(event) panel.toggle(event.player) end)

function M.register_command()
    commands.add_command("mts-cleanup", {"mts-cleanup.help"}, function(cmd)
        local player = cmd.player_index and game.get_player(cmd.player_index)
        if not player then game.print({"mts-cmd.player-only"}); return end
        if not player.admin then player.print({"mts-reaper.admin-only"}); return end
        panel.toggle(player)
    end)
end

return M
