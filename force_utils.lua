-- Multi-Team Support - force_utils.lua
-- Author: bits-orio
-- License: MIT
--
-- Force creation, tech/quality syncing, surface ownership checks, and
-- bounce-home logic. Extracted from control.lua for size reduction.

local helpers       = require("helpers")
local spectator     = require("spectator")
local surface_utils = require("surface_utils")

local force_utils = {}

--- Copy all researched technologies, quality unlocks, and space platform
--- unlock from one force to another.
local function copy_force_state(source, target)
    for name, tech in pairs(source.technologies) do
        if tech.researched then
            local t = target.technologies[name]
            if t then t.researched = true end
        end
    end
    for _, quality in pairs({"uncommon", "rare", "epic", "legendary"}) do
        pcall(function()
            if source.is_quality_unlocked(quality) then
                target.unlock_quality(quality)
            end
        end)
    end
    if source.is_space_platforms_unlocked() then
        pcall(target.unlock_space_platforms)
    end
end

--- Create a dedicated force for a player and set up diplomacy.
function force_utils.create_player_force(player)
    local force_name = "force-" .. player.name
    local ok, new_force = pcall(game.create_force, force_name)
    if not ok then
        player.print("Could not create separate force (64 force limit reached). Joining default team.")
        return
    end
    copy_force_state(game.forces.player, new_force)
    player.force = new_force

    for _, other_force in pairs(game.forces) do
        if other_force.name ~= "enemy" and other_force ~= new_force then
            new_force.set_cease_fire(other_force, true)
            other_force.set_cease_fire(new_force, true)
        end
    end

    spectator.setup_force(new_force)

    storage.team_leader = storage.team_leader or {}
    storage.team_leader[force_name] = player.index
end

--- Return true if the player is the team leader of their current force.
function force_utils.is_team_leader(player)
    storage.team_leader = storage.team_leader or {}
    return storage.team_leader[player.force.name] == player.index
end

--- Return the number of players on a force.
function force_utils.force_member_count(force)
    local n = 0
    for _ in pairs(force.players) do n = n + 1 end
    return n
end

--- Pick the best new leader from a force, preferring connected players.
local function pick_new_leader(force, exclude_index)
    local fallback = nil
    for _, member in pairs(force.players) do
        if member.valid and member.index ~= exclude_index then
            if member.connected then return member end
            if not fallback then fallback = member end
        end
    end
    return fallback
end

