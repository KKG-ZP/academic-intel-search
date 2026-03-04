#!/usr/bin/env bash
# End-to-end research intel pipeline
# Usage: bash scripts/run_pipeline.sh [output_dir]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_DIR="${1:-/tmp/academic-intel-search}"
mkdir -p "$OUTPUT_DIR"

echo "[1/9] Searching BCI core topics (Semantic Scholar/CrossRef)..." >&2
bash "$SCRIPT_DIR/bci_search.sh" "calibration-free online adaptation motor imagery" "2024-" 40 > "$OUTPUT_DIR/bci.json"

echo "[2/9] Searching neuro-modulation topics (Semantic Scholar/CrossRef)..." >&2
bash "$SCRIPT_DIR/neuro_search.sh" "transcranial focused ultrasound neuromodulation" "2023-" 30 > "$OUTPUT_DIR/neuro.json"

echo "[3/9] Searching algorithm transfer topics (Semantic Scholar/CrossRef)..." >&2
bash "$SCRIPT_DIR/algo_search.sh" "foundation model transformer time-series EEG" "2024-" 30 > "$OUTPUT_DIR/algo.json"

echo "[4/9] Searching arXiv direct API..." >&2
bash "$SCRIPT_DIR/arxiv_search.sh" "motor imagery BCI online adaptation" "2023-" 30 > "$OUTPUT_DIR/arxiv.json"

echo "[5/9] Searching PubMed direct API..." >&2
bash "$SCRIPT_DIR/pubmed_search.sh" "focused ultrasound neuromodulation brain stimulation" "2020-" 30 > "$OUTPUT_DIR/pubmed.json"

echo "[6/9] Searching OpenAlex direct API..." >&2
bash "$SCRIPT_DIR/openalex_search.sh" "brain computer interface motor imagery adaptation" "2020-" 30 > "$OUTPUT_DIR/openalex.json"

echo "[7/9] Merging + filtering high-quality papers..." >&2
jq -s 'add' \
  "$OUTPUT_DIR/bci.json" \
  "$OUTPUT_DIR/neuro.json" \
  "$OUTPUT_DIR/algo.json" \
  "$OUTPUT_DIR/arxiv.json" \
  "$OUTPUT_DIR/pubmed.json" \
  "$OUTPUT_DIR/openalex.json" \
  | bash "$SCRIPT_DIR/venue_filter.sh" - > "$OUTPUT_DIR/filtered.json"

echo "[8/9] Ranking papers..." >&2
bash "$SCRIPT_DIR/rank_results.sh" "$OUTPUT_DIR/filtered.json" > "$OUTPUT_DIR/ranked.json"

echo "[9/9] Updating intel store + catalog + dispatch queues..." >&2
DISPATCH_TARGETS="${DISPATCH_TARGETS:-tech_review}" \
  bash "$SCRIPT_DIR/intel_update.sh" "$OUTPUT_DIR/ranked.json" > "$OUTPUT_DIR/report.md"

echo "✅ Pipeline completed" >&2
echo "   Raw outputs:  $OUTPUT_DIR" >&2
echo "   Ranked file:  $OUTPUT_DIR/ranked.json" >&2
echo "   Report file:  $OUTPUT_DIR/report.md" >&2