#!/usr/bin/env python3
"""End-to-end check of the shipped rule against a real server audit.

Feeds the CSV produced in-game by /mts-reaper dump (or the original console
audit) through the actual scan module and reports which teams it flags. This is
the design's regression test against production data, not a synthetic case.
"""
import csv, os, sys
from lupa import LuaRuntime

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DAY, HOUR = 60 * 60 * 60 * 24, 60 * 60 * 60
NOW = 400 * DAY
RED, GREEN = "automation-science-pack", "logistic-science-pack"

def lua_teams(rows):
    out = []
    for r in rows:
        slot     = int(r["slot"])
        offline  = float(r["offline_days"])
        members  = int(r["members"])
        online   = "true" if offline == 0.0 else "false"
        last     = int(NOW - offline * DAY)
        people = ",".join(
            f'{{name="{r["leader"]}",connected={online},last_online={last},online_time={HOUR}}}'
            for _ in range(max(members, 1)))
        out.append(
            f'[{slot}]={{occupied=true,online_ticks={int(float(r["team_hours"]) * HOUR)},'
            f'display_name=[[{r["name"]}]],members={{{people}}},'
            f'surfaces={{{{production={{["{RED}"]={int(r[RED])},["{GREEN}"]={int(r[GREEN])}}},'
            f'entities={min(int(r["entities"]), 3000)},ghosts=0}}}}}}')
    return ",".join(out)

def main(path):
    rows = list(csv.DictReader(open(path)))
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute(f'package.path = "{ROOT}/?.lua;" .. package.path')
    script = f'''
        local mock = require("tests.mock_factorio")
        mock.build{{
            tick = {NOW}, max_teams = 60,
            science = {{"{RED}", "{GREEN}"}},
            items   = {{"{RED}", "{GREEN}"}},
            teams   = {{{lua_teams(rows)}}},
        }}
        mock.install_stubs()
        require("scripts.reaper.markers").resolve()
        local scan = require("scripts.reaper.scan")
        local result = scan.run{{full = true}}
        local flagged = {{}}
        for _, row in ipairs(scan.reapable(result)) do
            flagged[#flagged + 1] = row.slot
        end
        table.sort(flagged)
        return {{n = #result.rows, flagged = table.concat(flagged, ","),
                 count = #flagged}}
    '''
    out = lua.execute(script)
    flagged = [int(x) for x in str(out["flagged"]).split(",") if x]

    # Independent recomputation of the same rule, straight from the CSV.
    expected = sorted(int(r["slot"]) for r in rows
                      if float(r["offline_days"]) >= 1 and int(r[RED]) == 0)

    print(f"teams scanned:        {int(out['n'])}")
    print(f"flagged by scan.lua:  {len(flagged)}  slots {flagged}")
    print(f"expected by the rule: {len(expected)}  slots {expected}")
    ok = flagged == expected
    print("\nMATCH" if ok else "\nMISMATCH: " + str(set(flagged) ^ set(expected)))

    worst = max((r for r in rows if int(r["slot"]) in flagged),
                key=lambda r: int(r["iron_plate"]), default=None)
    if worst:
        print(f"most-invested team flagged: {worst['leader']} "
              f"({worst['iron_plate']} iron, {worst['team_hours']}h, "
              f"{worst['entities']} entities)")
    return 0 if ok else 1

if __name__ == "__main__":
    sys.exit(main(sys.argv[1] if len(sys.argv) > 1
                  else os.path.expanduser("~/.factorio/script-output/mts-team-audit.csv")))
