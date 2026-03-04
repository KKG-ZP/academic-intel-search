# academic-intel-search

Research-intel skill for BCI/motor-imagery decoding, neuro-modulation, and transferable ML methods.

## What it does

- Retrieves papers from Semantic Scholar, arXiv, PubMed, and OpenAlex
- Uses CrossRef as fallback when Semantic Scholar is unavailable
- Filters by venue quality / citation threshold
- Ranks with a composite `quality_score`
- Persists normalized JSON and generates a markdown brief
- Maintains `catalog.json` + dual dispatch queues with status fields to avoid duplicate downstream dispatch

## Quick start

```bash
cd ~/.openclaw/workspace/skills/academic-intel-search

# local env (do NOT commit)
cat > .env << 'EOF'
S2_API_KEY="YOUR_SEMANTIC_SCHOLAR_KEY"
ARXIV_CITATION_THRESHOLD=100
S2_MIN_INTERVAL=1
NCBI_API_KEY=""
OPENALEX_MAILTO=""
EOF

# run full pipeline (default dispatch target: tech_review)
bash scripts/run_pipeline.sh
```

## Core scripts

Retrieval:
- `scripts/bci_search.sh`
- `scripts/neuro_search.sh`
- `scripts/algo_search.sh`
- `scripts/arxiv_search.sh`
- `scripts/pubmed_search.sh`
- `scripts/openalex_search.sh`
- `scripts/crossref_search.sh`

Curation:
- `scripts/venue_filter.sh`
- `scripts/rank_results.sh`

Persistence/dispatch:
- `scripts/intel_update.sh`
- `scripts/dispatch_update.sh`
- `scripts/run_pipeline.sh`

## Typical manual flow

```bash
bash scripts/bci_search.sh "online adaptation motor imagery" "2024-" 40 > /tmp/bci.json
bash scripts/arxiv_search.sh "motor imagery BCI online adaptation" "2023-" 30 > /tmp/arxiv.json
bash scripts/pubmed_search.sh "focused ultrasound neuromodulation" "2020-" 30 > /tmp/pubmed.json
bash scripts/openalex_search.sh "brain computer interface adaptation" "2020-" 30 > /tmp/openalex.json

jq -s 'add' /tmp/bci.json /tmp/arxiv.json /tmp/pubmed.json /tmp/openalex.json \
  | bash scripts/venue_filter.sh - \
  | bash scripts/rank_results.sh - > /tmp/ranked.json

# default: dispatch to tech_review queue only
DISPATCH_TARGETS=tech_review bash scripts/intel_update.sh /tmp/ranked.json
```

## Outputs

- `intel/data/YYYY-MM-DD.json` (structured store)
- `intel/ACADEMIC-INTEL-AUTO.md` (auto-generated brief)
- `intel/catalog.json` (deduped catalog with dispatch status fields)
- `intel/dispatch/tech-review-queue.jsonl`
- `intel/dispatch/strategy-review-queue.jsonl`

## Dispatch behavior

- Same paper will not be queued twice for the same target.
- Targets:
  - `tech_review`
  - `strategy_review`
- Multi-target example:

```bash
DISPATCH_TARGETS=tech_review,strategy_review bash scripts/intel_update.sh /tmp/ranked.json
```
