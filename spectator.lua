-- Solo Teams - spectator.lua
-- Author: bits-orio
-- License: MIT
--
-- Spectator system: allows players to view other players' surfaces by
-- temporarily swapping to a dedicated spectator force that is friends
-- with all player forces (share_chart = true). A permission group
-- prevents any interaction beyond viewing and chatting.
--
-- Players whose target has friended them get a direct "friend view"
-- instead (no force swap needed — friendship grants chart access).

local admin_gui = require("admin_gui")

local spectator = {}

-- ─── Helpers ───────────────────────────────────────────────────────────

--- Announce spectation start/stop to all players (if notifications enabled).
local function announce_spectation(viewer, target_force, is_entering)
    if not admin_gui.flag("spectate_notifications_enabled") then return end

    local viewer_name = viewer.name
    local target_name = target_force.name:match("^player%-(.+)$") or target_force.name
    local action = is_entering and "is now spectating" or "stopped spectating"

    -- Find target color
    local tr, tg, tb = 1, 1, 1
    local target_players = target_force.connected_players
    if target_players[1] then
        tr = target_players[1].chat_color.r
        tg = target_players[1].chat_color.g
        tb = target_players[1].chat_color.b
    end

    local msg = string.format(
        "[color=%.2f,%.2f,%.2f]%s[/color] %s [color=%.2f,%.2f,%.2f]%s[/color]",
        viewer.chat_color.r, viewer.chat_color.g, viewer.chat_color.b,
        viewer_name, action, tr, tg, tb, target_name
    )

    for _, p in pairs(game.players) do
        if p.connected then p.print(msg) end
    end

    log("[solo-teams:spectator] announcement: " .. viewer_name .. " " .. action
        .. " " .. target_name)
end

-- ─── Setup ─────────────────────────────────────────────────────────────

--- Create the spectator force, permission group, and ensure all existing
--- player forces have the correct friendship/cease-fire/share_chart.
--- Called from on_init and on_configuration_changed.
function spectator.init()
    log("[solo-teams:spectator] init: starting")

    -- Create spectator force (idempotent)
    local spec = game.forces["spectator"]
    if not spec then
        spec = game.create_force("spectator")
        log("[solo-teams:spectator] init: created spectator force")
    end
    -- Spectator force must NOT share its chart — it accumulates everyone's
    -- chart data and sharing it back would leak all surfaces to all players.
    -- Chart flow is one-way: player forces → spectator force only.
    spec.share_chart = false

    -- Friend + cease-fire with all existing player forces (both directions)
    for _, force in pairs(game.forces) do
        if force.name:find("^player%-") then
            spec.set_friend(force, true)
            force.set_friend(spec, true)
            force.share_chart = true
        end
        if force.name ~= "enemy" and force ~= spec then
            spec.set_cease_fire(force, true)
            force.set_cease_fire(spec, true)
        end
    end

    -- Permission group (idempotent)
    local p = game.permissions.get_group("spectator")
    if not p then
        p = game.permissions.create_group("spectator")
    end
    -- Deny everything first
    for _, action_id in pairs(defines.input_action) do
        p.set_allows_action(action_id, false)
    end
    -- Re-enable only safe actions (matches Biter Battles spectator list)
    local allowed = {
        "admin_action",
        "change_active_item_group_for_filters",
        "change_active_quick_bar",
        "change_multiplayer_config",
        "clear_cursor",
        "edit_permission_group",
        "gui_checked_state_changed",
        "gui_click",
        "gui_confirmed",
        "gui_elem_changed",
        "gui_location_changed",
        "gui_selected_tab_changed",
        "gui_selection_state_changed",
        "gui_switch_state_changed",
        "gui_text_changed",
        "gui_value_changed",
        "map_editor_action",
        "open_character_gui",
        "quick_bar_set_selected_page",
        "quick_bar_set_slot",
        "remote_view_surface",
        "set_filter",
        "set_player_color",
        "spawn_item",
        "start_walking",
        "toggle_map_editor",
        "toggle_show_entity_info",
        "write_to_console",
    }
    for _, name in ipairs(allowed) do
        local action = defines.input_action[name]
        if action then
            p.set_allows_action(action, true)
        end
    end

    log("[solo-teams:spectator] init: complete, permission group configured")
