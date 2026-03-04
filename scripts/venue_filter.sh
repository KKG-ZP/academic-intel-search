#!/usr/bin/env bash
# Filter papers by venue quality and citation threshold
# Usage:
#   bash scripts/venue_filter.sh papers.json
#   cat papers.json | bash scripts/venue_filter.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_ROOT="$(dirname "$SCRIPT_DIR")"
DATA_DIR="$SKILL_ROOT/data"
WHITELIST_FILE="${WHITELIST_FILE:-$DATA_DIR/high_impact_venues.txt}"
MIN_CITATIONS="${MIN_CITATIONS:-50}"

if ! command -v jq >/dev/null 2>&1; then
  echo '{"error":"jq is required"}' >&2
  exit 1
fi

if [[ -n "${1:-}" && "${1:-}" != "-" ]]; then
  INPUT_JSON=$(cat "$1")
else
  INPUT_JSON=$(cat)
fi

if [[ -f "$WHITELIST_FILE" ]]; then
  WHITELIST_JSON=$(grep -vE '^\s*#|^\s*$' "$WHITELIST_FILE" | jq -R . | jq -s .)
else
  WHITELIST_JSON='[]'
fi

echo "$INPUT_JSON" | jq --argjson whitelist "$WHITELIST_JSON" --arg min "$MIN_CITATIONS" '
  def normalize:
    if type == "array" then .
    elif type == "object" then [.] 
    else []
    end;

  def venue_in_whitelist($wl):
    ((.venue // "") | ascii_downcase) as $v |
    reduce $wl[] as $w (false; . or ($v | contains(($w | ascii_downcase))));

  (normalize) as $papers |
  [
    $papers[] |
    .citations = (.citations // 0) |
    select(
      ((.venue_tier // "") == "top" or (.venue_tier // "") == "core" or (.venue_tier // "") == "top_ml")
      or ((.arxiv_status // "") == "recommended")
      or ((.citations // 0) >= ($min | tonumber))
      or venue_in_whitelist($whitelist)
    )
  ]
  | unique_by((.doi // .title // .url // ""))
  | sort_by(-(.citations // 0))
'