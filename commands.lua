-- Multi-Team Support - commands.lua
-- Author: bits-orio
-- License: MIT
--
-- Registers console commands:
--   /mts-players  - list all players and their surfaces with GPS pings
--   /mts-leave    - leave your current team and return to the Landing Pen
--   /mts-kick     - kick a player from your team (team leader only)

local surfaces_gui  = require("gui.surfaces")
local helpers       = require("helpers")
local force_utils   = require("force_utils")
local landing_pen   = require("gui.landing_pen")
local spectator     = require("spectator")

local commands_mod = {}

function commands_mod.register()
    commands.add_command("mts-players", "List all players, their bases, and platform locations", function(cmd)
        local caller = cmd.player_index and game.get_player(cmd.player_index)
        local owners, order, owner_info = surfaces_gui.get_platforms_by_owner()
        local lines = {"[All Players]"}
        for _, owner in ipairs(order) do
            lines[#lines + 1] = helpers.colored_name(owner, owner_info[owner].color) .. ":"
            for _, info in ipairs(owners[owner]) do
                lines[#lines + 1] = "  [color=0.7,0.7,0.7]" .. info.name .. "[/color] " .. info.gps .. "  @  " .. info.location
            end
        end
        if #order == 0 then
            lines[#lines + 1] = "  No players found."
        end
        local msg = table.concat(lines, "\n")
        if caller then
            caller.print(msg)
        else
            game.print(msg)
        end
    end)

    commands.add_command("mts-leave", "Leave your current team and return to the Landing Pen", function(cmd)
        local caller = cmd.player_index and game.get_player(cmd.player_index)
        if not caller then
            game.print("This command can only be used by a player.")
            return
        end

        if landing_pen.is_in_pen(caller) then
            caller.print("You are already in the Landing Pen.")
            return
        end

        if spectator.is_spectating(caller) then
            spectator.exit(caller)
        end
        if force_utils.remove_from_team(caller) then
            landing_pen.return_to_pen(caller)
            caller.print("You have left the team." .. helpers.force_tag(caller.force.name))
            surfaces_gui.update_all()
        end
    end)

    commands.add_command("mts-kick", "Kick a player from your team (team leader only). Usage: /mts-kick <player-name>", function(cmd)
        local caller = cmd.player_index and game.get_player(cmd.player_index)
        if not caller then
            game.print("This command can only be used by a player.")
            return
        end

        if not force_utils.is_team_leader(caller) then
            caller.print("Only the team leader can kick players." .. helpers.force_tag(caller.force.name))
            return
        end

        if force_utils.force_member_count(caller.force) < 2 then
            caller.print("You are the only player on your team." .. helpers.force_tag(caller.force.name))
            return
        end

        local target_name = cmd.parameter
        if not target_name or target_name == "" then
            caller.print("Usage: /mts-kick <player-name>")
            return
        end

        target_name = target_name:match("^%s*(.-)%s*$")  -- trim whitespace
        local target = game.get_player(target_name)
        if not target then
            caller.print("Player '" .. target_name .. "' not found.")
            return
        end

        if target.index == caller.index then
            caller.print("You cannot kick yourself. Use /mts-leave instead.")
            return
        end

        if target.force ~= caller.force then
            caller.print(helpers.colored_name(target.name, target.chat_color) .. " is not on your team." .. helpers.force_tag(caller.force.name))
            return
        end

        -- Perform the kick
        if spectator.is_spectating(target) then
            spectator.exit(target)
        end
        if force_utils.remove_from_team(target) then
            landing_pen.return_to_pen(target)
            local ft = helpers.force_tag(caller.force.name)
            target.print("You have been kicked from the team by " .. helpers.colored_name(caller.name, caller.chat_color) .. "." .. ft)
            caller.print("Kicked " .. helpers.colored_name(target.name, target.chat_color) .. " from the team." .. ft)
            surfaces_gui.update_all()
        end
    end)
end

return commands_mod
