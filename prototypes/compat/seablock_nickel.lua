-- Multi-Team Support - prototypes/compat/seablock_nickel.lua
-- Author: bits-orio
-- License: GPL-3.0-or-later
--
-- TEMPORARY. Remove once Sea Block Continued ships the upstream fix.
--
-- Eight Sea Block recipes take `bob-nickel-plate`, whose only producing recipe is
-- hidden and disabled: Angel's retired Bob's nickel chain in favour of its own and
-- these recipes were never repointed. They are researchable and permanently
-- uncraftable, and they gate a large downstream tree -- heat pipe 2 feeds the
-- nuclear reactor and both heat sources; antenna 2 / chargepad 2 feed every
-- roboport, robochest, zone expander and personal roboport tier above 1. Roughly
-- 43 recipe outputs in total (thanks to ZZ for the cascade analysis).
--
-- Upstream: modded-factorio/SeaBlock#375, fixed in KompetenzAirbag/SeaBlock
-- 99f3d13. The substitutions below are copied verbatim from that commit so this
-- shim and a future Sea Block Continued release agree on balance.
--
-- Only the NICKEL half of that commit is applied. Its zinc half is unnecessary
-- here: Sea Block Continued 0.6.3 already restores `bob-zinc-plate` in its own
-- data-final-fixes restore list, so zinc plate is producible.
--
-- WHY THIS LIVES IN MTS, which has no business carrying another mod's recipe
-- balance: the affected server is mid-run and cannot take a new mod into its mod
-- set, but can take an MTS update. Gated on mods["SeaBlockContinued"], so it is
-- inert for every other MTS user. It is also self-disarming -- once upstream ships
-- the fix there is no nickel left to replace and every call becomes a no-op -- so
-- deleting this file is safe at any time and urgent at none.
--
-- Load order note: MTS's data-final-fixes runs BEFORE Sea Block's (verified:
-- 1.319 vs 1.448). That is fine here. The nickel ingredients come from bobplates'
-- data-stage definitions, Sea Block's own nickel substitutions happen at
-- data-updates, and nothing in Sea Block's data-final-fixes touches nickel or any
-- of these eight recipes -- so a substitution made here is not overwritten.

local NICKEL = "bob-nickel-plate"

-- recipe -> replacement ingredient (upstream's choices, not ours)
local SWAPS = {
    ["bob-boiler-3"]             = "bob-invar-alloy",
    ["bob-oil-boiler-2"]         = "bob-invar-alloy",
    ["bob-burner-reactor-2"]     = "bob-invar-alloy",
    ["bob-fluid-reactor-2"]      = "bob-invar-alloy",
    ["bob-heat-pipe-2"]          = "bob-invar-alloy",
    ["bob-heat-exchanger-2"]     = "bob-invar-alloy",
    ["bob-roboport-antenna-2"]   = "bob-aluminium-plate",
    ["bob-roboport-chargepad-2"] = "bob-invar-alloy",
    -- bobwarfare only; the recipe lookup below skips it when absent
    ["bob-plasma-turret-1"]      = "bob-cobalt-steel-alloy",
}

local function ing_name(ing)   return ing.name or ing[1] end
local function ing_amount(ing) return ing.amount or ing[2] or 1 end

--- Replace `from` with `to` in one recipe.
--- If the recipe ALREADY lists `to`, the two entries are MERGED rather than
--- renamed: a recipe carrying the same ingredient twice is a load error, and a
--- plain rename would produce exactly that. Upstream's substingredient does not
--- guard this; none of the current eight collide, but the guard costs nothing and
--- keeps a future addition to SWAPS from bricking the data stage.
local function substitute(recipe_name, from, to)
    local recipe = data.raw.recipe[recipe_name]
    if not (recipe and recipe.ingredients) then return nil end
    if not (data.raw.item[to] or data.raw.fluid[to]) then
        return "REPLACEMENT MISSING: " .. to
    end

    local source_index, source_amount, existing
    for i, ing in pairs(recipe.ingredients) do
        local n = ing_name(ing)
        if n == from then
            source_index, source_amount = i, ing_amount(ing)
        elseif n == to then
            existing = ing
        end
    end
    if not source_index then return nil end

    if existing then
        existing.amount = ing_amount(existing) + source_amount
        table.remove(recipe.ingredients, source_index)
        return "merged x" .. source_amount .. " into existing " .. to
    end

    local ing = recipe.ingredients[source_index]
    if ing.name then ing.name = to else ing[1] = to end
    return "-> " .. to .. " x" .. source_amount
end

local changed, problems = 0, 0
for recipe_name, replacement in pairs(SWAPS) do
    local result = substitute(recipe_name, NICKEL, replacement)
    if result then
        log("[multi-team-support:seablock_nickel] " .. recipe_name .. ": " .. result)
        if result:find("MISSING") then problems = problems + 1 else changed = changed + 1 end
    end
end
log("[multi-team-support:seablock_nickel] substituted " .. changed
    .. " recipe(s), " .. problems .. " problem(s)")
