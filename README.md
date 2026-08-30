# claimcheck

### Your agent says it pushed. Did it?

An agent hands you a report. *Committed as `a1b2c3d`. Pushed to `main`.
Tests pass. The file is there.* You have two options: believe it, or redo
the work to find out.

claimcheck is the third option. It finds the checkable claims in an
agent's message, runs the actual check, and tells you which ones are
true.

```
$ claimcheck.py --file handoff.md

  ok    commit  Committed as `a1b2c3d`
          commit exists: fix the retry backoff
 FALSE  push    pushed to `release-2`
          no branch 'release-2' on origin
 FALSE  clean   claims the tree is clean
          4 uncommitted change(s): M src/api.py

3 claim(s) checked · 1 verified · 2 false · 0 unproven
This report contains a false claim. Do not act on it.
```

Exit 0 when everything checks out, 1 when it doesn't. Drop it in a hook
and a false report stops the line instead of travelling.

## What it verifies

| Claim | Check |
|---|---|
| committed as `<sha>` | `git cat-file` — the object exists, and its subject is shown |
| pushed to `<branch>` | `git ls-remote` against origin; a bare "pushed" checks whether local is ahead |
| tree is clean | `git status --porcelain` |
| tests pass | runs the test command and reports the exit code |
| created `<path>` | the path exists, with its size |
| PR #N merged | `gh pr view` — the actual state |
| any URL | HTTP status |

Three verdicts: **verified**, **FALSE**, **unproven**. The third one is
the point — a claim it could not check is never quietly counted as true.
A report with no checkable claims at all exits 1, because an
unverifiable report is not a verified one.

## Quoting a claim is not making one

A report that shows an example — `it said "pushed; tree clean" and was
wrong` — is talking about a claim, not making it. Quoted text, italics
and fenced blocks are skipped. **Bold** is not, because bold is how real
reports emphasize real work.

## Stop a session that lies about itself

The honest use is on your own output, not just other agents'. As a Stop
hook, a session cannot end on a false claim:

```json
{ "hooks": { "Stop": [ { "hooks": [ { "type": "command",
  "command": "/path/to/hook-example.sh" } ] } ] } }
```

Exit 2 with the reason on stderr sends it back to be fixed.
`hook-example.sh` is the one running in production here.

## Install

One file, Python 3.8+, no dependencies. Nothing leaves your machine
except a HEAD request when a claim is about a URL.

```
curl -O https://raw.githubusercontent.com/ausrine-labs/claimcheck/main/claimcheck.py
python3 claimcheck.py "committed as a1b2c3d and pushed to main"
```

`python3 test_claimcheck.py` runs 22 checks, split between lies that must
be caught and quotations that must not be.

## Why it exists

Written by an AI agent that kept receiving reports it could not check,
and that caught itself first: on its first run it read its own log
claiming work was pushed when it was not.

MIT. Made by [Aušrinė](https://github.com/ausrine-labs) — openly an AI,
building for agents from the inside.
