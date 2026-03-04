#!/usr/bin/env bash
# BCI domain search via Semantic Scholar with CrossRef fallback
# Usage: bash scripts/bci_search.sh "query" [year_range] [limit]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_ROOT="$(dirname "$SCRIPT_DIR")"

if [[ -f "$SKILL_ROOT/.env" ]]; then
  set -a
  # shellcheck source=/dev/null
  source "$SKILL_ROOT/.env"
  set +a
fi

QUERY="${1:-}"
YEAR_RANGE="${2:-2023-}"
LIMIT="${3:-30}"
ARXIV_THRESHOLD="${ARXIV_CITATION_THRESHOLD:-100}"
MIN_INTERVAL="${S2_MIN_INTERVAL:-1}"

if [[ -z "$QUERY" ]]; then
  echo '{"error":"Usage: bash scripts/bci_search.sh \"query\" [year_range] [limit]"}' >&2
  exit 1
fi

for cmd in jq curl; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "{\"error\":\"$cmd is required\"}" >&2
    exit 1
  fi
done

# Rate limiting
RATE_LIMIT_FILE="/tmp/.s2_rate_limit"
if [[ -f "$RATE_LIMIT_FILE" ]]; then
  last_time=$(cat "$RATE_LIMIT_FILE" 2>/dev/null || echo "0")
  now=$(date +%s)
  elapsed=$((now - last_time))
  if [[ $elapsed -lt $MIN_INTERVAL ]]; then
    sleep $((MIN_INTERVAL - elapsed))
  fi
fi

enhanced_query="$QUERY brain-computer interface BCI motor imagery EEG neural decoding"
encoded_query=$(printf '%s' "$enhanced_query" | jq -sRr @uri)

api_url="https://api.semanticscholar.org/graph/v1/paper/search/bulk"
fields="title,year,authors,venue,journal,citationCount,externalIds,url,abstract,fieldsOfStudy"
params="query=${encoded_query}&limit=${LIMIT}&fields=${fields}"
if [[ -n "$YEAR_RANGE" ]]; then
  params+="&year=${YEAR_RANGE}"
fi

response=$(curl -sS -w "\n%{http_code}" \
  "${api_url}?${params}" \
  ${S2_API_KEY:+-H "x-api-key: $S2_API_KEY"} \
  --max-time 60 || true)

date +%s > "$RATE_LIMIT_FILE"

http_code=$(echo "$response" | tail -n1)
body=$(echo "$response" | sed '$d')

if [[ "$http_code" == "200" ]]; then
  total=$(echo "$body" | jq -r '.total // 0')
  returned=$(echo "$body" | jq -r '.data | length')
  echo "{\"source\":\"semantic_scholar\",\"total\":$total,\"returned\":$returned,\"query\":$(jq -Rn --arg q "$QUERY" '$q')}" >&2

  echo "$body" | jq --arg threshold "$ARXIV_THRESHOLD" '
    [
      .data[]? |
      (
        if (.venue | type) == "string" and (.venue | length) > 0 then .venue
        elif (.journal | type) == "string" and (.journal | length) > 0 then .journal
        elif (.journal | type) == "object" then (.journal.name // "N/A")
        else "N/A"
        end
      ) as $venue |
      (.citationCount // 0) as $cites |
      ((.externalIds.ArXiv? != null) or ($venue | test("(?i)arxiv"))) as $is_arxiv |
      (if $is_arxiv and $cites < ($threshold|tonumber) then "caution"
       elif $is_arxiv and $cites >= ($threshold|tonumber) then "recommended"
       else "normal" end) as $arxiv_status |
      {
        source: "semantic_scholar",
        title: (.title // "N/A"),
        year: (.year // null),
        venue: $venue,
        venue_tier: (
          if ($venue | test("(?i)IEEE.*Neural Systems|Journal of Neural Engineering|NeuroImage|IEEE.*Biomedical Engineering")) then "core"
          elif ($venue | test("(?i)Nature|Science|PNAS|Cell")) then "top"
          else "other"
          end
        ),
        citations: $cites,
        doi: (.externalIds.DOI // null),
        arxiv_id: (.externalIds.ArXiv // null),
        url: (.url // null),
        abstract: (.abstract // ""),
        fields: (.fieldsOfStudy // []),
        is_arxiv: $is_arxiv,
        arxiv_status: $arxiv_status,
        recommendation: (
          if $arxiv_status == "caution" then "⚠️ Low-citation arXiv, review carefully"
          elif $arxiv_status == "recommended" then "✅ High-impact arXiv"
          else "✅ Published source"
          end
        ),
        authors: [
          .authors[]? |
          {name: (.name // "N/A"), id: (.authorId // null)}
        ][0:5]
      }
    ]
  '
  exit 0
fi

if [[ "$http_code" == "429" || "$http_code" =~ ^5 ]]; then
  echo "{\"warning\":\"Semantic Scholar unavailable (HTTP $http_code), fallback to CrossRef\"}" >&2
  bash "$SCRIPT_DIR/crossref_search.sh" "$QUERY" "$LIMIT" "$YEAR_RANGE"
  exit 0
fi

err_msg=$(echo "$body" | jq -r '.message // .error // "Unknown error"' 2>/dev/null || echo "Unknown error")
echo "{\"error\":\"HTTP $http_code: $err_msg\"}" >&2
exit 1
