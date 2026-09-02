-- scripts/activity.lua
-- The one definition of "when was this player last online", shared by the
-- Teams card member rows, the team activity label, the production stats rows
-- and the inactive-team reaper, so no two of them can disagree about who is
-- idle. A leaf: requires nothing, so anything may require it.

local M = {}

local HOUR = 60 * 60 * 60
local DAY  = HOUR * 24

M.COLOR_FRESH   = {0.4, 1.0, 0.4}      -- under an hour
M.COLOR_STALE   = {1.0, 0.8, 0.2}      -- under a day
M.COLOR_DEAD    = {1.0, 0.4, 0.4}      -- a day or more
M.COLOR_UNKNOWN = {0.55, 0.55, 0.55}   -- never recorded

--- Tick the player was last online; now, if connected. Prefers MTS's own
--- leave stamp and falls back to the engine's last_online, which survives a
--- client crash or server restart that never fired on_player_left_game.
function M.last_online_tick(player)
    if player.connected then return game.tick end
    return (storage.player_last_seen or {})[player.index] or player.last_online
end

--- Ticks since the player was last online. nil if never recorded.
function M.offline_ticks(player)
    local tick = M.last_online_tick(player)
    return tick and (game.tick - tick) or nil
end

function M.age_color(ticks)
    if ticks < HOUR then return M.COLOR_FRESH end
    if ticks < DAY  then return M.COLOR_STALE end
    return M.COLOR_DEAD
end

return M
