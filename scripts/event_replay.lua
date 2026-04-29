-- Multi-Team Support - scripts/event_replay.lua
-- Author: bits-orio
-- License: MIT
--
-- Retroactive compatibility for third-party mods. When a player adds a
-- new mod (chunk-gen, surface-decorator, force-aware) to an existing
-- save, that mod's on_init runs but it never sees MTS's pre-existing
-- team surfaces. Replay re-fires the relevant Factorio events so the
-- new mod gets a chance to set up.
--
-- IMPORTANT: replay only helps mods whose handlers do not filter the
-- surface by hardcoded name. A mod whose `on_surface_created` checks
-- `surface.name == "nauvis"` will reject every team surface no matter
-- how the event is delivered — those mods need either an mts-v1
-- subscription or a `surface.planet.name` upstream fix. See
-- docs/COMPAT.md for the full strategy.
--
-- This module is intentionally NOT auto-fired on every configuration
-- change. Replay can double-apply non-idempotent setup, so it's gated
-- behind the /mts-replay admin command — admins choose when to use it,
-- typically right after adding a new mod.

local surface_utils = require("scripts.surface_utils")

local event_replay = {}

local CHUNK_SIZE = 32

-- ─── Helpers ──────────────────────────────────────────────────────────

local function is_team_surface(surface)
    return surface and surface.valid and surface_utils.get_owner(surface) ~= nil
end

-- ─── Surface lifecycle replay ─────────────────────────────────────────

--- Re-fire on_surface_created for a single team surface. Cheap (one
--- event). Helps third-party mods that did per-surface setup in their
--- on_surface_created handler.
---
--- We deliberately do NOT raise mts-v1's on_team_surface_created here:
--- control.lua's own on_surface_created handler raises it as part of
--- its normal flow, so a single raise here triggers both events for
--- subscribers.
function event_replay.replay_lifecycle(surface)
    if not is_team_surface(surface) then return end

    script.raise_event(defines.events.on_surface_created, {
        surface_index = surface.index,
    })
end

-- ─── Chunk replay ─────────────────────────────────────────────────────

--- Re-fire on_chunk_generated for every chunk on a team surface.
--- Heavy: O(chunks) events per surface. Use when a chunk-gen mod was
--- just installed and you want it applied to existing chunks.
function event_replay.replay_chunks(surface)
    if not is_team_surface(surface) then return 0 end
    local count = 0
    for chunk in surface.get_chunks() do
        local x = chunk.x * CHUNK_SIZE
        local y = chunk.y * CHUNK_SIZE
        script.raise_event(defines.events.on_chunk_generated, {
            area     = {{x, y}, {x + CHUNK_SIZE, y + CHUNK_SIZE}},
            position = {x = chunk.x, y = chunk.y},
            surface  = surface,
        })
        count = count + 1
    end
    return count
end

-- ─── Bulk replay ──────────────────────────────────────────────────────

--- Replay across every team surface in the game.
--- opts.chunks: also replay on_chunk_generated per chunk (heavier).
--- Returns {surfaces = N, chunks = N}.
function event_replay.replay_all(opts)
    opts = opts or {}
    local stats = {surfaces = 0, chunks = 0}
    for _, surface in pairs(game.surfaces) do
        if is_team_surface(surface) then
            event_replay.replay_lifecycle(surface)
            stats.surfaces = stats.surfaces + 1
            if opts.chunks then
                stats.chunks = stats.chunks + event_replay.replay_chunks(surface)
            end
        end
    end
    return stats
end

return event_replay
