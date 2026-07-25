#!/usr/bin/env bash
# Auto-commit & push on Claude "Stop". No-ops when clean. Never fails the harness.
set -uo pipefail

root="$(git rev-parse --show-toplevel 2>/dev/null)" || exit 0
cd "$root" || exit 0

# Regenerate the standalone PWA index.html from the source fragment.
if [ -f .claude/build-pages.sh ]; then
  bash .claude/build-pages.sh >/dev/null 2>&1 || true
fi

# Nothing changed since last commit -> nothing to push.
if [ -z "$(git status --porcelain)" ]; then
  exit 0
fi

ts="$(date '+%Y-%m-%d %H:%M:%S')"
git add -A
git commit -q -m "Auto-update: $ts" >/dev/null 2>&1 || exit 0

if git push -q origin HEAD >/dev/null 2>&1; then
  printf '{"systemMessage":"✔ Pushed update to GitHub (%s)"}\n' "$ts"
else
  printf '{"systemMessage":"⚠ Committed locally but GitHub push failed (offline or sign-in needed). Run: git push"}\n'
fi
exit 0