end

--- Set up bidirectional friendship + cease-fire between a new player force
--- and the spectator force. Called from create_player_force after force creation.
--- Also hides all existing player surfaces from the new force.
function spectator.setup_force(new_force)
    new_force.share_chart = true
    local spec = game.forces["spectator"]
    if spec then
        new_force.set_friend(spec, true)
        spec.set_friend(new_force, true)
        spec.set_cease_fire(new_force, true)
        new_force.set_cease_fire(spec, true)
    end

    -- Hide all existing player-owned surfaces from the new force
    for _, surface in pairs(game.surfaces) do
        local owner = spectator.get_surface_owner(surface)
        if owner and owner ~= new_force.name then
            new_force.set_surface_hidden(surface, true)
        end
    end

    log("[solo-teams:spectator] setup_force: " .. new_force.name)
end

--- Ensure storage tables exist. Called from on_init, on_load, on_configuration_changed.
function spectator.init_storage()
    storage.spectator_real_force       = storage.spectator_real_force       or {}
    storage.spectating_target          = storage.spectating_target          or {}
    storage.spectator_saved_craft_mod  = storage.spectator_saved_craft_mod  or {}
    storage.friend_intents             = storage.friend_intents             or {}
end

-- ─── State Queries ─────────────────────────────────────────────────────

--- Returns true if the player is currently on the spectator force
--- with a saved real force.
function spectator.is_spectating(player)
    return storage.spectator_real_force[player.index] ~= nil
end

--- Returns the saved real force NAME (string) or nil.
function spectator.get_real_force(player)
    return storage.spectator_real_force[player.index]
end

--- Returns the player's effective force name — the real force if
--- spectating, otherwise the current force.
function spectator.get_effective_force(player)
    return storage.spectator_real_force[player.index] or player.force.name
end

--- Returns the target force NAME (string) or nil.
function spectator.get_target(player)
    return storage.spectating_target and storage.spectating_target[player.index]
end

--- Returns true if the viewer's force needs spectator mode to view
--- the target force. False means the target has friended the viewer
--- (direct view OK because target shares chart with viewer).
function spectator.needs_spectator_mode(viewer_force, target_force)
    return not target_force.get_friend(viewer_force)
end

--- Given a surface, return the force name that owns it, or nil.
function spectator.get_surface_owner(surface)
    if not surface or not surface.valid then return nil end

    -- Check space platforms: iterate all forces' platforms
    for _, force in pairs(game.forces) do
        if force.name:find("^player%-") then
            for _, plat in pairs(force.platforms) do
                if plat.surface and plat.surface.valid
                   and plat.surface.index == surface.index then
                    return force.name
                end
            end
        end
    end

    -- Check vanilla solo surfaces: pattern "<force_name>-<planet>"
    -- e.g. "player-bob-nauvis" → force_name = "player-bob"
    local force_name = surface.name:match("^(player%-.+)%-%w+$")
    if force_name and game.forces[force_name] then
        return force_name
    end

    return nil
end

-- ─── Core Operations ───────────────────────────────────────────────────

--- Begin spectating a target force's surface.
--- Precondition: caller has already checked needs_spectator_mode().
function spectator.enter(player, target_force, surface, position)
    log("[solo-teams:spectator] enter: " .. player.name
        .. " → " .. target_force.name
        .. " on " .. surface.name
        .. " at " .. serpent.line(position))

    -- 1. Save real force (if not already spectating)
    if not spectator.is_spectating(player) then
        storage.spectator_real_force[player.index] = player.force.name
    end

    -- 2. Set spectating target
    storage.spectating_target[player.index] = target_force.name

    -- 3. Swap to spectator force + permission group
    player.force = game.forces["spectator"]
    game.permissions.get_group("spectator").add_player(player)

    -- 4. Protect character and freeze crafting
    if player.character then
        player.character.destructible = false
        storage.spectator_saved_craft_mod[player.index] =
            player.character_crafting_speed_modifier
        player.character_crafting_speed_modifier = -1
    end
    player.show_on_map = false

    -- 5. Open remote view on target surface
    player.set_controller({
        type = defines.controllers.remote,
        surface = surface,
        position = position,
    })

    -- 6. Announce
    announce_spectation(player, target_force, true)

    log("[solo-teams:spectator] enter: done, force=" .. player.force.name)
