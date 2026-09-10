-- Multi-Team Support - scripts/science_packs.lua
-- Author: bits-orio
-- License: MIT
--
-- Which items count as science packs on THIS modpack. Derived from what the
-- labs accept (LuaEntityPrototype::lab_inputs), never from the item type: in
-- Factorio 2.1 science packs are plain items (type "item"), so the old
-- `type == "tool"` test finds nothing there, while lab_inputs reads the same
-- on 2.0 and 2.1 and follows any mod that adds labs or packs.
--
-- Shared by gui/stats/discovery.lua (Science tab) and milestones/config.lua
-- (science milestone) so both see the same set.

local M = {}

--- Set of item names any lab prototype accepts: { [item_name] = true }.
function M.lab_input_set()
    local set = {}
    for _, entity in pairs(prototypes.entity) do
        if entity.type == "lab" then
            for _, input in pairs(entity.lab_inputs or {}) do
                set[input] = true
            end
        end
    end
    return set
end

return M
