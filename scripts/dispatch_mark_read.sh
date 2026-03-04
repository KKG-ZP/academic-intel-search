#!/usr/bin/env bash
# Mark a paper as reviewed by downstream stage
# Usage:
#   bash scripts/dispatch_mark_read.sh <paper_key> <target> [reviewer] [note]
# target: tech_review | strategy_review

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_ROOT="$(dirname "$SCRIPT_DIR")"
WORKSPACE_ROOT="$(dirname "$(dirname "$SKILL_ROOT")")"
INTEL_DIR="${INTEL_DIR:-$WORKSPACE_ROOT/intel}"
DISPATCH_DIR="${DISPATCH_DIR:-$INTEL_DIR/dispatch}"
CATALOG_FILE="${CATALOG_FILE:-$INTEL_DIR/catalog.json}"
EVENTS_FILE="${EVENTS_FILE:-$DISPATCH_DIR/review-events.jsonl}"

PAPER_KEY="${1:-}"
TARGET="${2:-}"
REVIEWER="${3:-system}"
NOTE="${4:-}"

if [[ -z "$PAPER_KEY" || -z "$TARGET" ]]; then
  echo '{"error":"Usage: bash scripts/dispatch_mark_read.sh <paper_key> <target> [reviewer] [note]"}' >&2
  exit 1
fi

if [[ "$TARGET" != "tech_review" && "$TARGET" != "strategy_review" ]]; then
  echo '{"error":"target must be tech_review or strategy_review"}' >&2
  exit 1
fi

mkdir -p "$DISPATCH_DIR"
[[ -f "$CATALOG_FILE" ]] || echo "[]" > "$CATALOG_FILE"
touch "$EVENTS_FILE"

python3 - "$CATALOG_FILE" "$EVENTS_FILE" "$PAPER_KEY" "$TARGET" "$REVIEWER" "$NOTE" <<'PY'
import datetime as dt
import json
import sys

catalog_file, events_file, paper_key, target, reviewer, note = sys.argv[1:7]

with open(catalog_file, "r", encoding="utf-8") as f:
    catalog = json.load(f)

if not isinstance(catalog, list):
    catalog = []

now = dt.datetime.now(dt.timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")

found = None
for item in catalog:
    if isinstance(item, dict) and item.get("paper_key") == paper_key:
        found = item
        break

if found is None:
    print(json.dumps({"error": "paper_key not found in catalog", "paper_key": paper_key}, ensure_ascii=False))
    sys.exit(1)

ds = found.setdefault("dispatch_status", {})
for k, v in {
    "sent_to_tech_review": False,
    "sent_to_tech_review_at": None,
    "reviewed_by_tech_review": False,
    "reviewed_by_tech_review_at": None,
    "sent_to_strategy_review": False,
    "sent_to_strategy_review_at": None,
    "reviewed_by_strategy_review": False,
    "reviewed_by_strategy_review_at": None,
}.items():
    ds.setdefault(k, v)

if target == "tech_review":
    ds["sent_to_tech_review"] = True
    if not ds.get("sent_to_tech_review_at"):
        ds["sent_to_tech_review_at"] = now
    ds["reviewed_by_tech_review"] = True
    ds["reviewed_by_tech_review_at"] = now
    if ds.get("reviewed_by_strategy_review"):
        found["workflow_status"] = "fully_reviewed"
    else:
        found["workflow_status"] = "reviewed_by_tech_review"
else:
    ds["sent_to_strategy_review"] = True
    if not ds.get("sent_to_strategy_review_at"):
        ds["sent_to_strategy_review_at"] = now
    ds["reviewed_by_strategy_review"] = True
    ds["reviewed_by_strategy_review_at"] = now
    if ds.get("reviewed_by_tech_review"):
        found["workflow_status"] = "fully_reviewed"
    else:
        found["workflow_status"] = "reviewed_by_strategy_review"

if note:
    notes = found.setdefault("review_notes", [])
    if not isinstance(notes, list):
        notes = []
        found["review_notes"] = notes
    notes.append({"target": target, "reviewer": reviewer, "at": now, "note": note})

found["last_seen_at"] = now

with open(catalog_file, "w", encoding="utf-8") as f:
    json.dump(catalog, f, ensure_ascii=False, indent=2)

with open(events_file, "a", encoding="utf-8") as f:
    f.write(json.dumps({
        "event": "review_marked",
        "paper_key": paper_key,
        "target": target,
        "reviewer": reviewer,
        "note": note or None,
        "at": now,
    }, ensure_ascii=False) + "\n")

print(json.dumps({
    "ok": True,
    "paper_key": paper_key,
    "target": target,
    "workflow_status": found.get("workflow_status"),
    "catalog_file": catalog_file,
    "events_file": events_file,
}, ensure_ascii=False))
PY