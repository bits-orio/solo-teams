-- Solo Teams - force_utils.lua
-- Author: bits-orio
-- License: MIT
--
-- Force creation, tech/quality syncing, surface ownership checks, and
-- bounce-home logic. Extracted from control.lua for size reduction.

local helpers   = require("helpers")
local spectator = require("spectator")

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
    local force_name = "player-" .. player.name
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
end

--- Periodically unlock "uncommon" quality for all player forces.
function force_utils.sync_quality_all_forces()
    for _, force in pairs(game.forces) do
        if force.name ~= "enemy" and force.name ~= "neutral" then
            pcall(function() force.unlock_quality("uncommon") end)
        end
    end
end

--- Check whether the player is on another player's private surface.
function force_utils.on_foreign_surface(player)
    local surface = player.surface
    if not surface then return false end
    local owner_force = surface.name:match("^(player%-.+)%-%w+$")
    if owner_force and owner_force ~= player.force.name then return true end
    for _, force in pairs(game.forces) do
        if force ~= player.force and force.name ~= "enemy" and force.name ~= "neutral" then
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

--- Find the player's home surface: first space platform, then vanilla surface.
function force_utils.get_home_surface(player)
    for _, plat in pairs(player.force.platforms) do
        if plat.surface and plat.surface.valid then return plat.surface end
    end
    local ps = storage.player_surfaces and storage.player_surfaces[player.index]
    if ps then
        local s = game.surfaces[ps.name]
        if s and s.valid then return s end
    end
    return nil
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
            log("[solo-teams] " .. player.name .. " on foreign surface "
                .. (player.surface and player.surface.name or "nil")
                .. " but no home surface found")
            return
        end
        log("[solo-teams] bouncing " .. player.name .. " from "
            .. player.surface.name .. " → " .. home.name)
        player.teleport(helpers.ORIGIN, home)
    else
        local pen = game.surfaces["landing-pen"]
        if pen and pen.valid and player.surface.name ~= "landing-pen" then
            log("[solo-teams] bouncing " .. player.name .. " from "
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
        log("[solo-teams] clock started for " .. player.name .. " at tick " .. game.tick)
    end
end

return force_utils
