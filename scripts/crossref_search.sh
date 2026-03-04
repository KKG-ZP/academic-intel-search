#!/usr/bin/env bash
# CrossRef fallback search
# Usage: bash scripts/crossref_search.sh "query" [limit] [year_range]

set -euo pipefail

QUERY="${1:-}"
LIMIT="${2:-20}"
YEAR_RANGE="${3:-}"

if [[ -z "$QUERY" ]]; then
  echo '{"error":"Usage: bash scripts/crossref_search.sh \"query\" [limit] [year_range]"}' >&2
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo '{"error":"jq is required"}' >&2
  exit 1
fi

ENCODED_QUERY=$(printf '%s' "$QUERY" | jq -sRr @uri)

FILTER_PARAM=""
if [[ -n "$YEAR_RANGE" ]]; then
  # Supports forms like 2023- or 2020-2024
  START_YEAR="${YEAR_RANGE%%-*}"
  END_YEAR="${YEAR_RANGE#*-}"

  if [[ -n "$START_YEAR" ]]; then
    FILTER_PARAM="from-pub-date:${START_YEAR}-01-01"
  fi

  if [[ -n "$END_YEAR" && "$END_YEAR" != "$YEAR_RANGE" ]]; then
    if [[ -n "$FILTER_PARAM" ]]; then
      FILTER_PARAM+=",until-pub-date:${END_YEAR}-12-31"
    else
      FILTER_PARAM="until-pub-date:${END_YEAR}-12-31"
    fi
  fi
fi

URL="https://api.crossref.org/works?query=${ENCODED_QUERY}&rows=${LIMIT}&select=DOI,title,author,published-print,published-online,container-title,is-referenced-by-count,URL"
if [[ -n "$FILTER_PARAM" ]]; then
  URL+="&filter=${FILTER_PARAM}"
fi

RESPONSE=$(curl -sS --max-time 30 "$URL" || true)

if [[ -z "$RESPONSE" ]]; then
  echo '{"error":"CrossRef request failed"}' >&2
  exit 1
fi

echo "$RESPONSE" | jq '
  [
    .message.items[]? |
    (if ((.title // []) | length) > 0 then .title[0] else "N/A" end) as $title |
    (if ((."container-title" // []) | length) > 0 then ."container-title"[0] else "N/A" end) as $venue |
    ((.DOI // "") | ascii_downcase | contains("arxiv")) as $is_arxiv |
    {
      source: "crossref",
      title: $title,
      year: ((."published-print"."date-parts"[0][0] // ."published-online"."date-parts"[0][0]) // null),
      venue: $venue,
      venue_tier: "other",
      citations: (."is-referenced-by-count" // 0),
      doi: (.DOI // null),
      arxiv_id: null,
      url: (.URL // null),
      abstract: "",
      fields: [],
      is_arxiv: $is_arxiv,
      arxiv_status: (if $is_arxiv then "caution" else "normal" end),
      recommendation: (if $is_arxiv then "⚠️ Preprint candidate from fallback source" else "✅ Fallback result" end),
      authors: [
        .author[]? |
        {name: (((.given // "") + " " + (.family // "")) | gsub("^\\s+|\\s+$";"")), id: null}
      ][0:5]
    }
  ]
'