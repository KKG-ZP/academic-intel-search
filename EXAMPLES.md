# Examples

## 1) Search one domain

```bash
bash scripts/bci_search.sh "test-time adaptation EEG motor imagery" "2024-" 20 > /tmp/bci.json
jq '.[0:3]' /tmp/bci.json
```

## 2) Filter + rank

```bash
bash scripts/venue_filter.sh /tmp/bci.json | bash scripts/rank_results.sh - > /tmp/bci_ranked.json
jq '.[0:5] | .[] | {title, venue, citations, quality_score}' /tmp/bci_ranked.json
```

## 3) Merge multi-domain retrieval

```bash
bash scripts/bci_search.sh "calibration-free online adaptation motor imagery" "2024-" 30 > /tmp/bci.json
bash scripts/neuro_search.sh "transcranial focused ultrasound neuromodulation" "2023-" 20 > /tmp/neuro.json
bash scripts/algo_search.sh "transformer foundation model EEG" "2024-" 20 > /tmp/algo.json

jq -s 'add' /tmp/bci.json /tmp/neuro.json /tmp/algo.json > /tmp/all.json
```

## 4) Persist and auto-generate report

```bash
bash scripts/intel_update.sh /tmp/all.json > /tmp/report.md
cat /tmp/report.md | head -40
```

## 5) End-to-end one command

```bash
bash scripts/run_pipeline.sh /tmp/ais-run
ls -lah /tmp/ais-run
```

## 6) Author metrics and BibTeX

```bash
AUTHOR_ID=$(jq -r '.[0].authors[0].id // empty' /tmp/bci.json)
if [[ -n "$AUTHOR_ID" ]]; then
  bash scripts/author_info.sh "$AUTHOR_ID"
fi

DOI=$(jq -r '.[0].doi // empty' /tmp/bci.json)
if [[ -n "$DOI" ]]; then
  bash scripts/doi2bibtex.sh "$DOI"
fi
```
