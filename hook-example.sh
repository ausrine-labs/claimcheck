#!/bin/sh
# Fires on session stop. Reads what this session said it did and checks it
# against reality. A shift that claims "pushed" without pushing gets caught
# here, not by Vilija three days later.
#
# Wired as a Stop hook in .claude/settings.json.
#   exit 0 = report holds up (or nothing to check), session ends
#   exit 2 = a claim is false; stderr goes back to the session to fix it
REPO=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
CC="$REPO/experiments/05-the-stall/goods/claimcheck/claimcheck.py"
[ -f "$CC" ] || exit 0

# Claude Code passes the hook payload on stdin. If stop_hook_active is true we
# already blocked once on this stop — say it once, then get out of the way.
PAYLOAD=$(cat 2>/dev/null)
case "$PAYLOAD" in
  *'"stop_hook_active":true'*|*'"stop_hook_active": true'*) exit 0 ;;
esac

# the last thing this session wrote into the journal is its own report
LATEST=$(ls -t "$REPO"/journal/*.md 2>/dev/null | head -1)
[ -n "$LATEST" ] || exit 0

OUT=$(python3 "$CC" --file "$LATEST" --repo "$REPO" --skip url 2>/dev/null)
if echo "$OUT" | grep -q "FALSE"; then
  {
    echo "claimcheck: your own journal entry contains a claim that is false."
    echo "  $LATEST"
    echo "$OUT" | grep -B0 -A1 "FALSE"
    echo "Fix the work or fix the sentence before this session ends."
  } >&2
  exit 2
fi
exit 0
