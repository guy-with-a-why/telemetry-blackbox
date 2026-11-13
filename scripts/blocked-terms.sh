#!/usr/bin/env bash
# Fails if a blocked term appears in tracked files, commit messages, or issue
# and pull request text. Terms come from $BLOCKED_TERMS (a CI secret) or a
# git-ignored .blocked-terms file, one per line. Matches are reported by
# location only, so the terms never reach a log.
set -euo pipefail

terms=$(mktemp)
trap 'rm -f "$terms"' EXIT

if [[ -n "${BLOCKED_TERMS:-}" ]]; then
  printf '%s\n' "$BLOCKED_TERMS" >"$terms"
elif [[ -f .blocked-terms ]]; then
  cp .blocked-terms "$terms"
elif [[ -n "${CI:-}" ]]; then
  echo "blocked-terms: BLOCKED_TERMS is not set" >&2
  exit 1
else
  echo "blocked-terms: no .blocked-terms file, skipping"
  exit 0
fi
sed -i '/^[[:space:]]*$/d' "$terms" # a blank line would match everything

found=0
matches() { grep -qiF -f "$terms"; }

# GitHub adds a trailer crediting the release App when it squash-merges
# release-please's pull request. It names a bot, not a person, and release
# tags point at those commits, so they can't be rewritten.
release_bot='^[[:alnum:]-]+: telemetry-blackbox-release\[bot\] <356374965\+telemetry-blackbox-release\[bot\]@users\.noreply\.github\.com>$'

if files=$(git grep -liF -f "$terms"); then
  printf 'blocked term in file: %s\n' $files
  found=1
fi

for commit in $(git rev-list --all); do
  if git log -1 --format=%B "$commit" | grep -vE "$release_bot" | matches; then
    echo "blocked term in the message of commit ${commit:0:7}"
    found=1
  fi
done

if [[ -n "${GH_TOKEN:-}" ]] || gh auth status >/dev/null 2>&1; then
  if text=$(gh api --paginate "repos/{owner}/{repo}/issues?state=all&per_page=100" \
    --jq '.[] | "\(.number)\t\(.title) \(.body // "")"' 2>/dev/null); then
    for number in $(printf '%s\n' "$text" | grep -iF -f "$terms" | cut -f1); do
      echo "blocked term in issue or pull request #$number"
      found=1
    done
  elif [[ -n "${CI:-}" ]]; then
    echo "blocked-terms: could not read issues" >&2
    exit 1
  fi
fi

if ((found)); then
  exit 1
fi
echo "blocked-terms: clean"
