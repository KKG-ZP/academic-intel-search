#!/usr/bin/env bash
# Merge, deduplicate, rank, persist, and dispatch tracking
# Usage:
#   bash scripts/intel_update.sh papers.json
#   cat papers.json | bash scripts/intel_update.sh -

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_ROOT="$(dirname "$SCRIPT_DIR")"
WORKSPACE_ROOT="$(dirname "$(dirname "$SKILL_ROOT")")"
INTEL_DIR="${INTEL_DIR:-$WORKSPACE_ROOT/intel}"
DATE="$(date +%Y-%m-%d)"
OUTPUT_JSON="${OUTPUT_JSON:-$INTEL_DIR/data/$DATE.json}"
OUTPUT_MD="${OUTPUT_MD:-$INTEL_DIR/ACADEMIC-INTEL-AUTO.md}"
INPUT_FILE="${1:-}"
DISPATCH_TARGETS="${DISPATCH_TARGETS:-tech_review}"
ENABLE_DISPATCH_TRACKING="${ENABLE_DISPATCH_TRACKING:-1}"

if ! command -v jq >/dev/null 2>&1; then
  echo '{"error":"jq is required"}' >&2
  exit 1
fi

if [[ -z "$INPUT_FILE" ]]; then
  echo '{"error":"Usage: bash scripts/intel_update.sh <papers.json|->"}' >&2
  exit 1
fi

mkdir -p "$(dirname "$OUTPUT_JSON")"
mkdir -p "$(dirname "$OUTPUT_MD")"

TMP_NEW=$(mktemp)
trap 'rm -f "$TMP_NEW"' EXIT

if [[ "$INPUT_FILE" == "-" ]]; then
  cat > "$TMP_NEW"
else
  cat "$INPUT_FILE" > "$TMP_NEW"
fi

if [[ -f "$OUTPUT_JSON" ]]; then
  EXISTING_DATA=$(cat "$OUTPUT_JSON")
else
  EXISTING_DATA='[]'
fi

NEW_DATA=$(cat "$TMP_NEW")

MERGED_DATA=$(jq -s '
  def normalize:
    if type == "array" then .
    elif type == "object" then [.] 
    else []
    end;

  ((.[0] | normalize) + (.[1] | normalize))
  | map(select(
      ((.title // "") != "")
      or ((.doi // "") != "")
      or ((.url // "") != "")
    ))
  | map(.citations = (.citations // 0))
  | unique_by((.doi // .arxiv_id // .title // .url // ""))
  | sort_by(-(.quality_score // 0), -(.citations // 0))
' <(echo "$EXISTING_DATA") <(echo "$NEW_DATA"))

echo "$MERGED_DATA" | jq '.' > "$OUTPUT_JSON"

REPORT=$(echo "$MERGED_DATA" | jq -r --arg date "$DATE" '
  def section($name; $items):
    "## " + $name + "\n" +
    (if ($items | length) == 0 then "- None\n"
     else ($items | map(
       "- " + (.title // "N/A") + " (" + ((.year // "n/a")|tostring) + ", " + (.venue // "N/A") + ", cites: " + ((.citations // 0)|tostring) + ")" +
       "\n  - Source: " + (.source // "N/A") +
       "\n  - DOI: " + (.doi // "N/A") +
       "\n  - URL: " + (.url // "N/A")
     ) | join("\n")) + "\n"
     end);

  "# Academic Intel Auto Report\n\n" +
  "Generated: " + $date + "\n\n" +
  "Total papers in store: " + ((length)|tostring) + "\n\n" +
  section("Top 10 by quality score"; (.[0:10])) + "\n" +
  section("Top venue-tier papers"; ([.[] | select((.venue_tier // "") == "top" or (.venue_tier // "") == "top_ml")][0:10])) + "\n" +
  section("Core venue-tier papers"; ([.[] | select((.venue_tier // "") == "core")][0:10])) + "\n" +
  section("Recommended arXiv papers"; ([.[] | select((.arxiv_status // "") == "recommended")][0:10]))
')

echo "$REPORT" > "$OUTPUT_MD"

DISPATCH_SUMMARY='{}'
if [[ "$ENABLE_DISPATCH_TRACKING" != "0" ]]; then
  if DISPATCH_SUMMARY=$(bash "$SCRIPT_DIR/dispatch_update.sh" "$TMP_NEW" "$DISPATCH_TARGETS" 2>/dev/null); then
    :
  else
    DISPATCH_SUMMARY='{"warning":"dispatch tracking failed"}'
  fi
fi

# Print concise terminal summary
echo "✅ Updated JSON: $OUTPUT_JSON" >&2
echo "✅ Updated report: $OUTPUT_MD" >&2
echo "📊 Papers stored: $(echo "$MERGED_DATA" | jq 'length')" >&2
if [[ "$ENABLE_DISPATCH_TRACKING" != "0" ]]; then
  echo "📬 Dispatch: $DISPATCH_SUMMARY" >&2
fi

# Print report to stdout for piping/review
echo "$REPORT"