end

--- Stop spectating. Restores real force and clears all spectator state.
--- Safe to call if player is not spectating (no-ops).
function spectator.exit(player)
    if not spectator.is_spectating(player) then return end

    log("[solo-teams:spectator] exit: " .. player.name)

    local target_fn = storage.spectating_target[player.index]

    -- 1. Restore real force + Default permission group
    local real_fn = storage.spectator_real_force[player.index]
    local real_force = game.forces[real_fn]
    if real_force then
        player.force = real_force
    end
    local default_group = game.permissions.get_group("Default")
    if default_group then default_group.add_player(player) end

    -- 2. Restore character and resume crafting
    if player.character then
        player.character.destructible = true
        local saved = storage.spectator_saved_craft_mod[player.index]
        player.character_crafting_speed_modifier = saved or 0
    end
    storage.spectator_saved_craft_mod[player.index] = nil
    player.show_on_map = true

    -- 3. Announce stop (before clearing storage so we have target info)
    if target_fn then
        local target_force = game.forces[target_fn]
        if target_force then
            announce_spectation(player, target_force, false)
        end
    end

    -- 4. Clear storage
    storage.spectator_real_force[player.index] = nil
    storage.spectating_target[player.index] = nil

    log("[solo-teams:spectator] exit: done, force=" .. player.force.name)
end

--- Switch spectation target without leaving spectator force.
--- Only valid when player is already spectating.
function spectator.switch_target(player, target_force, surface, position)
    log("[solo-teams:spectator] switch_target: " .. player.name
        .. " → " .. target_force.name
        .. " on " .. surface.name)

    storage.spectating_target[player.index] = target_force.name

    player.set_controller({
        type = defines.controllers.remote,
        surface = surface,
        position = position,
    })

    announce_spectation(player, target_force, true)
end

--- Open a friend-view: direct remote view without spectator force swap.
--- The viewer stays on their own force (friendship gives chart access).
function spectator.enter_friend_view(player, surface, position)
    log("[solo-teams:spectator] enter_friend_view: " .. player.name
        .. " on " .. surface.name)

    player.set_controller({
        type = defines.controllers.remote,
        surface = surface,
        position = position,
    })
end

-- ─── Event Handlers ────────────────────────────────────────────────────

--- Detects remote-view exit and calls exit().
--- Called from on_player_controller_changed.
function spectator.on_controller_changed(player, old_controller_type)
    -- Only act when LEAVING remote view (not entering or switching)
    if old_controller_type ~= defines.controllers.remote then return end
    if player.controller_type == defines.controllers.remote then return end

    if spectator.is_spectating(player) then
        log("[solo-teams:spectator] on_controller_changed: " .. player.name
            .. " exited remote view, restoring force")
        spectator.exit(player)
    end
end

