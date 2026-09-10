# Portfolio tooling

Cross-repo scripts for the bits-orio mod family. They read the live mod portal
and report; neither writes anything.

- `audit.py` — scrapes each mod's portal page and reports category, tags,
  licence, links, emoji count, sibling cross-links and AI-note placement.
- `rank.py`  — reports where each mod ranks in portal search for a list of
  queries. Portal search is cached for hours after an update, so re-run a day
  after shipping, never immediately.

Both live here rather than in each mod repo because they look at the whole
family at once. Run them from this directory.