--- Delete all surfaces owned by a force and clean up related storage.
local function cleanup_force_surfaces(force_name)
    -- Delete surfaces matching "{force_name}-{planet}" pattern
    local deleted = {}
    for _, surface in pairs(game.surfaces) do
        if surface.valid and surface.name:find("^" .. force_name:gsub("%-", "%%-") .. "%-") then
            deleted[#deleted + 1] = surface.name
            game.delete_surface(surface)
        end
    end
    -- Also delete platforms owned by this force
    local force = game.forces[force_name]
    if force then
        for _, platform in pairs(force.platforms) do
            if platform.valid then
                deleted[#deleted + 1] = platform.name
                platform.destroy()
            end
        end
    end
    -- Clean up player_surfaces entries pointing to deleted surfaces
    storage.player_surfaces = storage.player_surfaces or {}
    for idx, ps in pairs(storage.player_surfaces) do
        for _, name in pairs(deleted) do
            if ps.name == name then
                storage.player_surfaces[idx] = nil
                break
            end
        end
    end
    return deleted
end

--- Remove a player from their current team, move them to their own force.
--- Handles three cases:
---   • Solo player (last member): cleans up force surfaces and creates a fresh force.
---   • Non-owner on a team: moves to their own "force-{name}" force.
---   • Force owner on a team: swaps into the new leader's empty force so the
---     remaining team keeps the base.
--- Handles leader promotion and broadcasts the change.
--- The caller is responsible for placing the player back in the landing pen.
function force_utils.remove_from_team(player)
    local old_force = player.force
    local old_force_name = old_force.name
    local member_count = force_utils.force_member_count(old_force)

    -- Track that this player has left this team (used for anti-abuse on rejoin)
    storage.left_teams = storage.left_teams or {}
    storage.left_teams[player.index] = storage.left_teams[player.index] or {}
    storage.left_teams[player.index][old_force_name] = true

    storage.team_leader = storage.team_leader or {}
    local own_force_name = "force-" .. player.name
    local is_owner = (own_force_name == old_force_name)

    if member_count <= 1 then
        -- Solo player leaving: clean up surfaces but keep the force.
        -- The force is reused when the player re-spawns from the pen.
        local display = helpers.display_name(old_force_name)
        local deleted = cleanup_force_surfaces(old_force_name)

        if #deleted > 0 then
            helpers.broadcast("[Team] " .. helpers.colored_name(player.name, player.chat_color) .. "'s base has been cleaned up." .. helpers.force_tag(old_force_name))
        end
    elseif is_owner then
        -- Owner is leaving. The remaining team keeps the force (and the base).
        -- Swap the owner into the new leader's empty force.
        local new_leader = pick_new_leader(old_force, player.index)
        if not new_leader then return false end

        local swap_force_name = "force-" .. new_leader.name
        local swap_force = game.forces[swap_force_name]
        if not swap_force then
            local ok, created = pcall(game.create_force, swap_force_name)
            if not ok then
                player.print("Could not create force for team transfer.")
                return false
            end
            swap_force = created
            copy_force_state(game.forces.player, swap_force)
            for _, other in pairs(game.forces) do
                if other.name ~= "enemy" and other ~= swap_force then
                    swap_force.set_cease_fire(other, true)
                    other.set_cease_fire(swap_force, true)
                end
            end
            spectator.setup_force(swap_force)
        end

        copy_force_state(old_force, swap_force)
        player.force = swap_force

        storage.team_leader[old_force_name] = new_leader.index
        storage.team_leader[swap_force_name] = player.index

        local cn_player = helpers.colored_name(player.name, player.chat_color)
        local cn_leader = helpers.colored_name(new_leader.name, new_leader.chat_color)
        local ft = helpers.force_tag(old_force_name)
        for _, member in pairs(old_force.players) do
            if member.connected then
                member.print(cn_player .. " has left the team." .. ft)
                member.print(cn_leader .. " is now the team leader." .. ft)
            end
        end
        helpers.broadcast("[Team] " .. cn_leader .. " now leads "
            .. cn_player .. "'s former team." .. ft)
    else
        -- Non-owner leaving: move to their own force.
        local own_force = game.forces[own_force_name]
        if not own_force then
            player.print("Could not find your force.")
            return false
        end

        copy_force_state(old_force, own_force)
        player.force = own_force
        storage.team_leader[own_force_name] = player.index

        if storage.team_leader[old_force_name] == player.index then
            local new_leader = pick_new_leader(old_force, player.index)
            if new_leader then
                storage.team_leader[old_force_name] = new_leader.index
                local cn_leader = helpers.colored_name(new_leader.name, new_leader.chat_color)
                local ft = helpers.force_tag(old_force_name)
                for _, member in pairs(old_force.players) do
                    if member.connected then
                        member.print(cn_leader .. " is now the team leader." .. ft)
                    end
                end
                helpers.broadcast("[Team] " .. cn_leader .. " now leads "
                    .. helpers.display_name(old_force_name) .. "'s team." .. ft)
            end
        end

        local cn_player = helpers.colored_name(player.name, player.chat_color)
        local ft = helpers.force_tag(old_force_name)
        for _, member in pairs(old_force.players) do
            if member.connected then
                member.print(cn_player .. " has left the team." .. ft)
            end
        end
    end

    return true
end

--- Periodically unlock "uncommon" quality for all player forces.
function force_utils.sync_quality_all_forces()
    for _, force in pairs(game.forces) do
        if force.name ~= "enemy" and force.name ~= "neutral" then
            pcall(function() force.unlock_quality("uncommon") end)
        end
    end
end

--- Get the player's real force (accounts for spectator mode).
local function effective_force(player)
    local real_fn = spectator.get_effective_force(player)
    return game.forces[real_fn]
end

--- Check whether the player is on another player's private surface.
--- Uses effective force (real force when spectating).
function force_utils.on_foreign_surface(player)
    local surface = player.surface
    if not surface then return false end
    local my_force = effective_force(player)
    if not my_force then return false end
    local my_force_name = my_force.name
    local owner_force = surface.name:match("^(force%-.+)%-%w+$")
    if owner_force and owner_force ~= my_force_name then return true end
    for _, force in pairs(game.forces) do
        if force ~= my_force and force.name ~= "enemy" and force.name ~= "neutral"
           and force.name ~= "spectator" then
            for _, plat in pairs(force.platforms) do
                if plat.surface and plat.surface.valid
                   and plat.surface.index == surface.index then
                    return true
                end
            end
        end
    end
    return false
end

--- Find the player's home surface (uses effective force for spectator compat).
function force_utils.get_home_surface(player)
    local force = effective_force(player)
    if not force then return nil end
    return surface_utils.get_home_surface(force, player.index)
end

--- Bounce a player back to their home surface if they're on a foreign one.
function force_utils.bounce_if_foreign(player)
    if not player or not player.connected then return end
    if player.controller_type == defines.controllers.remote then return end
    if not force_utils.on_foreign_surface(player) then return end
    local spawned = storage.spawned_players and storage.spawned_players[player.index]
    if spawned then
        local home = force_utils.get_home_surface(player)
        if not home then
            log("[multi-team-support] " .. player.name .. " on foreign surface "
                .. (player.surface and player.surface.name or "nil")
                .. " but no home surface found")
            return
        end
        log("[multi-team-support] bouncing " .. player.name .. " from "
            .. player.surface.name .. " → " .. home.name)
        player.teleport(helpers.ORIGIN, home)
    else
        local pen = game.surfaces["landing-pen"]
        if pen and pen.valid and player.surface.name ~= "landing-pen" then
            log("[multi-team-support] bouncing " .. player.name .. " from "
                .. player.surface.name .. " → landing-pen")
            player.teleport(helpers.ORIGIN, pen)
        end
    end
end

--- Mark a player's clock as started.
function force_utils.start_player_clock(player)
    storage.player_clock_start = storage.player_clock_start or {}
    if not storage.player_clock_start[player.index] then
        storage.player_clock_start[player.index] = game.tick
        log("[multi-team-support] clock started for " .. player.name .. " at tick " .. game.tick)
    end
end

return force_utils
