---
name: academic-intel-search
description: Semantic Scholar + CrossRef research-intel skill for BCI/motor-imagery decoding, neuro-modulation, and transferable ML methods. Use when you need (1) paper retrieval, (2) quality filtering/ranking, (3) structured JSON updates to intel/data/YYYY-MM-DD.json, or (4) auto-generated markdown research briefs.
---

# Academic Intel Search

Use this skill to run a reproducible literature retrieval-and-curation pipeline for BCI-focused research.

## Core rules

1. Run only scripts in `scripts/` (do not hand-write ad-hoc curl flows).
2. Prefer Semantic Scholar; fallback to CrossRef on 429/5xx.
3. Keep output structured: JSON as source-of-truth, Markdown as readable report.
4. Deduplicate by DOI/title/url before persistence.
5. Keep high-signal papers (venue tier, citations, recency, quality score).

## Scripts

- `scripts/bci_search.sh` — BCI/motor imagery retrieval
- `scripts/neuro_search.sh` — neuro-modulation retrieval
- `scripts/algo_search.sh` — algorithm transfer retrieval
- `scripts/crossref_search.sh` — fallback retrieval source
- `scripts/venue_filter.sh` — venue + citation filtering
- `scripts/rank_results.sh` — composite quality scoring
- `scripts/intel_update.sh` — merge + persist + markdown report
- `scripts/run_pipeline.sh` — one-shot end-to-end pipeline
- `scripts/author_info.sh` — Semantic Scholar author metrics
- `scripts/doi2bibtex.sh` — DOI to BibTeX

## Quick workflow

```bash
# 1) Retrieve
bash scripts/bci_search.sh "calibration-free online adaptation motor imagery" "2024-" 30 > /tmp/bci.json
bash scripts/neuro_search.sh "transcranial focused ultrasound neuromodulation" "2023-" 20 > /tmp/neuro.json
bash scripts/algo_search.sh "foundation model transformer time-series EEG" "2024-" 20 > /tmp/algo.json

# 2) Merge + filter + rank
jq -s 'add' /tmp/bci.json /tmp/neuro.json /tmp/algo.json \
  | bash scripts/venue_filter.sh - \
  | bash scripts/rank_results.sh - > /tmp/ranked.json

# 3) Persist + generate report
bash scripts/intel_update.sh /tmp/ranked.json
```

## Output contract

Default paths (override by env vars if needed):

- `intel/data/YYYY-MM-DD.json` (merged structured store)
- `intel/ACADEMIC-INTEL-AUTO.md` (auto brief)

## Environment

Create a local `.env` (not committed):

```bash
S2_API_KEY="YOUR_SEMANTIC_SCHOLAR_KEY"
ARXIV_CITATION_THRESHOLD=100
S2_MIN_INTERVAL=1
```

## Validation checklist

- Search scripts return **JSON array** (not mixed logs).
- `venue_filter.sh` accepts both object/array/stdin.
- `rank_results.sh` adds `quality_score` and sorts descending.
- `intel_update.sh` writes JSON + markdown report successfully.
