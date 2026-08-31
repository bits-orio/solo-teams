
## Factorio mod portal — search rules, corrected by measurement

These supersede the earlier "search indexing rules" where they conflict. Each was
established by changing something live and measuring the result, not by reasoning.

### The search index re-indexes in about 90 seconds

The earlier guidance said to wait a day before re-running `rank.py`. That is wrong
and it costs a whole feedback cycle. Two separate things were being conflated:

- The **read API** (`/api/mods/<name>/full`) IS cached. Reading it right after a
  sync returns the previous page. Defeat it with a throwaway query parameter —
  `tools/portal_check.py` and `rank.py` both already do this.
- The **search index** re-indexes within about 90 seconds of an `edit_details`
  sync. Measured by polling every 25s after a title change: rank held at #12
  through t+75s, was #2 by t+100s, stable thereafter.

So: after any title or summary change, re-measure immediately. A rank that has not
moved within a few minutes has not moved. Do not wait overnight "to let it settle".

This makes portal copy cheaply A/B testable. Change it, measure, keep or revert in
one sync. **Prefer measuring over arguing** — an afternoon of debate about a title
was settled in 90 seconds by shipping one and looking.

### Position within the title is a ranking factor, and a strong one

Confirmed, not hypothesised. Moving the single word "Multiplayer" from position
five to position one in multi-team-support's title moved it from **#12 to #2** on
the query "multiplayer". Nothing else changed: same summary, same tokens, same
downloads, and all twelve other tracked queries held their positions exactly.

At #2 it now outranks oarc-mod, which has roughly 8x its downloads. So title
position outweighs a large popularity gap. Put the term you care about at the FRONT
of the title, not trailing after a subtitle dash.

### "Generic single tokens are unwinnable" was too pessimistic

The real rule is narrower: a generic token is unwinnable **from the summary**, but
very winnable **from the title**, and popularity is only a weak tiebreaker.

On "multiplayer", every mod on page one carried the word in its TITLE, none ranked
without it there, and mods with 7 and 24 downloads outranked a 939-download mod.

Before writing off a term, count how many mods hold it in an INTERNAL NAME:
  - three or fewer → winnable from the summary alone (mts, collapse, gridlocked,
    redmew, cave all turned out to be here, and all now rank)
  - many, but they win via TITLE not name → winnable by putting it in the title,
    early (multiplayer: ABSENT to #2)
  - many, holding it in internal names, led by a high-download mod → genuinely
    lost; accept it and say so (oarc: 12 names led by oarc-mod at 7k. It sat at #14
    through four separate rewrites. Stop spending on it.)

### Multi-token phrases are not automatically distinctive

A phrase wins from the summary only if its TOKENS are uncontested, not merely
because it has several words. "brave new oarc" went to #4 from the summary because
those tokens are rare. "construction robots" stayed ABSENT from the same summary
because both tokens are common across bot-related mod names. Count the contest on
each token before assuming a phrase will carry.

### Never delete a search term in a rewrite

Already in the rules, and it was still violated: a summary rewrite dropped
"multiplayer", which the previous summary carried. Before shipping any rewritten
summary, diff the token set against the current live one and confirm nothing was
lost without a deliberate replacement.
