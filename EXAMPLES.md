# Examples

## 1) Search one source

```bash
bash scripts/arxiv_search.sh "motor imagery BCI online adaptation" "2023-" 10 > /tmp/arxiv.json
jq '.[0:3] | .[] | {title, year, source, arxiv_id}' /tmp/arxiv.json
```

## 2) Search biomedical source

```bash
bash scripts/pubmed_search.sh "focused ultrasound neuromodulation" "2020-" 10 > /tmp/pubmed.json
jq '.[0:3] | .[] | {title, year, venue, source}' /tmp/pubmed.json
```

## 3) Search open citation network

```bash
bash scripts/openalex_search.sh "brain computer interface adaptation" "2020-" 10 > /tmp/openalex.json
jq '.[0:3] | .[] | {title, year, venue, citations, source}' /tmp/openalex.json
```

## 4) Multi-source merge + filter + rank

```bash
bash scripts/bci_search.sh "online adaptation motor imagery" "2024-" 20 > /tmp/bci.json
bash scripts/arxiv_search.sh "motor imagery BCI" "2023-" 20 > /tmp/arxiv.json
bash scripts/pubmed_search.sh "focused ultrasound neuromodulation" "2020-" 20 > /tmp/pubmed.json
bash scripts/openalex_search.sh "brain computer interface adaptation" "2020-" 20 > /tmp/openalex.json

jq -s 'add' /tmp/bci.json /tmp/arxiv.json /tmp/pubmed.json /tmp/openalex.json \
  | bash scripts/venue_filter.sh - \
  | bash scripts/rank_results.sh - > /tmp/ranked.json
```

## 5) Persist + dispatch (tech review only)

```bash
DISPATCH_TARGETS=tech_review bash scripts/intel_update.sh /tmp/ranked.json
```

## 6) Persist + dispatch to both downstream queues

```bash
DISPATCH_TARGETS=tech_review,strategy_review bash scripts/intel_update.sh /tmp/ranked.json
```

## 7) Full pipeline one command

```bash
bash scripts/run_pipeline.sh /tmp/ais-run
ls -lah /tmp/ais-run
```

## 8) Inspect catalog and queue status

```bash
jq 'length' ~/.openclaw/workspace/intel/catalog.json

tail -n 5 ~/.openclaw/workspace/intel/dispatch/tech-review-queue.jsonl
tail -n 5 ~/.openclaw/workspace/intel/dispatch/strategy-review-queue.jsonl
```

## 9) Author metrics + BibTeX

```bash
AUTHOR_ID=$(jq -r '.[0].authors[0].id // empty' /tmp/ranked.json)
if [[ -n "$AUTHOR_ID" && "$AUTHOR_ID" != "null" ]]; then
  bash scripts/author_info.sh "$AUTHOR_ID"
fi

DOI=$(jq -r '.[0].doi // empty' /tmp/ranked.json)
if [[ -n "$DOI" && "$DOI" != "null" ]]; then
  bash scripts/doi2bibtex.sh "$DOI"
fi
```