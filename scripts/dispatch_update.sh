#!/usr/bin/env bash
# Update catalog + dispatch queues with deduped status tracking
# Usage:
#   bash scripts/dispatch_update.sh papers.json [targets]
#   targets: tech_review,strategy_review (default: tech_review)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_ROOT="$(dirname "$SCRIPT_DIR")"
WORKSPACE_ROOT="$(dirname "$(dirname "$SKILL_ROOT")")"
INTEL_DIR="${INTEL_DIR:-$WORKSPACE_ROOT/intel}"
DISPATCH_DIR="${DISPATCH_DIR:-$INTEL_DIR/dispatch}"
CATALOG_FILE="${CATALOG_FILE:-$INTEL_DIR/catalog.json}"
TECH_QUEUE_FILE="${TECH_QUEUE_FILE:-$DISPATCH_DIR/tech-review-queue.jsonl}"
STRATEGY_QUEUE_FILE="${STRATEGY_QUEUE_FILE:-$DISPATCH_DIR/strategy-review-queue.jsonl}"

INPUT_FILE="${1:-}"
TARGETS="${2:-${DISPATCH_TARGETS:-tech_review}}"

if [[ -z "$INPUT_FILE" ]]; then
  echo '{"error":"Usage: bash scripts/dispatch_update.sh papers.json [targets]"}' >&2
  exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo '{"error":"python3 is required"}' >&2
  exit 1
fi

mkdir -p "$DISPATCH_DIR"
[[ -f "$CATALOG_FILE" ]] || echo "[]" > "$CATALOG_FILE"
touch "$TECH_QUEUE_FILE" "$STRATEGY_QUEUE_FILE"

python3 - "$INPUT_FILE" "$CATALOG_FILE" "$TECH_QUEUE_FILE" "$STRATEGY_QUEUE_FILE" "$TARGETS" <<'PY'
import datetime as dt
import hashlib
import json
import os
import re
import sys
from typing import Any, Dict, List

input_file, catalog_file, tech_q_file, strategy_q_file, targets_raw = sys.argv[1:6]


def load_json(path: str):
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


def as_list(v: Any) -> List[Dict[str, Any]]:
    if isinstance(v, list):
        return [x for x in v if isinstance(x, dict)]
    if isinstance(v, dict):
        return [v]
    return []


def normalize_title(t: str) -> str:
    t = (t or "").strip().lower()
    t = re.sub(r"\s+", " ", t)
    return t


def paper_key(p: Dict[str, Any]) -> str:
    doi = (p.get("doi") or "").strip().lower()
    if doi:
        return f"doi:{doi}"
    arxiv_id = (p.get("arxiv_id") or "").strip().lower()
    if arxiv_id:
        return f"arxiv:{arxiv_id}"
    title = normalize_title(p.get("title") or "")
    year = p.get("year")
    base = f"{title}|{year}"
    digest = hashlib.sha1(base.encode("utf-8")).hexdigest()[:16]
    return f"title:{digest}"


def update_if_present(dst: Dict[str, Any], src: Dict[str, Any], key: str):
    val = src.get(key)
    if val not in (None, "", [], {}):
        dst[key] = val


