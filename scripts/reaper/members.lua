-- scripts/reaper/members.lua
-- The single source of truth for "who is on this team, and when was the team
-- last occupied by a living player".
--
-- force.players is NOT that answer. A player spectating another team is moved
-- onto the spectator force for the duration, so their own team reads as
-- member-less. Both disband paths already work around this by calling
-- spectator.exit_all_for_force first; a read-only scan cannot, so it resolves
-- membership through spectator.get_effective_force instead -- the same
-- resolution the team clock uses.

local spectator = require("scripts.spectator")

local M = {}

--- Every player bucketed by the team they really belong to, spectators
--- included. One pass over game.players; team forces with nobody on them are
--- absent from the result rather than present-and-empty.
function M.by_force()
    local buckets = {}
    for _, player in pairs(game.players) do
        if player and player.valid then
            local force_name = spectator.get_effective_force(player)
            if force_name then
                local bucket = buckets[force_name]
                if not bucket then bucket = {}; buckets[force_name] = bucket end
                bucket[#bucket + 1] = player
            end
        end
    end
    return buckets
end

function M.any_connected(list)
    for _, player in ipairs(list or {}) do
        if player.connected then return true end
    end
    return false
end

--- Tick of the most recent moment ANY member was online, which is what "the
--- whole team has been offline since X" means. A connected member pins it to
--- now. nil when no member has ever been recorded online.
function M.last_seen_tick(list)
    local best
    for _, player in ipairs(list or {}) do
        local seen = player.connected and game.tick or player.last_online
        if seen and (not best or seen > best) then best = seen end
    end
    return best
end

--- Longest-serving member, used only to label a row. Falls back to the first
--- member so a team is never displayed without a name.
function M.representative(list)
    local best
    for _, player in ipairs(list or {}) do
        if not best or (player.online_time or 0) > (best.online_time or 0) then
            best = player
        end
    end
    return best
end

return M
