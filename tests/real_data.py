#!/usr/bin/env python3
"""Shared harness for running the SHIPPED reaper logic over a real audit CSV.

Builds a mock Factorio world from the measured rows and runs the actual
scripts/reaper/scan.lua against it, so the verdicts reported are the mod's own,
not a Python restatement of the rule.
"""
import csv, os
# Factorio embeds Lua 5.2. lupa's default runtime is newer and accepts
# constructs 5.2 rejects (\u{} escapes, // division, integer subtypes), which
# let a load-time failure pass every headless check once. Pin to 5.2.
from lupa.lua52 import LuaRuntime

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DAY, HOUR = 60 * 60 * 60 * 24, 60 * 60 * 60
NOW = 400 * DAY
RED, GREEN = "automation-science-pack", "logistic-science-pack"
DEFAULT_CSV = os.path.expanduser("~/.factorio/script-output/mts-team-audit.csv")

def load(path=None):
    return list(csv.DictReader(open(path or DEFAULT_CSV)))

def _lua_teams(rows):
    out = []
    for r in rows:
        offline = float(r["offline_days"])
        online  = "true" if offline == 0.0 else "false"
        last    = int(NOW - offline * DAY)
        people = ",".join(
            f'{{name=[[{r["leader"]}]],connected={online},last_online={last},'
            f'online_time={HOUR}}}' for _ in range(max(int(r["members"]), 1)))
        out.append(
            f'[{int(r["slot"])}]={{occupied=true,'
            f'online_ticks={int(float(r["team_hours"]) * HOUR)},'
            f'display_name=[[{r["name"]}]],members={{{people}}},'
            f'surfaces={{{{production={{["{RED}"]={int(r[RED])},'
            f'["{GREEN}"]={int(r[GREEN])}}},'
            f'entities={min(int(r["entities"]), 3000)},ghosts=0}}}}}}')
    return ",".join(out)

def scan(rows, offline_days=1, max_teams=60):
    """Run the real scan.run{full=true}. Returns a list of row dicts."""
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute(f'package.path = "{ROOT}/?.lua;" .. package.path')
    out = lua.execute(f'''
        local mock = require("tests.mock_factorio")
        mock.build{{ tick = {NOW}, max_teams = {max_teams},
            science = {{"{RED}", "{GREEN}"}}, items = {{"{RED}", "{GREEN}"}},
            teams = {{{_lua_teams(rows)}}} }}
        mock.install_stubs()
        require("scripts.reaper.markers").resolve()
        require("scripts.reaper.config").set_number("offline_days", {offline_days})
        local scan = require("scripts.reaper.scan")
        local result = scan.run{{full = true}}
        local flat = {{}}
        for i, row in ipairs(result.rows) do
            flat[i] = {{ slot = row.slot, name = row.display_name,
                leader = row.leader_name or "-", members = row.member_count,
                connected = row.connected and 1 or 0,
                offline_ticks = row.offline_ticks or -1,
                team_ticks = row.team_ticks or 0, entities = row.entities or -1,
                tier1 = row.tier1 or 0, tier2 = row.tier2 or 0,
                verdict = row.verdict, reason = row.reason }}
        end
        return flat
    ''')
    rows_out = []
    for i in range(1, len(out) + 1):
        r = out[i]
        rows_out.append({
            "slot": int(r["slot"]), "name": str(r["name"]),
            "leader": str(r["leader"]), "members": int(r["members"]),
            "connected": bool(int(r["connected"])),
            "offline_days": (float(r["offline_ticks"]) / DAY
                             if float(r["offline_ticks"]) >= 0 else None),
            "team_hours": float(r["team_ticks"]) / HOUR,
            "entities": int(r["entities"]), "tier1": int(r["tier1"]),
            "tier2": int(r["tier2"]), "verdict": str(r["verdict"]),
            "reason": str(r["reason"]),
        })
    return rows_out
