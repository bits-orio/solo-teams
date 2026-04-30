-- Multi-Team Support - compat/clone_mirror.lua
-- Author: bits-orio
-- License: MIT
--
-- Generic terrain compatibility for any third-party mod that decorates
-- the real "nauvis" surface via on_chunk_generated and filters by
-- hardcoded surface name. When a chunk is generated on a team-N-nauvis
-- (or mts-nauvis-N) surface, this module:
--
--   1. Ensures the same chunk has been generated on real nauvis. That
--      synchronously fires every third-party mod's on_chunk_generated
--      handler (dangOreus, VoidBlock, Alien Biomes' autoplace, etc.)
--      against the nauvis surface, where their filters DO accept it.
--   2. Mirrors the resulting tiles + entities + decoratives from
--      nauvis to the team surface via clone_area.
--
-- Net effect: whatever the mod stack puts on nauvis, every team
-- surface gets the same. Per-team variety is traded for "same map
-- across teams", which suits the head-to-head race format MTS targets.
--
-- This handler is mod-agnostic. Adding a new terrain decorator does
-- not require any per-mod compat code on the MTS side as long as the
-- mod's logic ends up writing to nauvis. Per-mod shims are only
-- needed for runtime gameplay rules that fire AFTER chunk generation
-- (e.g. dangOreus's on_built_entity, on_entity_died, on_nth_tick) and
-- those tend to be small and stable.
--
-- Cost model: marginal cost per team chunk approaches 1× as the team
-- count grows, because nauvis is generated once per chunk-area and
-- amortized across all teams. The first team to explore a chunk pays
-- ~2×; subsequent teams exploring the same chunk pay ~1×.

local clone_mirror = {}

local CHUNK_SIZE = 32

-- Surface name patterns that should mirror from nauvis. Add patterns
-- here if MTS adds more nauvis-equivalent surface naming schemes.
local TEAM_NAUVIS_PATTERNS = {
    "^team%-%d+%-nauvis$",   -- base 2.0 cloned surface
    "^mts%-nauvis%-%d+$",    -- Space Age per-team variant
}

local function is_team_nauvis(name)
    if not name then return false end
    for _, p in ipairs(TEAM_NAUVIS_PATTERNS) do
        if name:find(p) then return true end
    end
    return false
end

--- Hook from MTS's on_chunk_generated event. Cheap when the surface
--- isn't a team nauvis (early return). For team nauvis, drives nauvis
--- to generate the matching chunk and clones the result.
function clone_mirror.on_chunk_generated(event)
    local team_surface = event.surface
    if not (team_surface and team_surface.valid) then return end
    if not is_team_nauvis(team_surface.name) then return end

    local nauvis = game.surfaces["nauvis"]
    if not (nauvis and nauvis.valid) then return end

    local cx, cy = event.position.x, event.position.y
    -- Drive nauvis to generate the same chunk if it hasn't already.
    -- Every mod that listens to on_chunk_generated for nauvis runs
    -- synchronously inside force_generate_chunk_requests.
    if not nauvis.is_chunk_generated({cx, cy}) then
        nauvis.request_to_generate_chunks(
            {cx * CHUNK_SIZE + CHUNK_SIZE / 2, cy * CHUNK_SIZE + CHUNK_SIZE / 2}, 0)
        nauvis.force_generate_chunk_requests()
    end

    -- Mirror tiles + entities + decoratives. clone_area is synchronous
    -- and overwrites destination contents, so any vanilla worldgen that
    -- happened on the team surface a moment ago is replaced by nauvis's
    -- (post-mod-decoration) state.
    nauvis.clone_area{
        source_area         = event.area,
        destination_area    = event.area,
        destination_surface = team_surface,
        clone_tiles         = true,
        clone_entities      = true,
        clone_decoratives   = true,
        expand_map          = false,
    }
end

return clone_mirror
