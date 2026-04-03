-- Solo Teams - landing_pen.lua
-- Author: bits-orio
-- License: MIT
--
-- A shared pre-game waiting surface ("Landing Pen") where all new players
-- land before spawning into the actual game.  Players see each other in the
-- pen and click "Spawn into game" when they're ready, so everyone can start
-- at roughly the same time.

local M = {}
local admin_gui = require("admin_gui")

-- ---------------------------------------------------------------------------
-- Layout constants
-- ---------------------------------------------------------------------------

local PEN_RADIUS   = 15   -- lab-dark-2 island radius (matches OARC holding pen)
local MOAT_OUTER   = PEN_RADIUS + 3   -- water moat outer edge
local GRASS_OUTER  = MOAT_OUTER  + 3   -- grass ring outer edge; void beyond
local SPAWN_RADIUS = 5    -- radius of the ring where players are placed
local MAX_SLOTS    = 8    -- number of evenly-spaced spawn positions
local SURFACE_NAME = "landing-pen"

-- ---------------------------------------------------------------------------
-- Surface creation
-- ---------------------------------------------------------------------------

--- Compute the tile name for a position based on distance from the origin.
--- Ring layout (matches OARC holding-pen dimensions):
---   r < PEN_RADIUS  (15)  → lab-dark-2   (central lobby)
---   r < MOAT_OUTER  (18)  → water        (moat)
---   r < GRASS_OUTER (21)  → grass-1      (outer ring)
---   otherwise             → out-of-map   (void)
local function tile_for_distance(r)
    if r < PEN_RADIUS then
        return "lab-dark-2"
    elseif r < MOAT_OUTER then
        return "water"
    elseif r < GRASS_OUTER then
        return "grass-1"
    else
        return "out-of-map"
    end
end

--- Create the landing-pen surface with a circular island.
local function get_or_create_surface()
    if game.surfaces[SURFACE_NAME] then
        return game.surfaces[SURFACE_NAME]
    end

    local surface = game.create_surface(SURFACE_NAME, {
        default_enable_all_autoplace_controls = false,
        autoplace_settings = {
            entity     = {treat_missing_as_default = false, settings = {}},
            tile       = {treat_missing_as_default = false, settings = {}},
            decorative = {treat_missing_as_default = false, settings = {}},
        },
    })
    surface.always_day  = true
    surface.show_clouds = false

    -- Force-generate centre chunks so we can teleport immediately.
    surface.request_to_generate_chunks({x = 0, y = 0}, 2)
    surface.force_generate_chunk_requests()

    -- Ground text decorations
    rendering.draw_text{
        text      = "SOLO TEAMS",
        surface   = surface,
        target    = {x = 0, y = -8},
        color     = {r = 0.9, g = 0.7, b = 0.3, a = 0.8},
        scale     = 5,
        font      = "default-large-bold",
        alignment = "center",
    }
    rendering.draw_text{
        text      = "Solo by design. Legendary by choice.",
        surface   = surface,
        target    = {x = 0, y = -4},
        color     = {r = 0.7, g = 0.7, b = 0.7, a = 0.8},
        scale     = 3,
        font      = "default-large",
        alignment = "center",
    }
    rendering.draw_text{
        text      = "Spawn when ready",
        surface   = surface,
        target    = {x = 0, y = 4},
        color     = {r = 1.0, g = 1.0, b = 1.0, a = 0.5},
        scale     = 1.5,
        font      = "default",
        alignment = "center",
    }

    return surface
end

