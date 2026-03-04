---
name: academic-intel-search
description: Multi-source research-intel skill for BCI/motor-imagery decoding, neuro-modulation, and transferable ML methods. Use when you need (1) paper retrieval from Semantic Scholar/CrossRef/arXiv/PubMed/OpenAlex, (2) quality filtering and ranking, (3) structured persistence to intel data files, and (4) deduplicated downstream dispatch tracking via catalog + dual queues.
---

# Academic Intel Search

Use this skill to run a reproducible literature retrieval-and-curation pipeline for BCI-focused research.

## Core rules

1. Run only scripts in `scripts/` (do not hand-write ad-hoc curl flows).
2. Use multi-source retrieval; keep schema normalized across sources.
3. Keep output structured: JSON as source-of-truth, Markdown as readable report.
4. Deduplicate by DOI/arXiv/title/url before persistence or dispatch.
5. Track dispatch status to avoid sending the same paper to the same downstream stage twice.

## Scripts

Retrieval:
- `scripts/bci_search.sh` — BCI/motor imagery retrieval (Semantic Scholar + CrossRef fallback)
- `scripts/neuro_search.sh` — neuro-modulation retrieval (Semantic Scholar + CrossRef fallback)
- `scripts/algo_search.sh` — algorithm transfer retrieval (Semantic Scholar + CrossRef fallback)
- `scripts/arxiv_search.sh` — arXiv API direct retrieval
- `scripts/pubmed_search.sh` — PubMed API direct retrieval
- `scripts/openalex_search.sh` — OpenAlex API direct retrieval
- `scripts/crossref_search.sh` — fallback retrieval source

Curation:
- `scripts/venue_filter.sh` — venue + citation filtering
- `scripts/rank_results.sh` — composite quality scoring

Persistence + dispatch:
- `scripts/intel_update.sh` — merge + persist + markdown report + dispatch tracking hook
- `scripts/dispatch_update.sh` — maintain `catalog.json` + dual queue files + dispatch status fields
- `scripts/run_pipeline.sh` — one-shot end-to-end pipeline

Utilities:
- `scripts/author_info.sh` — Semantic Scholar author metrics
- `scripts/doi2bibtex.sh` — DOI to BibTeX

## Quick workflow

```bash
# 1) Run end-to-end
bash scripts/run_pipeline.sh

# 2) Or custom flow
bash scripts/bci_search.sh "online adaptation motor imagery" "2024-" 30 > /tmp/bci.json
bash scripts/arxiv_search.sh "motor imagery BCI" "2023-" 30 > /tmp/arxiv.json
bash scripts/pubmed_search.sh "focused ultrasound neuromodulation" "2020-" 30 > /tmp/pubmed.json
bash scripts/openalex_search.sh "brain computer interface adaptation" "2020-" 30 > /tmp/openalex.json

jq -s 'add' /tmp/bci.json /tmp/arxiv.json /tmp/pubmed.json /tmp/openalex.json \
  | bash scripts/venue_filter.sh - \
  | bash scripts/rank_results.sh - > /tmp/ranked.json

DISPATCH_TARGETS=tech_review bash scripts/intel_update.sh /tmp/ranked.json
```

## Output contract

Default paths (override via env vars):

- `intel/data/YYYY-MM-DD.json` — merged structured store
- `intel/ACADEMIC-INTEL-AUTO.md` — auto brief
- `intel/catalog.json` — canonical deduped catalog with dispatch status fields
- `intel/dispatch/tech-review-queue.jsonl` — queue for downstream technical review stage
- `intel/dispatch/strategy-review-queue.jsonl` — queue for downstream strategy/synthesis stage

Catalog dispatch fields:
- `dispatch_status.sent_to_tech_review`
- `dispatch_status.sent_to_tech_review_at`
- `dispatch_status.sent_to_strategy_review`
- `dispatch_status.sent_to_strategy_review_at`

## Dispatch control

- Default `DISPATCH_TARGETS=tech_review`
- Multi-target: `DISPATCH_TARGETS=tech_review,strategy_review`
- Disable tracking: `ENABLE_DISPATCH_TRACKING=0`

## Environment

Create a local `.env` (not committed):

```bash
S2_API_KEY="YOUR_SEMANTIC_SCHOLAR_KEY"
ARXIV_CITATION_THRESHOLD=100
S2_MIN_INTERVAL=1
NCBI_API_KEY=""         # optional
OPENALEX_MAILTO=""      # optional, polite API usage
```

## Validation checklist

- Search scripts return **JSON array** (not mixed logs).
- `venue_filter.sh` accepts object/array/stdin.
- `rank_results.sh` adds `quality_score` and sorts descending.
- `intel_update.sh` writes JSON + markdown report.
- `dispatch_update.sh` updates catalog and queues without duplicate same-target dispatch.
