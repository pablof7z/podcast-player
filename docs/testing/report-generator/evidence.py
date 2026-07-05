from __future__ import annotations

import json
import shutil
from pathlib import Path
from typing import Any


def load_evidence_overlays(evidence_root: Path) -> dict[str, dict[str, Any]]:
    records_dir = evidence_root / "scenario-records"
    if not records_dir.exists():
        return {}
    overlays: dict[str, dict[str, Any]] = {}
    for path in sorted(records_dir.glob("*.json")):
        data = json.loads(path.read_text())
        scenario_id = data.get("scenario_id")
        if not scenario_id:
            raise ValueError(f"{path} is missing scenario_id")
        if scenario_id in overlays:
            raise ValueError(f"Duplicate evidence overlay for {scenario_id}")
        overlays[scenario_id] = data
    return overlays


def apply_evidence_overlays(records: list[dict[str, Any]], overlays: dict[str, dict[str, Any]]) -> None:
    by_id = {record["scenario"]["id"]: record for record in records}
    unknown = sorted(set(overlays) - set(by_id))
    if unknown:
        raise ValueError(f"Evidence overlays reference unknown scenarios: {', '.join(unknown)}")
    for scenario_id, overlay in overlays.items():
        record = by_id[scenario_id]
        for artifact in overlay.get("artifacts", []):
            record["evidence"]["artifacts"].append(artifact)
        deep_merge(record, overlay.get("merge", {}))


def copy_evidence_assets(evidence_root: Path, out: Path) -> None:
    source = evidence_root / "assets"
    if not source.exists():
        return
    target = out / "assets"
    if target.exists():
        shutil.rmtree(target)
    shutil.copytree(source, target)


def deep_merge(target: dict[str, Any], patch: dict[str, Any]) -> None:
    for key, value in patch.items():
        if isinstance(value, dict) and isinstance(target.get(key), dict):
            deep_merge(target[key], value)
        else:
            target[key] = value
