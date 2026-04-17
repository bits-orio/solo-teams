# Changelog

## 0.3.6

- Fix unresponsive landing pen buttons after a mod version upgrade —
  on_configuration_changed was back-filling the "spawned" flag for every
  player, including those currently in the pen, which made is_in_pen
  return false and silently gate every pen button

## 0.3.5

- Fix top-bar buttons (Teams, Stats, Research, Welcome) not working in saves
  loaded from older versions — click handlers were registered inside
  on_player_created, which never fires for existing players

## 0.3.4

- Fix landing pen GUI not refreshing after a team is disbanded
- Rebuild open GUIs on version change so stale content goes away after updates

## 0.3.3

- Add `/mts-disband` admin command to disband a team and free the slot
- Fix team clock not resetting when a team slot is released
