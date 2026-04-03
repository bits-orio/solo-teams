# Solo Teams

![Solo Teams](thumbnail.png)

> **Compete solo. Share the world.**

Ever wanted to play Factorio multiplayer but keep your own factory, your own research, and your own pace? Solo Teams gives every player their own independent team on the same shared map. Race your friends to rocket launch, compare research progress, or just build side by side without stepping on each other's toes.

**Discord:** https://discord.gg/tWz4FT74pH

## How it works

When you join a game with Solo Teams, you automatically get your own **force** (Factorio's term for a team). That means:

- **Your own tech tree** - research is independent; unlocking red science doesn't unlock it for anyone else
- **Your own buildings** - nobody can accidentally (or intentionally) mess with your factory
- **Your own space platforms** - if you're playing Space Age or Space Block, each player gets their own platform

You still share the same map and can see each other. Chat works normally across all teams. If you want to cooperate with someone, tick the "friend" checkbox next to their name and they can interact with your buildings.

## The Landing Pen

New players arrive in a shared waiting area called the **Landing Pen** - a small circular platform where everyone can hang out before the game starts. This lets your group wait for everyone to join before anyone clicks "Spawn into game" for a fair start.

From the pen you can also use the **buddy system**: request to join another player's team so you start together on the same planet. The other player gets an Accept/Reject popup.

Admins can disable the Landing Pen from the admin panel if you prefer players to spawn directly.

## GUI panels

Solo Teams adds a row of buttons to the top of your screen:

### Players & Platforms
See every player in the game at a glance - who's online, what surface they're on, and where their platforms are. Click a GPS icon to ping a location in chat. Use the "friend" checkbox to allow another player to access your buildings. There's also a "Return to my base" button if you've wandered onto someone else's surface.

### Production Stats
Compare your factory output against other players. Five item categories (Ores, Plates, Intermediates, Science, Custom) are built from the game's prototypes so it works with overhaul mods. Pick any time range from 1 minute to all time, and swap out items in any column.

### Research
A tech icon grid for every player, ordered by when each technology was researched. At a glance you can see who's ahead and what they've unlocked. Click any player's diff button to see a detailed comparison:

- **You both have researched** - shared progress
- **They have, you don't** - techs to catch up on
- **You have, they don't** - your lead

Click any tech icon to jump straight to it in the tech tree.

### Admin Panel
Visible to all admins. Currently has a Feature Flags tab where you can toggle the Landing Pen on or off at runtime. Disabling it mid-game immediately spawns any players still waiting.

### Welcome / Discord
A quick intro to the mod with a Discord invite and QR code. Auto-opens for new players, re-openable anytime from the nav bar.

## Commands

| Command | What it does |
|---------|-------------|
| `/platforms` | Lists all players and their platforms with clickable GPS pings |
| `/unstuck` | Ejects you from a vehicle and teleports to a safe position nearby |

## Installation

**From the Mod Portal:**
Search for "Solo Teams" in the Factorio mod manager and click Install.

**Manual:**
1. Download the latest release zip from [GitHub Releases](https://github.com/bits-orio/solo-teams/releases)
2. Place the zip (don't extract it) in your Factorio mods folder
3. Enable it in the mod manager

The mod activates automatically - every player who joins gets their own team.

## Compatibility

- Requires **Factorio 2.0** (Space Age recommended but not required)
- Works great with [Space Block](https://mods.factorio.com/mod/yunrus-space-block) - the scenario it was originally built for
- Works with vanilla Nauvis surfaces - each player gets their own copy of the planet
- Optional integration with [Platformer](https://mods.factorio.com/mod/platformer) for per-player space platforms
- Factorio supports up to 64 forces, so roughly 61 players can have their own team (after the built-in enemy/neutral/player forces)

## License

[MIT](LICENSE)
