#!/usr/bin/env bash
# Rank papers with a composite score inspired by citation-assistant
# Usage:
#   bash scripts/rank_results.sh papers.json
#   cat papers.json | bash scripts/rank_results.sh

set -euo pipefail

if ! command -v jq >/dev/null 2>&1; then
  echo '{"error":"jq is required"}' >&2
  exit 1
fi

if [[ -n "${1:-}" && "${1:-}" != "-" ]]; then
  INPUT=$(cat "$1")
else
  INPUT=$(cat)
fi

echo "$INPUT" | jq '
  def normalize:
    if type == "array" then .
    elif type == "object" then [.] 
    else []
    end;

  def venue_score($tier):
    if $tier == "top" then 40
    elif $tier == "top_ml" then 38
    elif $tier == "core" then 30
    else 12
    end;

  def citation_score($c):
    if $c <= 0 then 0
    elif $c >= 300 then 30
    else ($c / 10)
    end;

  def recency_score($y):
    if $y == null then 0
    elif $y >= 2026 then 20
    elif $y >= 2024 then 16
    elif $y >= 2022 then 12
    elif $y >= 2020 then 8
    else 4
    end;

  normalize
  | map(
      (.citations // 0) as $c |
      (.year // null) as $y |
      (.venue_tier // "other") as $vt |
      (.arxiv_status // "normal") as $arxiv_flag |
      . + {
        quality_score: (
          (venue_score($vt)) +
          (citation_score($c)) +
          (recency_score($y)) +
          (if $arxiv_flag == "recommended" then 6 elif $arxiv_flag == "caution" then -6 else 0 end)
        )
      }
    )
  | sort_by(-.quality_score, -.citations)
'