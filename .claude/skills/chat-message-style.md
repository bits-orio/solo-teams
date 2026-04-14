---
name: chat-message-style
description: Coding conventions for player-facing chat messages and GUI labels in the Multi-Team Support Factorio mod. Covers player name colorization and force name tagging.
---

# Chat Message & GUI Style Guide

When writing or modifying any player-facing messages (via `player.print`, `helpers.broadcast`, or GUI labels), follow these two rules strictly.

## Rule 1: Player names must always be colorized

Never use `player.name` directly in a player-visible message. Always wrap it with `helpers.colored_name()` using the player's `chat_color`:

```lua
-- WRONG
target.print(requester.name .. " has joined your team.")

-- CORRECT
target.print(helpers.colored_name(requester.name, requester.chat_color) .. " has joined your team.")
```

`helpers.colored_name(name, color)` produces Factorio rich text: `[color=R,G,B]name[/color]`

When you have the player object, use `player.chat_color`. If you only have a name string, look up the player first:
```lua
local p = game.get_player(name)
if p then helpers.colored_name(p.name, p.chat_color) end
```

**Applies to:** `player.print()`, `helpers.broadcast()`, GUI labels that mention player names.

**Does NOT apply to:** `log()` calls (debug only, not shown to players), tooltips, or internal identifiers.

## Rule 2: Force name tag must appear after every mention of "team"

Whenever a message mentions the word "team" (your team, the team, team leader, former team, etc.), append a grey force-name tag using `helpers.force_tag()`:

```lua
-- WRONG
caller.print("You have left the team.")

-- CORRECT
caller.print("You have left the team." .. helpers.force_tag(caller.force.name))
```

`helpers.force_tag(force_name)` produces: ` [color=0.50,0.50,0.50](force-bob)[/color]`

The force tag always goes at the **end of the sentence**, after the period.

### Examples of correct messages:

```lua
-- Team join
requester.print("You joined " .. cn_target .. "'s team." .. helpers.force_tag(target.force.name))

-- Team leave
member.print(cn_player .. " has left the team." .. ft)

-- Team leader change
member.print(cn_leader .. " is now the team leader." .. ft)

-- Broadcast
helpers.broadcast("[Team] " .. cn_leader .. " now leads " .. cn_player .. "'s former team." .. ft)

-- Kick
target.print("You have been kicked from the team by " .. cn_caller .. "." .. ft)

-- Team full
requester.print(cn_target .. "'s team is full." .. helpers.force_tag(target.force.name))
```

### Common pattern — cache both for readability:

```lua
local cn_player = helpers.colored_name(player.name, player.chat_color)
local ft = helpers.force_tag(old_force_name)
member.print(cn_player .. " has left the team." .. ft)
```

## In the Players GUI (surfaces_gui)

The Players GUI shows the force name in grey brackets next to each owner name:

```lua
if info.force_name then
    local force_lbl = owner_flow.add{type = "label", caption = " [" .. info.force_name .. "]"}
    force_lbl.style.font       = "default-small"
    force_lbl.style.font_color = {0.5, 0.5, 0.5}
end
```

## Helper functions reference

| Function | Location | Purpose |
|----------|----------|---------|
| `helpers.colored_name(name, color)` | `helpers.lua` | Wraps a name in `[color]...[/color]` rich text |
| `helpers.force_tag(force_name)` | `helpers.lua` | Returns grey ` (force-name)` suffix for chat messages |
| `helpers.colored_name` + `helpers.force_tag` | Combined | Standard pattern for all team-related messages |