def now_iso() -> str:
    return dt.datetime.now(dt.timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def parse_targets(raw: str):
    allowed = {"tech_review", "strategy_review"}
    targets = []
    for token in (raw or "").split(","):
        t = token.strip().lower()
        if t in allowed and t not in targets:
            targets.append(t)
    return targets or ["tech_review"]


def queue_append(path: str, row: Dict[str, Any]):
    with open(path, "a", encoding="utf-8") as f:
        f.write(json.dumps(row, ensure_ascii=False) + "\n")


papers = as_list(load_json(input_file))
catalog_data = as_list(load_json(catalog_file)) if os.path.exists(catalog_file) else []

catalog_map: Dict[str, Dict[str, Any]] = {}
for e in catalog_data:
    k = e.get("paper_key")
    if isinstance(k, str) and k:
        catalog_map[k] = e

now = now_iso()
targets = parse_targets(targets_raw)
queued_counts = {"tech_review": 0, "strategy_review": 0}

for p in papers:
    if not (p.get("title") or p.get("doi") or p.get("url")):
        continue

    k = paper_key(p)
    entry = catalog_map.get(k)
    is_new = entry is None

    if is_new:
        entry = {
            "paper_key": k,
            "title": p.get("title") or "N/A",
            "year": p.get("year"),
            "venue": p.get("venue"),
            "doi": p.get("doi"),
            "arxiv_id": p.get("arxiv_id"),
            "url": p.get("url"),
            "source": p.get("source"),
            "quality_score": p.get("quality_score"),
            "citations": p.get("citations", 0) or 0,
            "first_seen_at": now,
            "last_seen_at": now,
            "seen_count": 0,
            "workflow_status": "new",
            "dispatch_status": {
                "sent_to_tech_review": False,
                "sent_to_tech_review_at": None,
                "sent_to_strategy_review": False,
                "sent_to_strategy_review_at": None,
            },
        }

    update_if_present(entry, p, "title")
    update_if_present(entry, p, "year")
    update_if_present(entry, p, "venue")
    update_if_present(entry, p, "doi")
    update_if_present(entry, p, "arxiv_id")
    update_if_present(entry, p, "url")
    update_if_present(entry, p, "source")
    update_if_present(entry, p, "quality_score")
    if p.get("citations") is not None:
        entry["citations"] = p.get("citations")

    entry["last_seen_at"] = now
    entry["seen_count"] = int(entry.get("seen_count") or 0) + 1

    ds = entry.setdefault("dispatch_status", {})
    ds.setdefault("sent_to_tech_review", False)
    ds.setdefault("sent_to_tech_review_at", None)
    ds.setdefault("sent_to_strategy_review", False)
    ds.setdefault("sent_to_strategy_review_at", None)

    if "tech_review" in targets and not ds.get("sent_to_tech_review"):
        queue_append(
            tech_q_file,
            {
                "paper_key": k,
                "dispatch_target": "tech_review",
                "queued_at": now,
                "title": entry.get("title"),
                "year": entry.get("year"),
                "venue": entry.get("venue"),
                "doi": entry.get("doi"),
                "arxiv_id": entry.get("arxiv_id"),
                "url": entry.get("url"),
                "source": entry.get("source"),
                "quality_score": entry.get("quality_score"),
                "citations": entry.get("citations"),
            },
        )
        ds["sent_to_tech_review"] = True
        ds["sent_to_tech_review_at"] = now
        entry["workflow_status"] = "queued_for_tech_review"
        queued_counts["tech_review"] += 1

    if "strategy_review" in targets and not ds.get("sent_to_strategy_review"):
        queue_append(
            strategy_q_file,
            {
                "paper_key": k,
                "dispatch_target": "strategy_review",
                "queued_at": now,
                "title": entry.get("title"),
                "year": entry.get("year"),
                "venue": entry.get("venue"),
                "doi": entry.get("doi"),
                "arxiv_id": entry.get("arxiv_id"),
                "url": entry.get("url"),
                "source": entry.get("source"),
                "quality_score": entry.get("quality_score"),
                "citations": entry.get("citations"),
            },
        )
        ds["sent_to_strategy_review"] = True
        ds["sent_to_strategy_review_at"] = now
        entry["workflow_status"] = "queued_for_strategy_review"
        queued_counts["strategy_review"] += 1

    catalog_map[k] = entry

catalog_out = sorted(
    catalog_map.values(),
    key=lambda x: (
        -(x.get("quality_score") or 0),
        -(x.get("citations") or 0),
        x.get("title") or "",
    ),
)

with open(catalog_file, "w", encoding="utf-8") as f:
    json.dump(catalog_out, f, ensure_ascii=False, indent=2)

summary = {
    "catalog_file": catalog_file,
    "catalog_count": len(catalog_out),
    "targets": targets,
    "queued": queued_counts,
    "queue_files": {
        "tech_review": tech_q_file,
        "strategy_review": strategy_q_file,
    },
}
print(json.dumps(summary, ensure_ascii=False))
PY