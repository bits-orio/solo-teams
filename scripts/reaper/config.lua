-- scripts/reaper/config.lua
-- Admin-tunable reaper settings, stored in the save.
--
-- Deliberately NOT in settings.lua: Factorio shows every runtime-global mod
-- setting to ALL players (only admins may change them), so putting the
-- inactivity thresholds there would publish them on the server's own settings
-- screen. Storage-backed values are reachable only through the admin-gated
-- Cleanup GUI, which keeps the operator's actual numbers private even though
-- the defaults are readable in this open-source file.

local M = {}

M.TICKS_PER_HOUR = 60 * 60 * 60
M.TICKS_PER_DAY  = M.TICKS_PER_HOUR * 24

-- The reaper wakes on a fixed hourly heartbeat and acts only when cycle_hours
-- have elapsed. Registering a fixed period keeps on_load deterministic; a
-- configurable on_nth_tick period would have to be re-registered on every
-- change and re-derived identically at load.
M.HEARTBEAT_TICKS = M.TICKS_PER_HOUR

local DEFAULTS = {
    auto_disband_enabled = false,  -- phase 3 stays disarmed until an admin opts in
    offline_days         = 1,
    cycle_hours          = 6,
    slot_pressure_min    = 5,      -- nudge when free slots fall below this
    history_limit        = 500,
}

local BOUNDS = {
    offline_days      = {1, 60},
    cycle_hours       = {1, 24},
    slot_pressure_min = {0, 50},
    history_limit     = {50, 2000},
}

function M.get()
    storage.reaper_config = storage.reaper_config or {}
    local cfg = storage.reaper_config
    for key, default in pairs(DEFAULTS) do
        if cfg[key] == nil then cfg[key] = default end
    end
    return cfg
end

--- Validated read. Writes are clamped, but a value can still arrive out of
--- range from an older save or a hand-edited one, and offline_days = 0 would
--- reap every team the moment it went offline. Clamp on the way out too.
function M.value(key)
    local value = M.get()[key]
    local bound = BOUNDS[key]
    if not bound or type(value) ~= "number" then return value end
    if value < bound[1] or value > bound[2] then
        return math.max(bound[1], math.min(bound[2], value))
    end
    return value
end

--- Clamp and store a numeric setting. Returns the value actually stored, so a
--- caller can report the clamp back to the admin rather than silently differ.
function M.set_number(key, value)
    local bound = BOUNDS[key]
    if not bound or type(value) ~= "number" then return nil end
    local clamped = math.max(bound[1], math.min(bound[2], math.floor(value)))
    M.get()[key] = clamped
    return clamped
end

function M.set_flag(key, value)
    if type(value) ~= "boolean" then return nil end
    M.get()[key] = value
    return value
end

function M.offline_ticks()
    return M.value("offline_days") * M.TICKS_PER_DAY
end

function M.bounds(key)
    local b = BOUNDS[key]
    return b and b[1], b and b[2]
end

return M
