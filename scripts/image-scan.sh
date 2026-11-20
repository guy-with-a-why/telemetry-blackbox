#!/usr/bin/env bash
# Usage: image-scan.sh [--gate] [--out DIR] IMAGE...
# Scans container images with OSV-Scanner and prints a Markdown table, one row
# per image: its platform, every advisory found, the High or Critical ones and
# how many of those have a fixed version. DIR gets each image's full JSON and
# an SPDX SBOM, named after the image and its platform (ADR 7).
#
# With --gate it fails if any advisory is in a Rust crate. Those come from the
# lockfile, so they're mine to fix. Base-image packages are only reported:
# their fix is a newer base digest, and Dependabot proposes one each week.
set -euo pipefail
cd "$(dirname "$0")/.."

gate=false
out=.
while [[ $# -gt 0 ]]; do
  case $1 in
    --gate)
      gate=true
      shift
      ;;
    --out)
      out=$2
      shift 2
      ;;
    -*)
      echo "unknown option $1" >&2
      exit 2
      ;;
    *) break ;;
  esac
done
if [[ $# -eq 0 ]]; then
  echo "usage: image-scan.sh [--gate] [--out DIR] IMAGE..." >&2
  exit 2
fi
mkdir -p "$out"
# image ignores live beside the root workspace's, in the root osv-scanner.toml
config=()
if [[ -f osv-scanner.toml ]]; then config=(--config osv-scanner.toml); fi

# One entry per advisory, counted once even when it hits several binary
# packages from the same source: its ecosystem, its highest CVSS score and
# whether any of its records names a fixed version.
# shellcheck disable=SC2016 # a jq program, not shell
summary='[ .results[]?.packages[]? | . as $p | ($p.vulnerabilities // []) as $v
  | ($p.groups // [])[] | . as $g
  | { id: $g.ids[0], eco: $p.package.ecosystem,
      sev: ($g.max_severity | tonumber? // 0),
      fix: ([ $v[] | select(.id as $id | $g.ids | index($id))
              | .affected[]?.ranges[]?.events[]? | select(.fixed) ] | length > 0) } ]
  | unique_by(.id)
  | [ length,
      (map(select(.sev >= 7)) | length),
      (map(select(.sev >= 7 and .fix)) | length),
      (map(select(.eco == "crates.io")) | length) ]
  | @tsv'

archive=$(mktemp --suffix .tar)
trap 'rm -f "$archive"' EXIT
status=0
echo "| Image | Platform | Advisories | High or Critical | With a fix | In Rust crates |"
echo "|---|---|---|---|---|---|"
for image in "$@"; do
  docker image inspect "$image" >/dev/null 2>&1 || docker pull -q "$image" >/dev/null
  platform=$(docker image inspect --format '{{.Os}}-{{.Architecture}}' "$image")
  repo=${image%%@*}
  name=$(basename "${repo%:*}")-$platform
  docker save -o "$archive" "$image"
  for format in json spdx-2-3; do
    file=$out/$name.$([[ $format == json ]] && echo json || echo spdx.json)
    rc=0
    osv-scanner scan image --archive "${config[@]}" --all-packages \
      --format "$format" --output "$file" "$archive" >/dev/null 2>&1 || rc=$?
    # 1 means it found advisories, which the table reports. A missing tool also
    # exits 1, so the file has to be there too
    if ((rc > 1)) || [[ ! -s $file ]]; then
      echo "OSV-Scanner couldn't scan $image (exit $rc)" >&2
      exit 1
    fi
  done
  read -r total high fixable crates < <(jq -r "$summary" "$out/$name.json")
  echo "| \`$image\` | $platform | $total | $high | $fixable | $crates |"
  if $gate && ((crates > 0)); then
    echo "$image has $crates advisories in its Rust crates" >&2
    status=1
  fi
done
exit "$status"
