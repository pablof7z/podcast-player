from __future__ import annotations

import hashlib
import json
from pathlib import Path
from typing import Any

CASSETTE_FIXTURE_DIR = Path("tests") / "fixtures" / "provider_cassettes"
CASSETTE_ASSET_ROOT = Path("assets") / "cassettes" / "provider_cassettes"


def cassettes_for_scenario(repo: Path, scenario_id: str) -> list[dict[str, Any]]:
    return cassette_index(repo).get(scenario_id, [])


def cassette_index(repo: Path) -> dict[str, list[dict[str, Any]]]:
    fixtures = repo / CASSETTE_FIXTURE_DIR
    index: dict[str, list[dict[str, Any]]] = {}
    if not fixtures.exists():
        return index
    for path in sorted(fixtures.glob("*.json")):
        data = json.loads(path.read_text())
        summary = cassette_summary(path, data)
        for scenario_ref in data.get("scenario_refs", []):
            index.setdefault(str(scenario_ref), []).append(summary)
    return index


def cassette_summary(path: Path, data: dict[str, Any]) -> dict[str, Any]:
    digest = hashlib.sha256(path.read_bytes()).hexdigest()
    metrics = data.get("metrics", {})
    return {
        "id": data.get("id", path.stem),
        "file": path.name,
        "path": str(CASSETTE_FIXTURE_DIR / path.name),
        "asset_path": str(CASSETTE_ASSET_ROOT / path.name),
        "sha256": digest,
        "provider": data.get("provider", "provider"),
        "operation": data.get("operation", "operation"),
        "model": data.get("model", ""),
        "recorded_at": data.get("recorded_at"),
        "scenario_refs": data.get("scenario_refs", []),
        "nmp_rules": data.get("nmp_rules", data.get("nmp_doctrine_refs", [])),
        "metrics": {
            "recorded_latency_ms": metrics.get("recorded_latency_ms"),
            "replay_latency_ms": metrics.get("replay_latency_ms"),
            "budget_ms": metrics.get("budget_ms"),
            "acceptable_for_2026_premium": bool(metrics.get("acceptable_for_2026_premium")),
        },
    }


def run_cassette_records(cassettes: list[dict[str, Any]]) -> list[dict[str, Any]]:
    records = []
    for cassette in cassettes:
        record: dict[str, Any] = {
            "id": cassette["id"],
            "provider": cassette["provider"],
            "mode": "replay",
            "redaction_hash": cassette["sha256"],
        }
        if cassette.get("model"):
            record["model"] = cassette["model"]
        if cassette.get("recorded_at"):
            record["recorded_at"] = cassette["recorded_at"]
        records.append(record)
    return records


def cassette_artifacts(cassettes: list[dict[str, Any]]) -> list[dict[str, Any]]:
    return [
        {
            "id": f"cassette:{cassette['id']}",
            "type": "cassette",
            "path": cassette["asset_path"],
            "description": (
                f"{cassette['provider']} {cassette['operation']} replay fixture "
                f"covering {', '.join(cassette.get('scenario_refs', []))}."
            ),
            "sha256": cassette["sha256"],
            "required": True,
            "redaction": {
                "status": "redacted",
                "notes": "Authorization, raw secrets, and private media are excluded from provider replay matching.",
            },
        }
        for cassette in cassettes
    ]


def effective_provider_mode(scenario_provider_mode: str, cassettes: list[dict[str, Any]]) -> str:
    if cassettes:
        return "replay"
    return scenario_provider_mode
