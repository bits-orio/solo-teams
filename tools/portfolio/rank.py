#!/usr/bin/env python3
"""Track where bits-orio's mods rank in Factorio mod portal search."""
import subprocess, urllib.parse, re, time, sys

QUERIES = ["MTS", "multi player", "multiplayer", "multi force", "oarc",
           "separate spawns", "teams", "co-op", "multi-team", "separate research",
           "team race", "private spawn", "server teams"]

# mts-expanse is deliberately absent: it belongs to zzh8829, not bits-orio.
MINE = {"multi-team-support", "open-discord-bridge", "diggy", "brave-new-mts",
        "mts-dimension-warp", "land-title-registry"}
PRIMARY = "multi-team-support"

def results(q, depth=40):
    url = ("https://mods.factorio.com/search?query=" + urllib.parse.quote(q) +
           "&exclude_category=internal&factorio_version=2.0&sort_attribute=relevancy"
           f"&cb={int(time.time()*1000)}")
    h = subprocess.run(["curl", "-s", "--compressed", "-H", "Cache-Control: no-cache",
                        "-A", "Mozilla/5.0 (X11; Linux x86_64)", url],
                       capture_output=True, text=True).stdout
    seen, out = set(), []
    for m in re.findall(r'href="/mod/([a-zA-Z0-9_.-]+)', h):
        if m not in seen:
            seen.add(m); out.append(m)
    return out[:depth]

print(f"{'query':<20} {'MTS rank':<10} other mods of yours in top 40")
print("-" * 78)
for q in QUERIES:
    r = results(q)
    rank = (r.index(PRIMARY) + 1) if PRIMARY in r else None
    others = [f"{m}(#{r.index(m)+1})" for m in r if m in MINE and m != PRIMARY]
    print(f"{q:<20} {str(rank) if rank else 'ABSENT':<10} {', '.join(others) or '-'}")
    time.sleep(0.4)

print("\nNote: portal search is cached for several hours after a mod update.")
print("Re-run a few hours after shipping a release, not immediately.")
