-- Solo Teams - vanilla_compat.lua
-- Author: bits-orio
-- License: MIT
--
-- Support for vanilla-style games (no Platformer mod) where each player
-- spawns on their own fresh copy of the Nauvis surface generated from the
-- same seed as the shared Nauvis, giving everyone an identical starting world.
--
-- Surface naming: "<force_name>-<planet>" e.g. "player-bob-nauvis"
-- Using force name (not player name/index) so the surface is identifiable
-- by its owning force, which supports multi-player teams in the future.
--
-- storage.player_surfaces[player_index] = {name = surface_name, planet = "nauvis"}

local helpers = require("helpers")

local vanilla = {}

--- Returns true when vanilla surface compat should be used.
--- Active whenever the Platformer mod is NOT loaded.
function vanilla.is_active()
    return script.active_mods["platformer"] == nil
end

--- Derive a human-readable display name for a player's surface record.
--- planet "nauvis" → "base on Nauvis"; works for any planet name.
function vanilla.planet_display_name(planet)
    return planet:sub(1, 1):upper() .. planet:sub(2)
end

--- Create a personal Nauvis surface for `player` using the same map-gen
--- settings as the shared "nauvis" surface (same seed, fresh world state).
--- The surface will generate terrain identically to the original Nauvis but
--- is completely independent — only this player's force can see it.
---
--- Teleport is deferred to the next tick via storage.pending_vanilla_tp so
--- it is safe to call from on_player_created before the character is ready.
function vanilla.setup_player_surface(player)
    local planet    = "nauvis"
    local surf_name = player.force.name .. "-" .. planet

    local surface = game.surfaces[surf_name]
    if not surface then
        local nauvis = game.surfaces[planet]
        local mgs    = nauvis and nauvis.map_gen_settings or {}
        surface      = game.create_surface(surf_name, mgs)
    end

    storage.player_surfaces = storage.player_surfaces or {}
    storage.player_surfaces[player.index] = {name = surf_name, planet = planet}

    storage.pending_vanilla_tp = storage.pending_vanilla_tp or {}
    storage.pending_vanilla_tp[player.index] = surface
end

--- Process queued vanilla surface teleports. Must be called from on_tick.
function vanilla.process_pending_teleports()
    if not storage.pending_vanilla_tp then return end
    if not next(storage.pending_vanilla_tp) then return end
    for player_index, surface in pairs(storage.pending_vanilla_tp) do
        local player = game.get_player(player_index)
        if player and player.valid and surface and surface.valid then
            player.teleport(helpers.ORIGIN, surface)
        end
    end
    storage.pending_vanilla_tp = {}
end

return vanilla
