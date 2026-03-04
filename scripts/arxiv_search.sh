#!/usr/bin/env bash
# arXiv API direct search
# Usage: bash scripts/arxiv_search.sh "query" [year_range] [limit]

set -euo pipefail

QUERY="${1:-}"
YEAR_RANGE="${2:-2023-}"
LIMIT="${3:-30}"
ARXIV_THRESHOLD="${ARXIV_CITATION_THRESHOLD:-100}"

if [[ -z "$QUERY" ]]; then
  echo '{"error":"Usage: bash scripts/arxiv_search.sh \"query\" [year_range] [limit]"}' >&2
  exit 1
fi

for cmd in curl python3 jq; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "{\"error\":\"$cmd is required\"}" >&2
    exit 1
  fi
done

ENCODED_QUERY=$(printf '%s' "$QUERY" | jq -sRr @uri)
URL="https://export.arxiv.org/api/query?search_query=all:${ENCODED_QUERY}&start=0&max_results=${LIMIT}&sortBy=submittedDate&sortOrder=descending"

TMP_XML=$(mktemp)
trap 'rm -f "$TMP_XML"' EXIT

if ! curl -sS --max-time 60 "$URL" > "$TMP_XML"; then
  URL_HTTP="${URL/https:\/\/export.arxiv.org/http:\/\/export.arxiv.org}"
  curl -sS --max-time 60 "$URL_HTTP" > "$TMP_XML" || {
    echo "[]"
    exit 0
  }
fi

if [[ ! -s "$TMP_XML" ]]; then
  echo "[]"
  exit 0
fi

python3 - "$TMP_XML" "$YEAR_RANGE" "$ARXIV_THRESHOLD" <<'PY'
import json
import re
import sys
import xml.etree.ElementTree as ET

xml_path = sys.argv[1]
year_range = sys.argv[2]
threshold = int(sys.argv[3]) if len(sys.argv) > 3 else 100

with open(xml_path, "r", encoding="utf-8", errors="ignore") as f:
    xml_text = f.read()

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

ns = {
    "atom": "http://www.w3.org/2005/Atom",
    "arxiv": "http://arxiv.org/schemas/atom",
}

try:
    root = ET.fromstring(xml_text)
except ET.ParseError:
    print("[]")
    sys.exit(0)

results = []
for entry in root.findall("atom:entry", ns):
    title = (entry.findtext("atom:title", default="", namespaces=ns) or "").strip()
    title = re.sub(r"\s+", " ", title)
    summary = (entry.findtext("atom:summary", default="", namespaces=ns) or "").strip()
    summary = re.sub(r"\s+", " ", summary)
    published = entry.findtext("atom:published", default="", namespaces=ns)
    year = None
    if published and len(published) >= 4 and published[:4].isdigit():
        year = int(published[:4])

    if start_year is not None and (year is None or year < start_year):
        continue
    if end_year is not None and (year is None or year > end_year):
        continue

    id_url = (entry.findtext("atom:id", default="", namespaces=ns) or "").strip()
    arxiv_id = id_url.rsplit("/", 1)[-1] if id_url else None

    doi = None
    doi_el = entry.find("arxiv:doi", ns)
    if doi_el is not None and doi_el.text:
        doi = doi_el.text.strip()

    cats = [c.attrib.get("term", "") for c in entry.findall("atom:category", ns)]
    cats = [c for c in cats if c]

    authors = []
    for a in entry.findall("atom:author", ns)[:5]:
        name = (a.findtext("atom:name", default="", namespaces=ns) or "").strip()
        if name:
            authors.append({"name": name, "id": None})

    citations = 0
    arxiv_status = "recommended" if citations >= threshold else "caution"

    results.append(
        {
            "source": "arxiv_api",
            "title": title or "N/A",
            "year": year,
            "venue": "arXiv",
            "venue_tier": "other",
            "citations": citations,
            "doi": doi,
            "arxiv_id": arxiv_id,
            "url": id_url or None,
            "abstract": summary,
            "fields": cats,
            "is_arxiv": True,
            "arxiv_status": arxiv_status,
            "recommendation": "⚠️ Preprint, verify with peer-reviewed version when available",
            "authors": authors,
        }
    )

print(json.dumps(results, ensure_ascii=False))
PY