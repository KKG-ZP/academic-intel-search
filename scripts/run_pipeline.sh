#!/usr/bin/env bash
# End-to-end research intel pipeline
# Usage: bash scripts/run_pipeline.sh [output_dir]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_DIR="${1:-/tmp/academic-intel-search}"
mkdir -p "$OUTPUT_DIR"

echo "[1/6] Searching BCI core topics..." >&2
bash "$SCRIPT_DIR/bci_search.sh" "calibration-free online adaptation motor imagery" "2024-" 40 > "$OUTPUT_DIR/bci.json"

echo "[2/6] Searching neuro-modulation topics..." >&2
bash "$SCRIPT_DIR/neuro_search.sh" "transcranial focused ultrasound neuromodulation" "2023-" 30 > "$OUTPUT_DIR/neuro.json"

echo "[3/6] Searching algorithm transfer topics..." >&2
bash "$SCRIPT_DIR/algo_search.sh" "foundation model transformer time-series EEG" "2024-" 30 > "$OUTPUT_DIR/algo.json"

echo "[4/6] Merging + filtering high-quality papers..." >&2
jq -s 'add' "$OUTPUT_DIR/bci.json" "$OUTPUT_DIR/neuro.json" "$OUTPUT_DIR/algo.json" \
  | bash "$SCRIPT_DIR/venue_filter.sh" - > "$OUTPUT_DIR/filtered.json"

echo "[5/6] Ranking papers..." >&2
bash "$SCRIPT_DIR/rank_results.sh" "$OUTPUT_DIR/filtered.json" > "$OUTPUT_DIR/ranked.json"

echo "[6/6] Updating intel store..." >&2
bash "$SCRIPT_DIR/intel_update.sh" "$OUTPUT_DIR/ranked.json" > "$OUTPUT_DIR/report.md"

echo "✅ Pipeline completed" >&2
echo "   Raw outputs:  $OUTPUT_DIR" >&2
echo "   Ranked file:  $OUTPUT_DIR/ranked.json" >&2
echo "   Report file:  $OUTPUT_DIR/report.md" >&2