--- on_chunk_generated handler — tiles every chunk on the pen surface.
--- This catches both the initial force-generated chunks AND any chunks
--- Factorio generates later (e.g. if a player scrolls the map), ensuring
--- nothing but void appears outside the island.
function M.on_chunk_generated(event)
    if event.surface.name ~= SURFACE_NAME then return end

    local area = event.area
    local tiles = {}
    for x = area.left_top.x, area.right_bottom.x - 1 do
        for y = area.left_top.y, area.right_bottom.y - 1 do
            local r = math.sqrt(x * x + y * y)
            tiles[#tiles + 1] = {name = tile_for_distance(r), position = {x, y}}
        end
    end
    event.surface.set_tiles(tiles)

    -- Remove any auto-placed entities (resources, trees, etc.)
    for _, entity in ipairs(event.surface.find_entities(area)) do
        if entity.type ~= "character" then
            entity.destroy()
        end
    end
end

--- Map a 0-based slot index to a world position on the spawn ring.
local function get_spawn_position(slot)
    local angle = slot * (2 * math.pi / MAX_SLOTS)
    return {
        x = math.floor(SPAWN_RADIUS * math.cos(angle) + 0.5),
        y = math.floor(SPAWN_RADIUS * math.sin(angle) + 0.5),
    }
end

-- ---------------------------------------------------------------------------
-- Buddy-request helpers
-- ---------------------------------------------------------------------------

--- Build the buddy-request popup on the target player's screen.
local function show_buddy_request_gui(target, requester)
    if target.gui.screen.sb_buddy_req_frame then
        target.gui.screen.sb_buddy_req_frame.destroy()
    end
    local frame = target.gui.screen.add{
        type      = "frame",
        name      = "sb_buddy_req_frame",
        direction = "vertical",
    }
    frame.auto_center = true

    local title_bar = frame.add{type = "flow", direction = "horizontal"}
    title_bar.style.vertical_align = "center"
    title_bar.drag_target = frame
    title_bar.add{type = "label", caption = "Buddy Request", style = "frame_title"}
    local spacer = title_bar.add{type = "empty-widget", style = "draggable_space_header"}
    spacer.style.horizontally_stretchable = true
    spacer.style.height = 24
    spacer.drag_target = frame

    local msg = frame.add{type = "label", caption = requester.name .. " wants to join your team."}
    msg.style.top_margin    = 6
    msg.style.bottom_margin = 4
    msg.style.left_margin   = 4

    frame.add{type = "line"}

    local btn_flow = frame.add{type = "flow", direction = "horizontal"}
    btn_flow.style.top_margin    = 4
    btn_flow.style.bottom_margin = 2
    local accept_btn = btn_flow.add{
        type    = "button",
        name    = "sb_buddy_accept",
        caption = "Accept",
        style   = "confirm_button",
        tags    = {sb_requester_index = requester.index},
    }
    accept_btn.style.horizontally_stretchable = true
    local reject_btn = btn_flow.add{
        type    = "button",
        name    = "sb_buddy_reject",
        caption = "Reject",
        style   = "red_button",
        tags    = {sb_requester_index = requester.index},
    }
    reject_btn.style.horizontally_stretchable = true
end

-- ---------------------------------------------------------------------------
-- Public API
-- ---------------------------------------------------------------------------

--- Returns true when the player has not yet clicked "Spawn into game".
function M.is_in_pen(player)
    storage.spawned_players = storage.spawned_players or {}
    return not storage.spawned_players[player.index]
end

--- Place a player into the landing pen.
--- If the player is already on the pen surface the teleport is skipped
--- (they're already in position) and only the GUI is rebuilt.
--- The teleport is deferred one tick via storage.pending_pen_tp so it is
--- safe to call from on_player_created before the character is ready.
function M.place_player(player)
    local surface = get_or_create_surface()
    storage.pen_slots = storage.pen_slots or {}

    -- Assign a unique slot if not already assigned
    if not storage.pen_slots[player.index] then
        local used = {}
        for _, s in pairs(storage.pen_slots) do used[s] = true end
        local slot = 0
        while used[slot] do slot = slot + 1 end
        storage.pen_slots[player.index] = slot
    end

    if player.surface == surface then
        -- Already in the pen (reconnect or duplicate call) – just refresh GUI
        M.build_pen_gui(player)
        M.update_pen_gui_all()
    else
        -- Queue teleport; retried each tick until player.teleport() succeeds
        -- (it returns false while the player has no character entity yet).
        storage.pending_pen_tp = storage.pending_pen_tp or {}
        storage.pending_pen_tp[player.index] = {
            surface  = surface,
            position = get_spawn_position(storage.pen_slots[player.index]),
        }
    end
end

--- Process deferred pen teleports.  Must be called from an on_tick handler.
function M.process_pending_teleports()
    if not storage.pending_pen_tp then return end
    if not next(storage.pending_pen_tp) then return end
    local done = {}
    for player_index, tp in pairs(storage.pending_pen_tp) do
        local player = game.get_player(player_index)
        if player and player.valid and tp.surface and tp.surface.valid then
            -- Exit any landing cutscene immediately so the player doesn't watch
            -- the Nauvis drop-pod sequence before being moved to the pen.
            if player.controller_type == defines.controllers.cutscene then
                player.exit_cutscene()
            end
            local ok = player.teleport(tp.position, tp.surface)
            if ok then
                -- Re-assert the player's solo force. The Factorio scenario's
                -- cutscene-end handler runs after on_player_created and resets
                -- the player back to the default "player" force, overwriting
                -- our create_player_force assignment. Correcting it here, right
                -- after the successful teleport, ensures it sticks.
                local solo_force = game.forces["player-" .. player.name]
                if solo_force and player.force ~= solo_force then
                    player.force = solo_force
                end
                done[#done + 1] = player_index
            end
            -- If teleport returned false (character not ready yet), leave the
            -- entry in the queue and retry on the next tick.
        else
            -- Player or surface gone — drop the entry
            done[#done + 1] = player_index
        end
    end
    for _, idx in ipairs(done) do
        storage.pending_pen_tp[idx] = nil
    end
    if #done > 0 then
        -- Rebuild GUIs now that the teleports have fired
        for _, idx in ipairs(done) do
            local player = game.get_player(idx)
            if player and player.connected then
                M.build_pen_gui(player)
            end
        end
        M.update_pen_gui_all()
    end
end

--- Build (or rebuild) the Landing Pen GUI for one player.
function M.build_pen_gui(player)
    local screen = player.gui.screen
    storage.pen_gui_location = storage.pen_gui_location or {}

    if screen.sb_pen_frame then
        storage.pen_gui_location[player.index] = screen.sb_pen_frame.location
        screen.sb_pen_frame.destroy()
    end

    local frame = screen.add{
        type      = "frame",
        name      = "sb_pen_frame",
        direction = "vertical",
    }

    if storage.pen_gui_location[player.index] then
        frame.location = storage.pen_gui_location[player.index]
    else
        frame.location = {x = 5, y = 80}
    end

    -- Title bar (draggable)
    local title_bar = frame.add{type = "flow", direction = "horizontal"}
    title_bar.style.vertical_align = "center"
    title_bar.drag_target = frame
    title_bar.add{type = "label", caption = "Landing Pen", style = "frame_title"}
    local spacer = title_bar.add{type = "empty-widget", style = "draggable_space_header"}
    spacer.style.horizontally_stretchable = true
    spacer.style.height = 24
    spacer.drag_target = frame

    -- Subtitle
    local sub = frame.add{type = "label", caption = "Wait here, then spawn when ready."}
    sub.style.top_margin    = 6
    sub.style.bottom_margin = 4
    sub.style.left_margin   = 4

    -- In-pen player list
    local pen_surface = game.surfaces[SURFACE_NAME]
    if pen_surface then
        local in_pen = {}
        for _, p in pairs(game.players) do
            if p.surface == pen_surface then
                in_pen[#in_pen + 1] = p
            end
        end
        if #in_pen > 0 then
            local hdr = frame.add{type = "label", caption = "In the pen:"}
            hdr.style.font        = "default-bold"
            hdr.style.left_margin = 4
            hdr.style.top_margin  = 4
            for _, p in ipairs(in_pen) do
                local lbl = frame.add{type = "label", caption = "  \xE2\x80\xA2 " .. p.name}
                lbl.style.left_margin = 4
                if p.index == player.index then
                    lbl.style.font_color = {1, 1, 0.6}
                elseif p.connected then
                    lbl.style.font_color = p.chat_color
                else
                    lbl.style.font_color = {0.65, 0.65, 0.65}
                end
            end
        end
    end

    -- Already-spawned player list
    storage.spawned_players = storage.spawned_players or {}
    local spawned_list = {}
    for idx in pairs(storage.spawned_players) do
        local p = game.get_player(idx)
        if p then spawned_list[#spawned_list + 1] = p.name end
    end
    if #spawned_list > 0 then
        table.sort(spawned_list)
        local hdr = frame.add{type = "label", caption = "Already spawned:"}
        hdr.style.font        = "default-bold"
        hdr.style.left_margin = 4
        hdr.style.top_margin  = 6
        for _, name in ipairs(spawned_list) do
            local lbl = frame.add{type = "label", caption = "  \xE2\x80\xA2 " .. name}
            lbl.style.font_color = {0.5, 0.5, 0.5}
            lbl.style.left_margin = 4
        end
    end

    -- Spawn button
    frame.add{type = "line"}.style.top_margin = 6
    local btn = frame.add{
        type    = "button",
        name    = "sb_spawn_btn",
        caption = "Spawn into game",
        style   = "confirm_button",
    }
    btn.style.top_margin              = 4
    btn.style.bottom_margin           = 2
    btn.style.horizontally_stretchable = true

    -- Join-as-buddy section (only when admin flag is enabled)
    if not admin_gui.flag("buddy_join_enabled") then return end
    storage.buddy_requests = storage.buddy_requests or {}
    local my_request = storage.buddy_requests[player.index]
    local active = {}
    for _, p in pairs(game.players) do
        if p.connected and not M.is_in_pen(p) then
            active[#active + 1] = p
        end
    end
    table.sort(active, function(a, b) return a.name < b.name end)

    if #active > 0 then
        frame.add{type = "line"}.style.top_margin = 4
        local hdr = frame.add{type = "label", caption = "Join as buddy:"}
        hdr.style.font        = "default-bold"
        hdr.style.left_margin = 4
        hdr.style.top_margin  = 4

        for _, p in ipairs(active) do
            local row = frame.add{type = "flow", direction = "horizontal"}
            row.style.vertical_align           = "center"
            row.style.left_margin              = 4
            row.style.horizontally_stretchable = true
            local lbl = row.add{type = "label", caption = p.name}
            lbl.style.font_color    = p.chat_color
            lbl.style.minimal_width = 100
            if my_request == p.index then
                local pending = row.add{type = "label", caption = "Pending..."}
                pending.style.font       = "default-small"
                pending.style.font_color = {1, 1, 0.4}
            elseif not my_request then
                row.add{
                    type    = "button",
                    name    = "sb_buddy_request",
                    caption = "Request",
                    style   = "button",
                    tags    = {sb_target_index = p.index},
                    tooltip = "Ask " .. p.name .. " if you can join their team",
                }
            end
        end
    end
end

--- Rebuild the Landing Pen GUI for every connected player currently in the pen.
function M.update_pen_gui_all()
    local surface = game.surfaces[SURFACE_NAME]
    if not surface then return end
    for _, player in pairs(game.players) do
        if player.connected and player.surface == surface and M.is_in_pen(player) then
            M.build_pen_gui(player)
        end
    end
end

--- Mark the player as spawned, release their pen slot, and destroy the GUI.
--- Does NOT teleport — caller is responsible for moving the player.
function M.finish_spawn(player)
    storage.spawned_players       = storage.spawned_players or {}
    storage.spawned_players[player.index] = true

    if storage.pen_slots then
        storage.pen_slots[player.index] = nil
    end

    if player.gui.screen.sb_pen_frame then
        player.gui.screen.sb_pen_frame.destroy()
    end

    -- Update GUI for players still waiting in the pen
    M.update_pen_gui_all()
end

--- Re-show buddy-request popups for any targets who reconnected without one.
function M.rebuild_buddy_request_guis()
    storage.buddy_requests = storage.buddy_requests or {}
    for req_idx, tgt_idx in pairs(storage.buddy_requests) do
        local target    = game.get_player(tgt_idx)
        local requester = game.get_player(req_idx)
        if target and target.connected and requester and requester.valid then
            if not target.gui.screen.sb_buddy_req_frame then
                show_buddy_request_gui(target, requester)
            end
        end
    end
end

--- Send a buddy request from requester to target.
function M.send_buddy_request(requester, target)
    storage.buddy_requests = storage.buddy_requests or {}
    storage.buddy_requests[requester.index] = target.index
    show_buddy_request_gui(target, requester)
    M.build_pen_gui(requester)
end

--- Accept a buddy request: move requester onto target's force and spawn them.
function M.accept_buddy_request(target, requester_index)
    storage.buddy_requests = storage.buddy_requests or {}
    storage.buddy_requests[requester_index] = nil

    if target.gui.screen.sb_buddy_req_frame then
        target.gui.screen.sb_buddy_req_frame.destroy()
    end

    local requester = game.get_player(requester_index)
    if not (requester and requester.valid) then return end

    requester.force = target.force
    M.finish_spawn(requester)
    -- Find the nearest non-colliding position around the target so the two
    -- players don't land on top of each other.
    local spawn_pos = target.surface.find_non_colliding_position(
        "character", target.position, 10, 1
    ) or target.position
    requester.teleport(spawn_pos, target.surface)
    -- Clock starts when the buddy lands on the real game surface
    storage.player_clock_start = storage.player_clock_start or {}
    if not storage.player_clock_start[requester.index] then
        storage.player_clock_start[requester.index] = game.tick
    end

    target.print(requester.name .. " has joined your team.")
    if requester.connected then
        requester.print("You joined " .. target.name .. "'s team.")
    end
end

--- Reject a buddy request.
function M.reject_buddy_request(target, requester_index)
    storage.buddy_requests = storage.buddy_requests or {}
    storage.buddy_requests[requester_index] = nil

    if target.gui.screen.sb_buddy_req_frame then
        target.gui.screen.sb_buddy_req_frame.destroy()
    end

    local requester = game.get_player(requester_index)
    if requester and requester.connected then
        requester.print(target.name .. " declined your buddy request.")
        M.build_pen_gui(requester)
    end
end

return M
