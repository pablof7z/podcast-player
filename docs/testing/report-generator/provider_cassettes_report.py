from __future__ import annotations

import json
from pathlib import Path
from typing import Any

from render import badge, e, hero, page, p, section


def provider_cassette_data(repo: Path, evidence: Path) -> dict[str, Any]:
    cassette_dir = repo / "tests" / "fixtures" / "provider_cassettes"
    cassettes = [cassette_summary(path) for path in sorted(cassette_dir.glob("*.json"))]
    validation = read_json(evidence / "provider-cassette-validation.json", {})
    return {
        "cassette_count": len(cassettes),
        "providers": sorted({item["provider"] for item in cassettes}),
        "operations": sorted({item["operation"] for item in cassettes}),
        "scenario_refs": sorted({ref for item in cassettes for ref in item["scenario_refs"]}),
        "all_within_budget": all(item["metrics"].get("acceptable_for_2026_premium") for item in cassettes),
        "cassettes": cassettes,
        "validation": validation,
    }


def cassette_summary(path: Path) -> dict[str, Any]:
    data = json.loads(path.read_text())
    metrics = data.get("metrics", {})
    return {
        "id": data.get("id", path.stem),
        "file": path.name,
        "provider": data.get("provider", ""),
        "operation": data.get("operation", ""),
        "scenario_refs": data.get("scenario_refs", []),
        "nmp_doctrine_refs": data.get("nmp_doctrine_refs", []),
        "metrics": {
            "recorded_latency_ms": metrics.get("recorded_latency_ms"),
            "replay_latency_ms": metrics.get("replay_latency_ms"),
            "budget_ms": metrics.get("budget_ms"),
            "acceptable_for_2026_premium": bool(metrics.get("acceptable_for_2026_premium")),
        },
        "redaction": data.get("redaction", {}),
    }


def render_provider_cassette_page(data: dict[str, Any], depth: int) -> str:
    subtitle = (
        f"{data['cassette_count']} replay cassettes across "
        f"{len(data['providers'])} providers and {len(data['operations'])} operation types."
    )
    body = [
        hero("Provider Cassette Replay Coverage", subtitle),
        section("Replay Gate", replay_gate_block(data)),
        section("Cassette Matrix", cassette_table(data["cassettes"])),
        section("Validation Commands", validation_block(data.get("validation", {}))),
        section("Scenario Coverage", scenario_refs_block(data)),
    ]
    return page("Provider Cassette Replay Coverage", depth, "\n".join(body))


def replay_gate_block(data: dict[str, Any]) -> str:
    status = "pass" if data["all_within_budget"] and data["cassette_count"] else "incomplete"
    values = {
        "Replay status": status,
        "Cassette count": data["cassette_count"],
        "Providers": ", ".join(data["providers"]) or "none",
        "Operations": ", ".join(data["operations"]) or "none",
        "Budget verdict": "all cassettes within recorded 2026 premium-app latency budgets"
        if data["all_within_budget"]
        else "one or more cassettes lacks an acceptable latency budget",
    }
    rows = "".join(f"<dt>{e(key)}</dt><dd>{badge(str(value)) if key == 'Replay status' else e(str(value))}</dd>" for key, value in values.items())
    return "<dl>" + rows + "</dl>" + p("Runtime replay is enabled with POD0_PROVIDER_CASSETTE_DIR and fails closed on request misses, so provider-backed validation can run without live credentials.")


def cassette_table(cassettes: list[dict[str, Any]]) -> str:
    rows = []
    for item in cassettes:
        metrics = item["metrics"]
        rows.append(
            "<tr>"
            f"<td>{e(item['id'])}</td>"
            f"<td>{e(item['provider'])}</td>"
            f"<td>{e(item['operation'])}</td>"
            f"<td>{e(', '.join(item['scenario_refs']))}</td>"
            f"<td>{e(metrics.get('recorded_latency_ms'))} ms</td>"
            f"<td>{e(metrics.get('replay_latency_ms'))} ms</td>"
            f"<td>{e(metrics.get('budget_ms'))} ms</td>"
            f"<td>{badge('pass' if metrics.get('acceptable_for_2026_premium') else 'incomplete')}</td>"
            "</tr>"
        )
    return "<table><caption>Provider replay fixtures</caption><thead><tr><th>Cassette</th><th>Provider</th><th>Operation</th><th>Scenarios</th><th>Recorded</th><th>Replay</th><th>Budget</th><th>2026 Gate</th></tr></thead><tbody>" + "".join(rows) + "</tbody></table>"


def validation_block(validation: dict[str, Any]) -> str:
    rows = "".join(
        f"<tr><td><code>{e(item['command'])}</code></td><td>{badge(item['status'])}</td><td>{e(item['summary'])}</td></tr>"
        for item in validation.get("commands", [])
    )
    notes = "".join(f"<li>{e(note)}</li>" for note in validation.get("notes", []))
    return (
        f"<p><strong>Verified at:</strong> {e(validation.get('verified_at', 'not recorded'))}</p>"
        + "<table><caption>Local replay verification</caption><thead><tr><th>Command</th><th>Status</th><th>Result</th></tr></thead><tbody>"
        + rows
        + "</tbody></table>"
        + f"<ul>{notes}</ul>"
    )


def scenario_refs_block(data: dict[str, Any]) -> str:
    items = "".join(f"<li>{e(ref)}</li>" for ref in data["scenario_refs"])
    return f"<p>{len(data['scenario_refs'])} scenario references are covered by at least one provider cassette.</p><ul class=\"link-list\">{items}</ul>"


def read_json(path: Path, fallback: dict[str, Any]) -> dict[str, Any]:
    if not path.exists():
        return fallback
    return json.loads(path.read_text())
