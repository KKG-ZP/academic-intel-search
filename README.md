# academic-intel-search

Research-intel skill for BCI/motor imagery decoding, neuro-modulation, and transferable ML methods.

## What it does

- Retrieves papers from Semantic Scholar
- Falls back to CrossRef when Semantic Scholar is rate-limited/unavailable
- Filters by venue quality / citation threshold
- Ranks with a composite `quality_score`
- Persists normalized JSON and generates a markdown brief

## Quick start

```bash
cd ~/.openclaw/workspace/skills/academic-intel-search

# local env (do NOT commit)
cat > .env << 'EOF'
S2_API_KEY="YOUR_SEMANTIC_SCHOLAR_KEY"
ARXIV_CITATION_THRESHOLD=100
S2_MIN_INTERVAL=1
EOF

# run full pipeline
bash scripts/run_pipeline.sh
```

## Core scripts

- `scripts/bci_search.sh`
- `scripts/neuro_search.sh`
- `scripts/algo_search.sh`
- `scripts/crossref_search.sh`
- `scripts/venue_filter.sh`
- `scripts/rank_results.sh`
- `scripts/intel_update.sh`

## Typical manual flow

```bash
bash scripts/bci_search.sh "online adaptation motor imagery" "2024-" 40 > /tmp/bci.json
bash scripts/neuro_search.sh "focused ultrasound neuromodulation" "2023-" 30 > /tmp/neuro.json
bash scripts/algo_search.sh "foundation model EEG time series" "2024-" 30 > /tmp/algo.json

jq -s 'add' /tmp/bci.json /tmp/neuro.json /tmp/algo.json \
  | bash scripts/venue_filter.sh - \
  | bash scripts/rank_results.sh - > /tmp/ranked.json

bash scripts/intel_update.sh /tmp/ranked.json
```

## Outputs

- `intel/data/YYYY-MM-DD.json` (structured store)
- `intel/ACADEMIC-INTEL-AUTO.md` (auto-generated brief)

## Notes

- All search scripts output JSON arrays.
- Status logs are written to `stderr`; machine-readable output is on `stdout`.
- Keep `.env` local; never commit real API keys.