--- Handle friendship changes that affect active spectators/friend-viewers.
--- Called from on_friend_toggle.
---
--- Direction: player_force just set_friend(target_force, is_friend).
--- Effect when is_friend=true:  target_force members can now see player_force's chart.
--- Effect when is_friend=false: target_force members lose player_force's chart access.
function spectator.on_friend_changed(player_force, target_force, is_friend)
    log("[solo-teams:spectator] on_friend_changed: "
        .. player_force.name .. (is_friend and " friended " or " unfriended ")
        .. target_force.name)

    if is_friend then
        -- Case A: player_force friended target_force.
        -- target_force members can now see player_force's chart.
        -- Upgrade: any spectator whose real force is target_force AND who is
        -- spectating player_force can switch from spectator to friend-view.
        for idx, spectated_fn in pairs(storage.spectating_target) do
            if spectated_fn == player_force.name then
                local real_fn = storage.spectator_real_force[idx]
                if real_fn == target_force.name then
                    local p = game.get_player(idx)
                    if p and p.connected then
                        -- Upgrade: restore real force, keep remote view open
                        p.force = game.forces[real_fn]
                        local default_group = game.permissions.get_group("Default")
                        if default_group then default_group.add_player(p) end
                        if p.character then
                            p.character.destructible = true
                            local saved = storage.spectator_saved_craft_mod[idx]
                            p.character_crafting_speed_modifier = saved or 0
                        end
                        storage.spectator_saved_craft_mod[idx] = nil
                        p.show_on_map = true
                        storage.spectator_real_force[idx] = nil
                        storage.spectating_target[idx] = nil
                        if p.crafting_queue_size > 0 then
                            p.print("[solo-teams] You are now viewing as a friend. Crafting resumed.")
                        else
                            p.print("[solo-teams] You are now viewing as a friend.")
                        end
                        log("[solo-teams:spectator] upgraded " .. p.name
                            .. " from spectator to friend-view")
                    end
                end
            end
        end
    else
        -- Case B: player_force unfriended target_force.
        -- target_force members lose chart access to player_force.
        -- Downgrade any target_force player who is friend-viewing player_force's
        -- surfaces into spectator mode (they keep viewing, just on spectator force).
        for _, p in pairs(target_force.connected_players) do
            if p.controller_type == defines.controllers.remote then
                local owner = spectator.get_surface_owner(p.surface)
                if owner == player_force.name then
                    log("[solo-teams:spectator] downgrading " .. p.name
                        .. " from friend-view to spectator (unfriended)")
                    local unfriender = player_force.name:match("^player%-(.+)$")
                        or player_force.name
                    -- Save real force and swap to spectator
                    storage.spectator_real_force[p.index] = p.force.name
                    storage.spectating_target[p.index] = player_force.name
                    p.force = game.forces["spectator"]
                    game.permissions.get_group("spectator").add_player(p)
                    if p.character then
                        p.character.destructible = false
                        storage.spectator_saved_craft_mod[p.index] =
                            p.character_crafting_speed_modifier
                        p.character_crafting_speed_modifier = -1
                    end
                    p.show_on_map = false
                    if p.crafting_queue_size > 0 then
                        p.print("[solo-teams] " .. unfriender
                            .. " unfriended you. Now spectating (crafting paused).")
                    else
                        p.print("[solo-teams] " .. unfriender
                            .. " unfriended you. Now spectating.")
                    end
                end
            end
        end
    end
end

--- Called from on_player_left_game.
--- Restore force immediately so buildings/turrets remain correctly assigned.
function spectator.on_player_left(player)
    if not spectator.is_spectating(player) then return end

    log("[solo-teams:spectator] on_player_left: restoring " .. player.name)

    local real_fn = storage.spectator_real_force[player.index]
    local real_force = game.forces[real_fn]
    if real_force then
        player.force = real_force
    end
    local default_group = game.permissions.get_group("Default")
    if default_group then default_group.add_player(player) end
    if player.character then
        player.character.destructible = true
        local saved = storage.spectator_saved_craft_mod[player.index]
        player.character_crafting_speed_modifier = saved or 0
    end
    storage.spectator_saved_craft_mod[player.index] = nil
    player.show_on_map = true

    storage.spectator_real_force[player.index] = nil
    storage.spectating_target[player.index] = nil
end

