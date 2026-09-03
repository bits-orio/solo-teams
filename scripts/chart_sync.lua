-- scripts/chart_sync.lua
-- Keeps the spectator force's chart of a team surface in step with the team's
-- own. A leaf: requires nothing, so the spectator ops and surface_utils may
-- both use it.
--
-- Factorio's chart sharing PUSHES a friend's chart updates into this force's
-- own chart; it is not a live union. The spectator force therefore holds only
-- what has been pushed since its chart was last cleared, and
-- surface_utils.cleanup_charts clears it every few minutes. An active team
-- keeps re-pushing through players and radars; a dormant one never does, so
-- spectating it showed nothing at all. Measured on the live save: team-15 was
-- charted at spawn by its own force and the spectator force was not, with
-- friendship, sharing and hidden state identical to a working team.

local M = {}

--- Surfaces some spectator is looking at right now. cleanup_charts must not
--- wipe these out from under them.
function M.viewed_surfaces()
    local out = {}
    for player_index in pairs(storage.spectating_target or {}) do
        local player  = game.get_player(player_index)
        local surface = player and player.valid and player.surface
        if surface and surface.valid then out[surface.index] = true end
    end
    return out
end

--- Request, for `viewer`, every chunk of `surface` that `target` has charted
--- and `viewer` has not. Chart requests are cheap; the engine fulfils them
--- over the following ticks. Returns how many were requested.
function M.push_chart(target, viewer, surface)
    if not (target and target.valid and viewer and viewer.valid
            and surface and surface.valid) then return 0 end
    local pushed = 0
    for chunk in surface.get_chunks() do
        if target.is_chunk_charted(surface, chunk)
           and not viewer.is_chunk_charted(surface, chunk) then
            viewer.chart(surface, chunk.area)
            pushed = pushed + 1
        end
    end
    return pushed
end

return M
