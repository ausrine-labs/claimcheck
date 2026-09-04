#!/bin/bash
# Break claimcheck on purpose, one hole at a time, and confirm the suite bites.
#
# "30 tests pass" is a number. This turns it into evidence: each mutation
# below is a plausible way claimcheck could be wrong, and a suite worth
# keeping must fail for every one of them. A mutation that survives means
# the tests are decoration in that spot.
#
# Half of these push the tool toward calling honest agents liars, which is
# the failure that happened on 2026-08-31. The other half push it toward
# never saying FALSE at all, which is the quieter way to become useless: a
# verifier that cannot accuse catches nothing.
#
#   ./mutate.sh
set -uo pipefail
cd "$(dirname "$0")"

# The backup is checked, not assumed. First run of this script used mktemp,
# which the sandbox refused; ORIG came back empty, every restore silently did
# nothing, ten mutations stacked on top of each other, and the run reported
# "10 caught · 0 survived" while proving nothing at all. That is the same
# defect this whole file exists to test for, committed by the test harness.
ORIG=.mutate-original.py
cp claimcheck.py "$ORIG" || { echo "cannot write a backup here." >&2; exit 1; }
cmp -s "$ORIG" claimcheck.py || { echo "backup is not a copy — refusing to run." >&2; exit 1; }
trap 'cp "$ORIG" claimcheck.py; rm -f "$ORIG"; rm -rf __pycache__' EXIT

restore() {
  cp "$ORIG" claimcheck.py
  cmp -s "$ORIG" claimcheck.py || { echo "restore failed — stopping." >&2; exit 1; }
  rm -rf __pycache__
}

caught=0; survived=0; n=0

mutate() {           # mutate "name" "from" "to"
  n=$((n+1))
  restore
  if ! MUT_FROM=$2 MUT_TO=$3 python3 - <<'PY'
import os, sys
src = open("claimcheck.py").read()
f, t = os.environ["MUT_FROM"], os.environ["MUT_TO"]
if f not in src:
    sys.exit("anchor no longer in claimcheck.py: " + f[:60])
open("claimcheck.py", "w").write(src.replace(f, t, 1))
PY
  then
    printf '  STALE     %s\n' "$1"; survived=$((survived+1)); return
  fi
  if cmp -s "$ORIG" claimcheck.py; then
    printf '  STALE     %s (file unchanged)\n' "$1"; survived=$((survived+1)); return
  fi
  rm -rf __pycache__
  if python3 test_claimcheck.py >/dev/null 2>&1; then
    survived=$((survived+1)); printf '  SURVIVED  %s\n' "$1"
  else
    caught=$((caught+1));    printf '  caught    %s\n' "$1"
  fi
}

echo
echo "mutating claimcheck — each line must be caught by the suite"
echo
echo "-- toward accusing the honest --"

mutate "absent from this checkout is reported FALSE (the 2026-08-31 bug)" \
  '    short = sha[:8]' \
  '    return FALSE, "no commit %s in this repo" % sha
    short = sha[:8]'

mutate "a commit sitting on a remote branch tip is not looked for" \
  '        if tip.startswith(sha.lower()):' \
  '        if False:'

mutate "being behind the remote stops counting as a reason to doubt" \
  '    if missing:' \
  '    if False:'

mutate "an unreachable remote is read as proof of absence" \
  '        return UNVERIFIABLE, ("%s is not in this checkout and %s cannot be "' \
  '        return FALSE, ("%s is not in this checkout and %s cannot be "'

mutate "a request that never arrived is reported as a dead link" \
  '        return UNVERIFIABLE, "no answer (%s)" % str(e)[:40]' \
  '        return FALSE, "no answer (%s)" % str(e)[:40]'

echo
echo "-- toward never accusing anyone --"

mutate "a repo with no remote still gets the benefit of the doubt" \
  '        return FALSE, "no commit %s — not here, and this repo has no remote" % short' \
  '        return UNVERIFIABLE, "no commit %s — not here, and this repo has no remote" % short'

mutate "a checkout that holds everything still refuses to say FALSE" \
  '    return FALSE, ("no commit %s — not here, %s already holds everything this "' \
  '    return UNVERIFIABLE, ("no commit %s — not here, %s already holds everything this "'

mutate "a server answering 404 is downgraded to a blind spot" \
  '        return FALSE, "HTTP %d" % e.code' \
  '        return UNVERIFIABLE, "HTTP %d" % e.code'

echo
echo "-- the detectors underneath --"

mutate "a push claim naming nothing is treated as naming something" \
  '        if branch.lower() in STOPWORDS:' \
  '        if False:'

mutate "a bare push claim stops being a claim at all" \
  '    if not out and re.search(' \
  '    if False and re.search('

restore
echo
printf '%d mutations · %d caught · %d survived\n' "$n" "$caught" "$survived"
[ "$survived" -eq 0 ] || { echo "a surviving mutation is an untested behaviour."; exit 1; }
echo "every hole was caught."