--- Called from on_player_joined_game.
--- Verify force is correct after reconnect. Defensive cleanup.
function spectator.on_player_joined(player)
    local real_fn = storage.spectator_real_force[player.index]
    if not real_fn then return end

    if player.force.name ~= "spectator" then
        -- Force was already restored (by on_player_left), clean up stale storage
        storage.spectator_real_force[player.index] = nil
        storage.spectating_target[player.index] = nil
        storage.spectator_saved_craft_mod[player.index] = nil
        log("[solo-teams:spectator] on_player_joined: cleaned stale storage for "
            .. player.name)
    else
        -- Still on spectator force after reconnect — restore
        local real_force = game.forces[real_fn]
        if real_force then
            player.force = real_force
        end
        local default_group = game.permissions.get_group("Default")
        if default_group then default_group.add_player(player) end
        if player.character then
            player.character.destructible = true
            local saved = storage.spectator_saved_craft_mod[player.index]
            player.character_crafting_speed_modifier = saved or 0
        end
        storage.spectator_saved_craft_mod[player.index] = nil
        player.show_on_map = true
        storage.spectator_real_force[player.index] = nil
        storage.spectating_target[player.index] = nil
        log("[solo-teams:spectator] on_player_joined: restored " .. player.name
            .. " from spectator force")
    end
end

-- ─── Chat ──────────────────────────────────────────────────────────────

--- Returns the chat context prefix for a player, or "".
function spectator.get_chat_prefix(player)
    -- Case 1: spectating (on spectator force)
    local target_fn = storage.spectating_target
        and storage.spectating_target[player.index]
    if target_fn then
        local target_name = target_fn:match("^player%-(.+)$") or target_fn
        return "[on " .. target_name .. "'s base][spectator] "
    end

    -- Case 2: friend-viewing (on own force but remote-viewing foreign surface)
    if player.controller_type == defines.controllers.remote then
        local owner = spectator.get_surface_owner(player.surface)
        if owner and owner ~= player.force.name then
            local owner_name = owner:match("^player%-(.+)$") or owner
            return "[on " .. owner_name .. "'s base][friend] "
        end
    end

    return ""
end

-- ─── Surface Visibility ────────────────────────────────────────────────

--- Update surface visibility between two forces based on friendship state.
--- When friends, each side can see the other's surfaces in the map sidebar.
--- When not friends, surfaces are hidden.
function spectator.update_surface_visibility(force_a, force_b, are_friends)
    for _, surface in pairs(game.surfaces) do
        local owner = spectator.get_surface_owner(surface)
        if owner == force_a.name then
            force_b.set_surface_hidden(surface, not are_friends)
        elseif owner == force_b.name then
            force_a.set_surface_hidden(surface, not are_friends)
        end
    end
end

--- Hide a newly created surface from all player forces except its owner
--- and the owner's mutual friends. Called from on_surface_created in control.lua.
function spectator.on_surface_created(surface)
    local owner_fn = spectator.get_surface_owner(surface)
    if not owner_fn then return end
    local owner_force = game.forces[owner_fn]
    if not owner_force then return end

    for _, force in pairs(game.forces) do
        if force.name:find("^player%-") and force.name ~= owner_fn then
            local are_friends = force.get_friend(owner_force)
                and owner_force.get_friend(force)
            force.set_surface_hidden(surface, not are_friends)
        end
    end
end

-- ─── Maintenance ───────────────────────────────────────────────────────

--- Periodic chart cleanup: clears spectator force chart data for
--- surfaces with no active spectators.
function spectator.cleanup_charts()
    local spec = game.forces["spectator"]
    if not spec then return end

    -- Build set of surfaces currently being spectated
    local active_surfaces = {}
    for _, target_fn in pairs(storage.spectating_target) do
        local force = game.forces[target_fn]
        if force then
            for _, plat in pairs(force.platforms) do
                if plat.surface and plat.surface.valid then
                    active_surfaces[plat.surface.index] = true
                end
            end
        end
    end

    -- Clear chart for non-active surfaces
    for _, surface in pairs(game.surfaces) do
        if not active_surfaces[surface.index] then
            local owner = spectator.get_surface_owner(surface)
            if owner and owner ~= "spectator" then
                spec.clear_chart(surface)
            end
        end
    end

    log("[solo-teams:spectator] cleanup_charts: cleared inactive surface charts")
end

return spectator
