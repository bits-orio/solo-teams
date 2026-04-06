-- Solo Teams - platforms_gui.lua
-- Author: bits-orio
-- License: MIT
--
-- Draggable, collapsible GUI overlay that shows all players and their
-- platforms. Includes clickable GPS ping buttons and per-player friend
-- toggle checkboxes.

local nav = require("nav")
local spectator_mod = require("spectator")

local M = {}

--- Build a Factorio rich-text GPS tag for a platform's hub location.
--- Returns "" if the hub or surface is unavailable.
local function get_platform_gps(platform)
    local hub = platform.hub
    if hub and hub.valid and platform.surface then
        local pos = hub.position
        return string.format("[gps=%d,%d,%s]", pos.x, pos.y, platform.surface.name)
    end
    return ""
end

--- Build a Factorio rich-text GPS tag for a player's current position.
--- Returns "" if the player is offline or has no valid surface.
local function get_player_gps(player)
    if player and player.valid and player.connected and player.surface then
        local pos = player.position
        return string.format("[gps=%d,%d,%s]", pos.x, pos.y, player.surface.name)
    end
    return ""
end

--- Collect all platforms grouped by owner (player name).
--- Returns three tables:
---   owners:     { owner_name = { {name, location, gps}, ... }, ... }
---   order:      { owner_name, ... }  (insertion order)
---   owner_info: { owner_name = {gps, color, force_name}, ... }
--- Force names like "player-bob" are mapped to owner "bob".
--- The default "player" force keeps its name as-is.
function M.get_platforms_by_owner()
    local owners = {}
    local owner_info = {}
    local order = {}
    for _, force in pairs(game.forces) do
        -- Skip built-in forces: enemy/neutral are not player forces, and
        -- "player" is the default force used by Platformer for Base One —
        -- which we leave intact so Platformer doesn't crash, but hide here
        -- since solo players are always on their own "player-X" force.
        if force.name ~= "enemy" and force.name ~= "neutral"
           and force.name ~= "player" and force.name ~= "spectator" then
            local has_platforms = false
            for _ in pairs(force.platforms) do has_platforms = true; break end
            if has_platforms then
                -- Strip the "player-" prefix to get the display name
                local owner = force.name:match("^player%-(.+)$") or force.name
                owners[owner] = {}
                order[#order + 1] = owner
                owner_info[owner] = {gps = "", color = {1, 1, 1}, force_name = force.name, online = false}
                -- Find the player matching this owner for color/GPS.
                -- Can't rely solely on force.connected_players because
                -- a spectating player is temporarily on the spectator force.
                local owner_player = game.get_player(owner)
                if owner_player and owner_player.connected then
                    owner_info[owner].gps = get_player_gps(owner_player)
                    owner_info[owner].color = owner_player.chat_color
                    owner_info[owner].online = true
                end
                for _, platform in pairs(force.platforms) do
                    local location = platform.space_location and platform.space_location.name or "in transit"
                    local gps = get_platform_gps(platform)
                    local hub = platform.hub
                    local hub_pos = (hub and hub.valid) and hub.position or nil
                    owners[owner][#owners[owner] + 1] = {
                        name = platform.name,
                        location = location,
                        gps = gps,
                        surface_name = platform.surface and platform.surface.name or nil,
                        position = hub_pos and {x = hub_pos.x, y = hub_pos.y} or {x = 0, y = 0},
                    }
                end
            end
        end
    end

    -- Add vanilla (non-Platformer) surfaces from storage.player_surfaces.
    -- Each entry is {name = surface_name, planet = "nauvis"} keyed by player index.
    -- We only create an owner entry here if the player had no space platforms
    -- (avoiding duplicates when a player has both a vanilla base and platforms).
    -- owner key is p.name directly — no force-name derivation needed since we
    -- iterate actual players, and the solo force may not be assigned yet on join.
    local player_surfaces = storage.player_surfaces or {}
    for _, p in pairs(game.players) do
        local ps = player_surfaces[p.index]
        if ps then
            local surface = game.surfaces[ps.name]
            if surface and surface.valid then
                local owner = p.name
                if not owners[owner] then
                    owners[owner] = {}
                    order[#order + 1] = owner
                    owner_info[owner] = {
                        gps        = get_player_gps(p),
                        color      = p.chat_color,
                        force_name = spectator_mod.get_effective_force(p),
                        online     = p.connected,
                    }
                end
                local planet_disp = ps.planet:sub(1, 1):upper() .. ps.planet:sub(2)
                owners[owner][#owners[owner] + 1] = {
                    name         = p.name .. "'s base on " .. planet_disp,
                    location     = planet_disp,
                    gps          = string.format("[gps=0,0,%s]", ps.name),
                    surface_name = ps.name,
                    position     = {x = 0, y = 0},
                }
            end
        end
    end

    return owners, order, owner_info
end

--- Check whether a player's GUI is in collapsed state.
local function is_gui_collapsed(player)
    storage.gui_collapsed = storage.gui_collapsed or {}
    return storage.gui_collapsed[player.index] or false
end

--- Build (or rebuild) the platforms GUI for a single player.
--- The GUI is placed on player.gui.screen so it can be freely dragged.
--- Position is persisted in storage.gui_location across rebuilds.
function M.build_platforms_gui(player)
    local screen = player.gui.screen
    storage.gui_location = storage.gui_location or {}

    -- Reuse existing frame (preserves drag state); create only if absent
    local frame = screen.sb_platforms_frame
    if frame then
        storage.gui_location[player.index] = frame.location
        frame.clear()
    else
        frame = screen.add{
            type = "frame",
            name = "sb_platforms_frame",
            direction = "vertical"
        }
        if storage.gui_location[player.index] then
            frame.location = storage.gui_location[player.index]
        else
            frame.location = {x = 5, y = 400}
        end
    end

    local collapsed = is_gui_collapsed(player)

    -- Title bar: draggable, with "Platforms" label, spacer, and +/- toggle
    local title_bar = frame.add{type = "flow", name = "sb_title_bar", direction = "horizontal"}
    title_bar.style.vertical_align = "center"
    title_bar.style.horizontal_spacing = 8
    title_bar.drag_target = frame

    title_bar.add{type = "label", caption = "Players", style = "frame_title"}

    local spacer = title_bar.add{type = "empty-widget", style = "draggable_space_header"}
    spacer.style.horizontally_stretchable = true
    spacer.style.height = 24
    spacer.drag_target = frame

    title_bar.add{
        type = "sprite-button",
        name = "sb_platforms_toggle",
        caption = collapsed and "+" or "-",
        style = "close_button",
        tooltip = collapsed and "Show players" or "Hide players"
    }

    -- When collapsed, only the title bar is shown
    if collapsed then return end

    frame.style.maximal_height = 400
    frame.style.minimal_width = 256

    local scroll = frame.add{
        type = "scroll-pane",
        name = "sb_platforms_scroll",
        direction = "vertical"
    }
    scroll.style.maximal_height = 350

    -- Two-column table: col 1 = player/platform name + GPS, col 2 = friend toggle or location
    local tbl = scroll.add{
        type = "table",
        name = "sb_platforms_table",
        column_count = 2
    }
    tbl.style.horizontal_spacing = 12
    tbl.style.vertical_spacing = 2

    -- Use effective force (real force when spectating) for all comparisons
    local viewer_force_name = spectator_mod.get_effective_force(player)
    local viewer_force = game.forces[viewer_force_name]

    local owners, order, owner_info = M.get_platforms_by_owner()
    for _, owner in ipairs(order) do
        -- Player name row (col 1): bold, colored by chat_color; grey + "(offline)" when disconnected
        local owner_flow = tbl.add{type = "flow", direction = "horizontal"}
        local owner_label = owner_flow.add{type = "label", caption = owner}
        owner_label.style.font = "default-bold"
        if owner_info[owner].online then
            owner_label.style.font_color = owner_info[owner].color
        else
            owner_label.style.font_color = {0.65, 0.65, 0.65}
            local off_lbl = owner_flow.add{type = "label", caption = " (offline)"}
            off_lbl.style.font       = "default-small"
            off_lbl.style.font_color = {0.45, 0.45, 0.45}
        end

        -- Player name row (col 2): friend checkbox (only for other players)
        local target_force_name = owner_info[owner].force_name
        if target_force_name ~= viewer_force_name then
            local target_force = game.forces[target_force_name]
            -- Friendship checkbox states:
                -- State                     | Label            | Color  | Checked | Tooltip
                -- No intents                | "request friend" | blue   | no      | "Send friend request to X"
                -- I requested, they haven't | "request pending"| yellow | yes     | "Withdraw friend request to X"
                -- They requested, I haven't | "request pending"| yellow | no      | "Accept friend request from X"
                -- Mutual active             | "friends"        | green  | yes     | "Break friendship with X"
            if viewer_force and target_force then
                local intents = storage.friend_intents or {}
                local my_intent = intents[viewer_force_name]
                    and intents[viewer_force_name][target_force_name] or false
                local their_intent = intents[target_force_name]
                    and intents[target_force_name][viewer_force_name] or false
                local is_mutual = viewer_force.get_friend(target_force)
                local friend_flow = tbl.add{type = "flow", direction = "horizontal"}
                friend_flow.style.horizontal_align = "right"
                friend_flow.style.horizontally_stretchable = true
                local lbl_text, lbl_color, tip, checked
                if is_mutual then
                    -- Active mutual friendship
                    lbl_text  = "friends"
                    lbl_color = {0, 1, 0}
                    tip       = "Break friendship with " .. owner
                    checked   = true
                elseif my_intent then
                    -- I requested, waiting for them
                    lbl_text  = "request pending"
                    lbl_color = {1, 0.8, 0}
                    tip       = "Withdraw friend request to " .. owner
                    checked   = true
                elseif their_intent then
                    -- They requested, I haven't accepted yet
                    lbl_text  = "request pending"
                    lbl_color = {1, 0.8, 0}
                    tip       = "Accept friend request from " .. owner
                    checked   = false
                else
                    -- No intents from either side
                    lbl_text  = "request friend"
                    lbl_color = {0.4, 0.7, 1}
                    tip       = "Send friend request to " .. owner
                    checked   = false
                end
                local friend_label = friend_flow.add{type = "label", caption = lbl_text}
                friend_label.style.font = "default-small"
                friend_label.style.font_color = lbl_color
                friend_label.style.right_margin = 4
                friend_flow.add{
                    type = "checkbox",
                    state = checked,
                    tags = {sb_friend_toggle = true, sb_target_force = target_force_name},
                    tooltip = tip
                }
            else
                tbl.add{type = "label", caption = ""}
            end
        else
            tbl.add{type = "label", caption = ""}
        end

        -- Platform rows: indented name (small font) + spectate button | location
        local is_own = (target_force_name == viewer_force_name)
        local is_current_target = (target_force_name == spectator_mod.get_target(player))
        for _, info in ipairs(owners[owner]) do
            local plat_flow = tbl.add{type = "flow", direction = "horizontal"}
            local plat_label = plat_flow.add{type = "label", caption = "  " .. info.name}
            plat_label.style.font = "default-small"
            -- Spectate button: skip own surfaces and the currently spectated player
            if not is_own and not is_current_target and info.surface_name then
                plat_flow.add{
                    type = "sprite-button",
                    sprite = "utility/search_icon",
                    tags = {
                        sb_spectate = true,
                        sb_target_force = target_force_name,
                        sb_surface = info.surface_name,
                        sb_position = info.position,
                    },
                    style = "mini_button",
                    tooltip = "Spectate " .. owner .. "'s " .. info.name
                }
            end
            local loc_label = tbl.add{type = "label", caption = info.location}
            loc_label.style.font = "default-small"
        end
    end

    if #order == 0 then
        tbl.add{type = "label", caption = "No players yet."}
        tbl.add{type = "label", caption = ""}
    end

    -- Footer: return button, shown when the player is away from their own base.
    -- Uses effective force (real force when spectating) to find home surface.
    local eff_force = viewer_force
    local own_platform
    if eff_force then
        for _, p in pairs(eff_force.platforms) do own_platform = p; break end
    end
    local return_surface
    if own_platform and own_platform.surface then
        return_surface = own_platform.surface
    else
        local ps = storage.player_surfaces and storage.player_surfaces[player.index]
        local vs = ps and game.surfaces[ps.name]
        if vs and vs.valid then return_surface = vs end
    end
    if return_surface and player.surface.index ~= return_surface.index then
        local is_spec = spectator_mod.is_spectating(player)
        local footer = frame.add{type = "flow", direction = "horizontal"}
        footer.style.top_margin = 4
        footer.style.horizontal_align = "center"
        footer.style.horizontally_stretchable = true
        footer.add{
            type    = "button",
            name    = "sb_return_to_base",
            caption = is_spec
                and (player.crafting_queue_size > 0
                     and "Stop spectating (crafting paused)"
                     or  "Stop spectating")
                or "Return to my base",
            style   = "button",
            tooltip = is_spec and "Stop spectating and return to your base"
                                or "Teleport back to your space platform",
        }
    end
end

--- Rebuild the platforms GUI for all connected players, including those in the
--- landing pen (so they can inspect active players before deciding to spawn).
function M.update_all()
    for _, player in pairs(game.players) do
        if player.connected and player.gui.screen.sb_platforms_frame then
            M.build_platforms_gui(player)
        end
    end
end

--- Handle GUI click events for this mod's elements.
--- Returns true if the click was consumed, false otherwise.
function M.on_gui_click(event)
    local element = event.element
    if not element or not element.valid then return end

    -- Return-to-base button: exit spectation if needed, then teleport home.
    if element.name == "sb_return_to_base" then
        local player = game.get_player(event.player_index)
        if player then
            -- Exit spectation first (restores real force)
            if spectator_mod.is_spectating(player) then
                spectator_mod.exit(player)
            end
            local own_platform
            for _, p in pairs(player.force.platforms) do own_platform = p; break end
            if own_platform and own_platform.surface then
                player.teleport({ x = 0, y = 0 }, own_platform.surface)
            else
                local ps = storage.player_surfaces and storage.player_surfaces[player.index]
                local vs = ps and game.surfaces[ps.name]
                if vs and vs.valid then
                    player.teleport({ x = 0, y = 0 }, vs)
                end
            end
        end
        return true
    end

    -- Toggle collapse/expand
    if element.name == "sb_platforms_toggle" then
        local player = game.get_player(event.player_index)
        if player then
            storage.gui_collapsed = storage.gui_collapsed or {}
            storage.gui_collapsed[player.index] = not is_gui_collapsed(player)
            M.build_platforms_gui(player)
        end
        return true
    end

    -- Spectate button: enter/switch spectation or friend-view
    if element.tags and element.tags.sb_spectate then
        local player = game.get_player(event.player_index)
        if player then
            local target_force = game.forces[element.tags.sb_target_force]
            local surface = game.surfaces[element.tags.sb_surface]
            local position = element.tags.sb_position or {x = 0, y = 0}

            if target_force and surface then
                local viewer_force = game.forces[spectator_mod.get_effective_force(player)]
                if viewer_force and spectator_mod.needs_spectator_mode(viewer_force, target_force) then
                    if spectator_mod.is_spectating(player) then
                        spectator_mod.switch_target(player, target_force, surface, position)
                    else
                        spectator_mod.enter(player, target_force, surface, position)
                    end
                else
                    -- Friend view — direct remote view
                    spectator_mod.enter_friend_view(player, surface, position)
                end
            end
        end
        return true
    end

    return false
end

--- Handle friend checkbox toggle. Friendship is mutual: both sides must
--- agree before it activates. Either side can break it immediately.
--- Intents are stored per-force in storage.friend_intents.
function M.on_friend_toggle(event)
    local element = event.element
    if not element or not element.valid then return end
    if not (element.tags and element.tags.sb_friend_toggle) then return end

    local player = game.get_player(event.player_index)
    if not player then return end

    local target_force = game.forces[element.tags.sb_target_force]
    if not target_force then return end

    -- Use effective force (real force when spectating)
    local viewer_force_name = spectator_mod.get_effective_force(player)
    local viewer_force = game.forces[viewer_force_name]
    if not viewer_force then return end

    local target_force_name = target_force.name
    local target_name = target_force_name:match("^player%-(.+)$") or target_force_name

    -- Color helpers for announcements
    local vc = player.chat_color
    local tc = target_force.connected_players[1]
        and target_force.connected_players[1].chat_color
        or {r = 1, g = 1, b = 1}
    local viewer_tag = string.format("[color=%.2f,%.2f,%.2f]%s[/color]",
        vc.r, vc.g, vc.b, player.name)
    local target_tag = string.format("[color=%.2f,%.2f,%.2f]%s[/color]",
        tc.r, tc.g, tc.b, target_name)

    storage.friend_intents = storage.friend_intents or {}
    storage.friend_intents[viewer_force_name] = storage.friend_intents[viewer_force_name] or {}

    local new_state = element.state
    local msg

    if new_state then
        -- Record this side's intent
        storage.friend_intents[viewer_force_name][target_force_name] = true

        -- Check if reverse intent exists
        local reverse = storage.friend_intents[target_force_name]
            and storage.friend_intents[target_force_name][viewer_force_name]

        if reverse then
            -- Both sides agree → activate mutual friendship
            viewer_force.set_friend(target_force, true)
            target_force.set_friend(viewer_force, true)
            spectator_mod.on_friend_changed(viewer_force, target_force, true)
            spectator_mod.on_friend_changed(target_force, viewer_force, true)
            spectator_mod.update_surface_visibility(viewer_force, target_force, true)
            msg = viewer_tag .. " and " .. target_tag
                .. " are now [color=0,1,0]friends[/color]"
        else
            msg = viewer_tag .. " wants to friend " .. target_tag
                .. " [color=1,0.8,0](pending)[/color]"
        end
    else
        -- Remove this side's intent
        storage.friend_intents[viewer_force_name][target_force_name] = nil

        local was_mutual = viewer_force.get_friend(target_force)

        if was_mutual then
            -- Break both directions
            storage.friend_intents[target_force_name] = storage.friend_intents[target_force_name] or {}
            storage.friend_intents[target_force_name][viewer_force_name] = nil

            viewer_force.set_friend(target_force, false)
            target_force.set_friend(viewer_force, false)
            spectator_mod.on_friend_changed(viewer_force, target_force, false)
            spectator_mod.on_friend_changed(target_force, viewer_force, false)
            spectator_mod.update_surface_visibility(viewer_force, target_force, false)
            msg = viewer_tag .. " and " .. target_tag .. " are no longer friends"
        else
            msg = viewer_tag .. " withdrew friend request to " .. target_tag
        end
    end

    for _, p in pairs(game.players) do
        if p.connected then p.print(msg) end
    end

    -- Rebuild all players' GUIs: friendship changes may upgrade/bounce spectators,
    -- changing button text and visibility for affected players.
    M.update_all()
end

--- Toggle the platforms panel open/closed for a player.
function M.toggle(player)
    if player.gui.screen.sb_platforms_frame then
        storage.gui_location = storage.gui_location or {}
        storage.gui_location[player.index] = player.gui.screen.sb_platforms_frame.location
        player.gui.screen.sb_platforms_frame.destroy()
    else
        M.build_platforms_gui(player)
    end
end

--- Register the nav bar button for this player.
--- Idempotent — safe to call on reconnect.
function M.on_player_created(player)
    nav.add_top_button(player, {
        name    = "sb_platforms_btn",
        sprite  = "utility/gps_map_icon",
        tooltip = "Players & Platforms",
    })
    nav.on_click("sb_platforms_btn", function(e)
        M.toggle(e.player)
    end)
end

return M
