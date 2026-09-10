-- scripts/reaper/markers.lua
-- Resolves which items count as "tier 1" and "tier 2" science on THIS modpack.
--
-- Hardcoding automation-science-pack is wrong on every overhaul: the prototype
-- may not exist, and a missing prototype reads as zero production, which would
-- mark every team on the server reapable. Sorting the lab-accepted packs by
-- tech unlock depth gives the right two items on vanilla, Bob's/Angel's,
-- Krastorio and Sea Block alike. Alphabetical order does not -- on the author's
-- own save it puts angels-token-bio ahead of automation-science-pack.
--
-- Resolution is pinned into storage so a mod update cannot silently shift the
-- marker under a running save, and an admin can override either slot.

local discovery = require("gui.stats.discovery")
local config    = require("scripts.reaper.config")

local M = {}

M.TIERS = {"tier1", "tier2"}

local function store()
    storage.reaper_markers = storage.reaper_markers or {}
    return storage.reaper_markers
end

--- Science packs every lab in this modpack accepts, ordered by unlock depth,
--- and filtered to those something can actually make.
---
--- The filter is not defensive tidying, it is the whole safety property. On the
--- author's own SeaBlock server the labs accept space-science-pack, which no
--- recipe in that pack produces (it drops from a satellite launch). Every team
--- therefore reads zero of it, and an unfiltered list picked it as tier 1 and
--- condemned 34 of 46 teams, established bases included. A marker nothing can
--- produce measures nothing.
local function discovered_packs()
    local ok, lists = pcall(discovery.proto_lists)
    if not ok or not lists or not lists.science then return {} end
    local names = {}
    for _, entry in ipairs(lists.science) do
        if entry and entry.name and discovery.has_known_producer(entry.name) then
            names[#names + 1] = entry.name
        end
    end
    return names
end

--- A resolved marker changing under a running save means a mod altered the
--- progression. Every verdict on record was measured against the old marker, so
--- keep it and stop destroying anything until an admin has looked.
local function on_shift(tier, pinned, found)
    store()[tier .. "_shifted"] = found
    if config.value("auto_disband_enabled") then
        config.set_flag("auto_disband_enabled", false)
    end
    log("[multi-team-support:reaper] " .. tier .. " marker shifted from "
        .. tostring(pinned) .. " to " .. tostring(found)
        .. "; auto disband disarmed pending admin review")
end

--- Pin tier1/tier2 from prototype discovery, leaving admin overrides intact.
--- Safe to call on every init and configuration change.
---
--- This genuinely pins. An earlier version reassigned on every
--- on_configuration_changed, so any mod being added, removed or version-bumped
--- could silently repoint the marker at a different item mid-save while the
--- reaper stayed armed.
function M.resolve()
    local packs = discovered_packs()
    local marks = store()
    for i, tier in ipairs(M.TIERS) do
        local override = marks[tier .. "_override"]
        local pinned   = marks[tier]
        local found    = packs[i]
        if override then                                     -- admin's choice stands
            marks[tier .. "_shifted"] = nil
        elseif pinned == nil or prototypes.item[pinned] == nil then
            marks[tier] = found                              -- first run, or the pin died
            marks[tier .. "_shifted"] = nil
        elseif found ~= nil and found ~= pinned then
            on_shift(tier, pinned, found)
        else
            marks[tier .. "_shifted"] = nil
        end
    end
    marks.discovered = packs
    return marks
end

--- Resolve on first use as well as at init. A save loaded after the mod files
--- changed in place (no version bump) never fires on_configuration_changed, so
--- without this the markers would stay nil and quietly disable the whole
--- feature rather than reporting a problem.
function M.ensure()
    local marks = store()
    if marks.tier1 == nil and marks.tier1_override == nil then M.resolve() end
    return marks
end

local function resolved(tier)
    local marks = store()
    return marks[tier .. "_override"] or marks[tier]
end

function M.tier1() return resolved("tier1") end
function M.tier2() return resolved("tier2") end

function M.discovered() return store().discovered or {} end

function M.is_override(tier) return store()[tier .. "_override"] ~= nil end

--- Set or clear an admin override. Passing nil returns the tier to discovery.
function M.set_override(tier, item_name)
    if tier ~= "tier1" and tier ~= "tier2" then return false end
    if item_name ~= nil then
        if not prototypes.item[item_name] then return false end
        -- Refuse the exact hazard this module exists to prevent: a marker
        -- nothing can make reads zero for every team on the server.
        if not discovery.has_known_producer(item_name) then return false end
    end
    local marks = store()
    marks[tier .. "_override"] = item_name
    if item_name == nil then
        -- Returning a tier to automatic means "trust discovery from now": drop
        -- the pin as well, otherwise resolve() would just re-detect the same
        -- shift against the old pin and leave the feature blocked.
        marks[tier] = nil
        marks[tier .. "_shifted"] = nil
        M.resolve()
    end
    return true
end

--- The reaper refuses to run without a tier-1 marker that actually exists.
--- Returning zero for a missing prototype would make every team look dead, so
--- an unresolvable marker must disable the feature rather than default.
function M.ready()
    M.ensure()
    local name = M.tier1()
    if type(name) ~= "string" or prototypes.item[name] == nil then return false end
    -- An item nothing can produce reads zero for every team on the server, which
    -- would condemn all of them. Refuse rather than measure the unmeasurable.
    if not discovery.has_known_producer(name) then return false end
    return store().tier1_shifted == nil
end

function M.blocked_reason()
    local name = M.tier1()
    if name == nil then return {"mts-reaper.blocked-no-science"} end
    if prototypes.item[name] == nil then
        return {"mts-reaper.blocked-missing-item", tostring(name)}
    end
    if not discovery.has_known_producer(name) then
        return {"mts-reaper.blocked-unproducible", tostring(name)}
    end
    return {"mts-reaper.blocked-shifted", tostring(name),
            tostring(store().tier1_shifted)}
end

return M
