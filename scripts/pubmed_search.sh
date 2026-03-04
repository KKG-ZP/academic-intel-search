#!/usr/bin/env bash
# PubMed direct search (biomedical)
# Usage: bash scripts/pubmed_search.sh "query" [year_range] [limit]

set -euo pipefail

QUERY="${1:-}"
YEAR_RANGE="${2:-2020-}"
LIMIT="${3:-30}"

if [[ -z "$QUERY" ]]; then
  echo '{"error":"Usage: bash scripts/pubmed_search.sh \"query\" [year_range] [limit]"}' >&2
  exit 1
fi

for cmd in curl jq python3; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "{\"error\":\"$cmd is required\"}" >&2
    exit 1
  fi
done

ENCODED_QUERY=$(printf '%s' "$QUERY" | jq -sRr @uri)
ESEARCH_URL="https://eutils.ncbi.nlm.nih.gov/entrez/eutils/esearch.fcgi?db=pubmed&retmode=json&retmax=${LIMIT}&sort=pub+date&term=${ENCODED_QUERY}"
if [[ -n "${NCBI_API_KEY:-}" ]]; then
  ESEARCH_URL+="&api_key=${NCBI_API_KEY}"
fi

TMP_ESEARCH=$(mktemp)
TMP_ESUMMARY=$(mktemp)
trap 'rm -f "$TMP_ESEARCH" "$TMP_ESUMMARY"' EXIT

curl -sS --max-time 60 "$ESEARCH_URL" > "$TMP_ESEARCH"

IDS=$(jq -r '.esearchresult.idlist // [] | join(",")' "$TMP_ESEARCH" 2>/dev/null || echo "")
if [[ -z "$IDS" ]]; then
  echo "[]"
  exit 0
fi

ESUMMARY_URL="https://eutils.ncbi.nlm.nih.gov/entrez/eutils/esummary.fcgi?db=pubmed&retmode=json&id=${IDS}"
if [[ -n "${NCBI_API_KEY:-}" ]]; then
  ESUMMARY_URL+="&api_key=${NCBI_API_KEY}"
fi

curl -sS --max-time 60 "$ESUMMARY_URL" > "$TMP_ESUMMARY"

python3 - "$TMP_ESUMMARY" "$YEAR_RANGE" <<'PY'
import json
import re
import sys

summary_path = sys.argv[1]
year_range = sys.argv[2]

try:
    with open(summary_path, "r", encoding="utf-8", errors="ignore") as f:
        payload = json.load(f)
except Exception:
    print("[]")
    sys.exit(0)

start_year = None
end_year = None
if year_range:
    if "-" in year_range:
        left, right = year_range.split("-", 1)
        start_year = int(left) if left.strip().isdigit() else None
        end_year = int(right) if right.strip().isdigit() else None
    elif year_range.isdigit():
        start_year = int(year_range)
        end_year = int(year_range)

result = payload.get("result", {})
uids = result.get("uids", [])
items = []

for uid in uids:
    rec = result.get(uid, {})
    title = (rec.get("title") or "N/A").strip()
    pubdate = rec.get("pubdate") or ""
    year = None
    m = re.search(r"(19|20)\d{2}", pubdate)
    if m:
        year = int(m.group(0))

    if start_year is not None and (year is None or year < start_year):
        continue
    if end_year is not None and (year is None or year > end_year):
        continue

    doi = None
    for aid in rec.get("articleids", []) or []:
        if (aid.get("idtype") or "").lower() == "doi":
            doi = aid.get("value")
            break

    venue = rec.get("fulljournalname") or rec.get("source") or "PubMed"
    venue_l = venue.lower()
    if any(k in venue_l for k in ["nature", "science", "cell", "pnas", "lancet", "nejm"]):
        tier = "top"
    elif any(k in venue_l for k in ["ieee", "journal", "neuroscience", "biomedical"]):
        tier = "core"
    else:
        tier = "other"

    authors = []
    for a in (rec.get("authors") or [])[:5]:
        name = (a.get("name") or "").strip()
        if name:
            authors.append({"name": name, "id": None})

    pmcref = rec.get("pmcrefcount")
    citations = int(pmcref) if isinstance(pmcref, int) else 0

    items.append(
        {
            "source": "pubmed",
            "title": title,
            "year": year,
            "venue": venue,
            "venue_tier": tier,
            "citations": citations,
            "doi": doi,
            "arxiv_id": None,
            "url": f"https://pubmed.ncbi.nlm.nih.gov/{uid}/",
            "abstract": "",
            "fields": ["Medicine", "Biomedical"],
            "is_arxiv": False,
            "arxiv_status": "normal",
            "recommendation": "✅ Indexed biomedical literature",
            "authors": authors,
        }
    )

print(json.dumps(items, ensure_ascii=False))
PY