#!/usr/bin/env bash
# OpenAlex direct search (open citation network)
# Usage: bash scripts/openalex_search.sh "query" [year_range] [limit]

set -euo pipefail

QUERY="${1:-}"
YEAR_RANGE="${2:-2020-}"
LIMIT="${3:-30}"
ARXIV_THRESHOLD="${ARXIV_CITATION_THRESHOLD:-100}"

if [[ -z "$QUERY" ]]; then
  echo '{"error":"Usage: bash scripts/openalex_search.sh \"query\" [year_range] [limit]"}' >&2
  exit 1
fi

for cmd in curl jq python3; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "{\"error\":\"$cmd is required\"}" >&2
    exit 1
  fi
done

ENCODED_QUERY=$(printf '%s' "$QUERY" | jq -sRr @uri)
URL="https://api.openalex.org/works?search=${ENCODED_QUERY}&per-page=${LIMIT}&sort=publication_year:desc"
if [[ -n "${OPENALEX_MAILTO:-}" ]]; then
  URL+="&mailto=${OPENALEX_MAILTO}"
fi

TMP_JSON=$(mktemp)
trap 'rm -f "$TMP_JSON"' EXIT
curl -sS --max-time 60 "$URL" > "$TMP_JSON"

python3 - "$TMP_JSON" "$YEAR_RANGE" "$ARXIV_THRESHOLD" <<'PY'
import json
import re
import sys

json_path = sys.argv[1]
year_range = sys.argv[2]
threshold = int(sys.argv[3]) if len(sys.argv) > 3 else 100

try:
    with open(json_path, "r", encoding="utf-8", errors="ignore") as f:
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


def reconstruct_abstract(inverted_index):
    if not inverted_index:
        return ""
    pos = {}
    for word, idxs in inverted_index.items():
        for i in idxs:
            pos[i] = word
    return " ".join(pos[i] for i in sorted(pos.keys()))


items = []
for w in payload.get("results", []):
    title = (w.get("display_name") or "N/A").strip()
    year = w.get("publication_year")

    if start_year is not None and (year is None or year < start_year):
        continue
    if end_year is not None and (year is None or year > end_year):
        continue

    primary_location = w.get("primary_location") or {}
    source_obj = primary_location.get("source") or {}
    venue = source_obj.get("display_name") or "N/A"
    venue_l = venue.lower()

    if any(k in venue_l for k in ["nature", "science", "cell", "pnas", "lancet", "nejm"]):
        tier = "top"
    elif any(k in venue_l for k in ["ieee", "neurips", "icml", "iclr", "journal"]):
        tier = "core"
    else:
        tier = "other"

    doi_url = w.get("doi")
    doi = re.sub(r"^https?://doi\.org/", "", doi_url, flags=re.I) if doi_url else None

    locations = w.get("locations") or []
    is_arxiv = False
    arxiv_id = None
    for loc in locations:
        src = ((loc.get("source") or {}).get("display_name") or "").lower()
        if "arxiv" in src:
            is_arxiv = True
            lp = loc.get("landing_page_url") or ""
            m = re.search(r"arxiv\.org/(?:abs|pdf)/([^/?#]+)", lp)
            if m:
                arxiv_id = m.group(1)
            break

    citations = int(w.get("cited_by_count") or 0)
    if is_arxiv and citations >= threshold:
        arxiv_status = "recommended"
    elif is_arxiv:
        arxiv_status = "caution"
    else:
        arxiv_status = "normal"

    if arxiv_status == "recommended":
        recommendation = "✅ High-impact arXiv indexed in OpenAlex"
    elif arxiv_status == "caution":
        recommendation = "⚠️ arXiv preprint indexed in OpenAlex"
    else:
        recommendation = "✅ OpenAlex indexed publication"

    authors = []
    for a in (w.get("authorships") or [])[:5]:
        au = a.get("author") or {}
        name = (au.get("display_name") or "").strip()
        if name:
            authors.append({"name": name, "id": au.get("id")})

    concepts = [c.get("display_name") for c in (w.get("concepts") or [])[:5] if c.get("display_name")]

    url = primary_location.get("landing_page_url") or w.get("id")
    abstract = reconstruct_abstract(w.get("abstract_inverted_index"))

    items.append(
        {
            "source": "openalex",
            "title": title,
            "year": year,
            "venue": venue,
            "venue_tier": tier,
            "citations": citations,
            "doi": doi,
            "arxiv_id": arxiv_id,
            "url": url,
            "abstract": abstract,
            "fields": concepts,
            "is_arxiv": is_arxiv,
            "arxiv_status": arxiv_status,
            "recommendation": recommendation,
            "authors": authors,
        }
    )

print(json.dumps(items, ensure_ascii=False))
PY