-- gui/cleanup/state.lua
-- Per-player Cleanup panel state: which rows are ticked, how the table is
-- sorted, and the selection handed to the confirm dialog.
--
-- Selection is keyed by force name rather than row index so it survives a
-- refresh that reorders or drops rows.

local M = {}

M.SORT_KEYS = {
    verdict = true, offline = true, team_hours = true,
    tier1 = true, entities = true, slot = true,
}

local function bucket(key, player_index)
    storage[key] = storage[key] or {}
    storage[key][player_index] = storage[key][player_index] or {}
    return storage[key][player_index]
end

function M.selection(player) return bucket("cleanup_selection", player.index) end

function M.is_selected(player, force_name)
    return M.selection(player)[force_name] ~= nil
end

--- A tick stores the slot GENERATION it was made against, not a bare true. If
--- that team disbands and a new one claims the slot while the panel is open,
--- the stored generation no longer matches and the tick is ignored, so a
--- selection can never be inherited by a team the admin never saw.
function M.set(player, force_name, generation)
    M.selection(player)[force_name] = generation
end

function M.clear(player)
    storage.cleanup_selection = storage.cleanup_selection or {}
    storage.cleanup_selection[player.index] = {}
end

--- Preselect exactly what the armed rule would take, and nothing else. Done
--- once per opening so a later refresh never undoes the admin's edits.
function M.preselect(player, rows)
    M.clear(player)
    local selection = M.selection(player)
    for _, row in ipairs(rows) do
        if row.verdict == "reap" then selection[row.force_name] = row.generation end
    end
end

function M.selected_rows(player, rows)
    local selection = M.selection(player)
    local out = {}
    for _, row in ipairs(rows) do
        -- Two refusals, whatever the checkbox says: a team that came back online
        -- since the panel was drawn, and a slot recycled by a different team
        -- since the tick was made.
        local picked = selection[row.force_name]
        if picked ~= nil and not row.connected and picked == row.generation then
            out[#out + 1] = row
        end
    end
    return out
end

--- Cached scan result for an open panel. Measuring every team reads production
--- statistics per surface, which is far too expensive to repeat on every
--- checkbox click, so the panel measures on open and re-renders from this.
function M.cache(player, result)
    storage.cleanup_cache = storage.cleanup_cache or {}
    storage.cleanup_cache[player.index] = result
end

function M.cached(player)
    storage.cleanup_cache = storage.cleanup_cache or {}
    return storage.cleanup_cache[player.index]
end

function M.drop_cache(player)
    storage.cleanup_cache = storage.cleanup_cache or {}
    storage.cleanup_cache[player.index] = nil
end

function M.sort(player)
    storage.cleanup_sort = storage.cleanup_sort or {}
    storage.cleanup_sort[player.index] =
        storage.cleanup_sort[player.index] or {key = "verdict", ascending = true}
    return storage.cleanup_sort[player.index]
end

function M.set_sort(player, key)
    if not M.SORT_KEYS[key] then return end
    local sort = M.sort(player)
    if sort.key == key then
        sort.ascending = not sort.ascending
    else
        sort.key, sort.ascending = key, true
    end
end

-- Deadest first: reap, then skip, then keep.
local VERDICT_ORDER = {reap = 1, skip = 2, keep = 3}

local function sort_value(row, key)
    if key == "verdict"    then return VERDICT_ORDER[row.verdict] or 9 end
    if key == "offline"    then return -(row.offline_ticks or -1) end
    if key == "team_hours" then return row.team_ticks or 0 end
    if key == "tier1"      then return row.tier1 or 0 end
    if key == "entities"   then return row.entities or -1 end
    return row.slot or 0
end

function M.apply_sort(player, rows)
    local sort = M.sort(player)
    table.sort(rows, function(a, b)
        local va, vb = sort_value(a, sort.key), sort_value(b, sort.key)
        if va == vb then return (a.slot or 0) < (b.slot or 0) end
        if sort.ascending then return va < vb end
        return va > vb
    end)
    return rows
end

--- Selection staged for the confirm dialog. Kept in storage rather than in GUI
--- tags so a 40-team selection does not have to round-trip through element tags.
function M.stage(player, entries)
    storage.cleanup_pending = storage.cleanup_pending or {}
    storage.cleanup_pending[player.index] = entries
end

function M.take_staged(player)
    storage.cleanup_pending = storage.cleanup_pending or {}
    local entries = storage.cleanup_pending[player.index]
    storage.cleanup_pending[player.index] = nil
    return entries
end

return M
