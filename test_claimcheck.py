#!/usr/bin/env python3
"""Tests for claimcheck's detectors.

The detectors are the whole product: a missed lie is a broken promise, and
a false alarm is worse, because a checker that cries wolf gets switched off.
These tests hold both ends.

    python3 test_claimcheck.py
"""

import sys

import claimcheck as cc


FAILURES = []


def check(name, got, want):
    if got == want:
        print("  ok    %s" % name)
    else:
        print(" FAIL   %s\n          got  %r\n          want %r" % (name, got, want))
        FAILURES.append(name)


def kinds(text):
    """Which claim kinds survive masking and get detected."""
    masked = cc.mask_mentions(text)
    found = []
    for finder, _ in cc.DETECTORS:
        for kind, _quote, _arg in finder(masked):
            if kind not in found:
                found.append(kind)
    return sorted(found)


def branches(text):
    return [arg for _k, _q, arg in cc.find_pushes(cc.mask_mentions(text))]


print("\n-- a plain claim is detected --")
check("commit", kinds("committed as a1b2c3d"), ["commit"])
check("push named", kinds("pushed to dawn"), ["push"])
check("push backticked", branches("pushed to `claimcheck-hook`"), ["claimcheck-hook"])
check("push origin/", branches("pushed to origin/main"), ["main"])
check("clean tree", kinds("the working tree clean"), ["clean"])
check("tests", kinds("all tests pass"), ["tests"])

print("\n-- quoting a claim is not making it --")
check("quoted", kinds('it said "pushed; tree clean" and was wrong'), [])
check("curly quoted", kinds("it said “all tests pass” yesterday"), [])
check("italic example", kinds("*Committed as a1b2c3d. Pushed.*"), [])
check("italic over lines", kinds("*Committed as a1b2c3d.\nTests pass.*"), [])
check("fenced block", kinds("```\ncommitted as a1b2c3d\npushed to main\n```"), [])

print("\n-- emphasis of a real claim survives --")
check("bold", kinds("**pushed to dawn**"), ["push"])
check("bold branch", branches("**pushed to `dawn`**"), ["dawn"])
check("bullet list", kinds("* pushed to dawn\n* tests pass"), ["push", "tests"])

print("\n-- a push claim needs a branch to be a checkable claim --")
check("bare push", branches("pushed everything up"), [None])
check("stopword", branches("pushed to it"), [None])
check("semicolon", branches("pushed; tree clean"), [None])

print("\n-- offsets survive masking (a mask must not shift the text) --")
src = 'a "quoted bit" and *an italic bit* end'
check("length held", len(cc.mask_mentions(src)), len(src))
check("newlines held", cc.mask_mentions("*a\nb*").count("\n"), 1)

print()
if FAILURES:
    print("%d test(s) failed: %s" % (len(FAILURES), ", ".join(FAILURES)))
    sys.exit(1)
print("all tests pass")
