#!/usr/bin/env python3
"""Fetch bits-orio's Factorio mod pages directly and audit them."""
import re, html, json, subprocess, time, sys, os

MODS = ["multi-team-support", "open-discord-bridge", "diggy", "brave-new-mts",
        "mts-dimension-warp", "land-title-registry", "solo-teams"]

EMOJI = re.compile("[\U0001F000-\U0001FAFF←-⇿⌀-➿⬀-⯿️☀-⛿]")

def fetch(url):
    cb = f"{'&' if '?' in url else '?'}cb={int(time.time()*1000)}"
    r = subprocess.run(["curl","-s","--compressed","-H","Cache-Control: no-cache",
                        "-H","Pragma: no-cache","-A","Mozilla/5.0 (X11; Linux x86_64)",
                        url+cb], capture_output=True, text=True)
    return r.stdout

def text_of(h):
    t = re.sub(r'<script.*?</script>', '', h, flags=re.S)
    t = re.sub(r'<style.*?</style>', '', t, flags=re.S)
    t = re.sub(r'<[^>]+>', ' ', t)
    return re.sub(r'[ \t]+', ' ', html.unescape(t))

def audit(mod):
    h = fetch(f"https://mods.factorio.com/mod/{mod}")
    blob = re.sub(r'\s+', ' ', text_of(h))
    out = {"mod": mod}

    out["version"]   = (re.search(r'Latest Version:\s*([^\s]+\s*\([^)]*\))', blob) or [None,None])[1]
    out["downloads"] = (re.search(r'Downloaded by:\s*([\d,]+)', blob) or [None,None])[1]
    out["created"]   = (re.search(r'Created:\s*(.{0,20}?)\s*Latest', blob) or [None,None])[1]
    out["license"]   = (re.search(r'License:\s*(.{0,30}?)\s*Created:', blob) or [None,None])[1]
    out["source"]    = (re.search(r'Source:\s*(\S+)', blob) or [None,None])[1]
    out["homepage"]  = (re.search(r'Homepage:\s*(\S+)', blob) or [None,None])[1]

    cat = re.search(r'Mod category:\s*([A-Za-z ]+?)\s{2,}|Mod category:\s*([A-Za-z ]+)', blob)
    out["category"] = (cat.group(1) or cat.group(2)).strip() if cat else "NONE SET"
    out["tags"] = sorted(set(re.findall(r'Mod tag:\s*([A-Za-z ]+?)\s+[A-Z]', blob)))

    out["screenshots"] = len(set(re.findall(r'assets-mod\.factorio\.com/assets/([0-9a-f]{40})', h)))

    body = blob.split("users", 1)[-1] if "Downloaded by" in blob else blob
    out["emoji_in_body"] = len(EMOJI.findall(body))

    bad = sorted(set(re.findall(r'href="(https://mods\.factorio\.com/mod/[^"]*\.(?:md|lua|txt)[^"]*)"', h)))
    bad += sorted(set(re.findall(r'href="(https://mods\.factorio\.com/mod/(?:docs|scripts|LICENSE)[^"]*)"', h)))
    out["broken_links"] = sorted(set(bad))

    out["empty_img"] = h.count('src=""') + len(re.findall(r'!\[\]\(<>\)', h))

    sibs = set(re.findall(r'mods\.factorio\.com/mod/([a-zA-Z0-9_-]+)', h))
    out["links_to_siblings"] = sorted(s for s in sibs if s in MODS and s != mod)

    m = re.search(r'AI coding assistants', body)
    out["ai_note_pos_pct"] = round(100*m.start()/max(len(body),1)) if m else None
    out["ai_plea"] = bool(re.search(r'keep the hate|anti-human|rude or disrespectful|keep it kind', body))

    out["summary"] = blob.split("Mod category")[0].strip()[-400:]
    out["body_chars"] = len(body)
    return out

if __name__ == "__main__":
    res = [audit(m) for m in MODS]
    # Write beside this script rather than a hardcoded absolute path.
    dest = os.path.join(os.path.dirname(os.path.abspath(__file__)), "audit.json")
    json.dump(res, open(dest, "w"), indent=2)
    for r in res:
        print("="*70)
        print(f"{r['mod']}  |  v{r['version']}  |  {r['downloads']} users  |  created {r['created']}")
        print(f"  category    : {r['category']}")
        print(f"  tags        : {r['tags'] or 'NONE'}")
        print(f"  license     : {r['license']}")
        print(f"  source      : {r['source']}")
        print(f"  homepage    : {r['homepage']}")
        print(f"  screenshots : {r['screenshots']}")
        print(f"  emoji       : {r['emoji_in_body']}   body {r['body_chars']} chars")
        print(f"  AI note at  : {r['ai_note_pos_pct']}% of page   plea present: {r['ai_plea']}")
        print(f"  siblings    : {r['links_to_siblings'] or 'NONE'}")
        print(f"  broken links: {r['broken_links'] or 'none'}")
        print(f"  empty imgs  : {r['empty_img']}")
    print(f"\nwrote {dest}")
