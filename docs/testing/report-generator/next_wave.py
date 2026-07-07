from __future__ import annotations

import copy
import json
from pathlib import Path
from typing import Any


DEFAULT_MANIFEST = Path(__file__).resolve().parent / "data" / "next-wave-foundation-onboarding.json"

REQUIRED_ENTRY_FIELDS = {
    "scenario_id",
    "priority",
    "runbook",
    "screenshot_requirements",
    "performance_metrics",
    "ui_ux_liquid_glass_checks",
    "issue_filing_gates",
}


def load_next_wave(path: Path = DEFAULT_MANIFEST) -> dict[str, Any]:
    manifest = json.loads(path.read_text())
    validate_manifest(manifest, path)
    return manifest


def validate_manifest(manifest: dict[str, Any], path: Path) -> None:
    for key in ["wave_id", "title", "status", "cluster", "scenarios"]:
        if key not in manifest:
            raise ValueError(f"{path} is missing {key}")
    seen: set[str] = set()
    for entry in manifest["scenarios"]:
        missing = REQUIRED_ENTRY_FIELDS - set(entry)
        if missing:
            raise ValueError(f"{path} entry is missing: {', '.join(sorted(missing))}")
        scenario_id = entry["scenario_id"]
        if scenario_id in seen:
            raise ValueError(f"{path} duplicates scenario_id {scenario_id}")
        seen.add(scenario_id)
        for list_key in ["screenshot_requirements", "performance_metrics", "ui_ux_liquid_glass_checks", "issue_filing_gates"]:
            if not entry[list_key]:
                raise ValueError(f"{path} {scenario_id} has no {list_key}")


def scenario_entries(manifest: dict[str, Any]) -> list[dict[str, Any]]:
    return sorted(manifest["scenarios"], key=lambda item: (item["priority"], item["scenario_id"]))


def scenario_entry_for(record: dict[str, Any], manifest: dict[str, Any]) -> dict[str, Any] | None:
    scenario_id = record["scenario"]["id"]
    return next((entry for entry in scenario_entries(manifest) if entry["scenario_id"] == scenario_id), None)


def next_wave_export(records: list[dict[str, Any]], manifest: dict[str, Any]) -> dict[str, Any]:
    records_by_id = {record["scenario"]["id"]: record for record in records}
    scenarios = []
    for entry in scenario_entries(manifest):
        record = records_by_id.get(entry["scenario_id"])
        item = copy.deepcopy(entry)
        item["catalog_status"] = "mapped" if record else "missing_from_current_catalog"
        if record:
            item["title"] = record["scenario"]["title"]
            item["category"] = record["scenario"]["category"]
            item["scenario_url"] = f"scenarios/{record['scenario']['slug']}/"
            item["data_url"] = f"scenarios/{record['scenario']['slug']}/data.json"
            item["execution_status"] = record["execution"]["status"]
            item["verdict"] = record["verdict"]["overall"]
            item["readiness"] = record["readiness"]["ship_gate"]
            item["missing_evidence"] = [missing["kind"] for missing in record["evidence"]["missing"]]
        scenarios.append(item)
    return {
        "wave_id": manifest["wave_id"],
        "title": manifest["title"],
        "status": manifest["status"],
        "cluster": manifest["cluster"],
        "created_at": manifest["created_at"],
        "search_command": manifest["search_command"],
        "loaded_skills": manifest["loaded_skills"],
        "execution_principles": manifest["execution_principles"],
        "common_capture_requirements": manifest["common_capture_requirements"],
        "target_count": len(scenarios),
        "mapped_count": sum(1 for item in scenarios if item["catalog_status"] == "mapped"),
        "not_run_count": sum(1 for item in scenarios if item.get("execution_status") == "not_run"),
        "scenarios": scenarios,
    }
