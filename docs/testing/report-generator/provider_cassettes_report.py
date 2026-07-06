from __future__ import annotations

import json
from pathlib import Path
from typing import Any

from catalog import parse_catalog
from render import badge, e, hero, page, p, rel, section


def provider_cassette_data(repo: Path, evidence: Path, catalog: Path | None = None) -> dict[str, Any]:
    catalog_index = catalog_scenario_index(catalog or repo / "docs" / "testing" / "scenarios" / "catalog")
    cassette_dir = repo / "tests" / "fixtures" / "provider_cassettes"
    cassettes = [cassette_summary(path, catalog_index) for path in sorted(cassette_dir.glob("*.json"))]
    validation = read_json(evidence / "provider-cassette-validation.json", {})
    unmapped_refs = sorted(
        {
            ref
            for item in cassettes
            for ref in item["scenario_refs"]
            if ref not in catalog_index
        }
    )
    mapped_refs = sorted({ref for item in cassettes for ref in item["scenario_refs"] if ref in catalog_index})
    return {
        "cassette_count": len(cassettes),
        "catalog_scenario_count": len(catalog_index),
        "providers": sorted({item["provider"] for item in cassettes}),
        "operations": sorted({item["operation"] for item in cassettes}),
        "scenario_refs": sorted({ref for item in cassettes for ref in item["scenario_refs"]}),
        "mapped_scenario_refs": mapped_refs,
        "unmapped_scenario_refs": unmapped_refs,
        "all_refs_current_catalog_ids": not unmapped_refs,
        "all_within_budget": all(item["metrics"].get("acceptable_for_2026_premium") for item in cassettes),
        "cassettes": cassettes,
        "validation": validation,
    }


def cassette_summary(path: Path, catalog_index: dict[str, dict[str, str]]) -> dict[str, Any]:
    data = json.loads(path.read_text())
    metrics = data.get("metrics", {})
    scenario_refs = data.get("scenario_refs", [])
    return {
        "id": data.get("id", path.stem),
        "file": path.name,
        "provider": data.get("provider", ""),
        "operation": data.get("operation", ""),
        "scenario_refs": scenario_refs,
        "scenario_ref_links": scenario_ref_links(scenario_refs, catalog_index),
        "nmp_rules": data.get("nmp_rules", data.get("nmp_doctrine_refs", [])),
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
        section("Cassette Matrix", cassette_table(data["cassettes"], depth)),
        section("Validation Commands", validation_block(data.get("validation", {}))),
        section("Scenario Coverage", scenario_refs_block(data, depth)),
    ]
    return page("Provider Cassette Replay Coverage", depth, "\n".join(body))


def replay_gate_block(data: dict[str, Any]) -> str:
    status = "pass" if data["all_within_budget"] and data["cassette_count"] and data["all_refs_current_catalog_ids"] else "incomplete"
    values = {
        "Replay status": status,
        "Cassette count": data["cassette_count"],
        "Catalog scenarios": data["catalog_scenario_count"],
        "Providers": ", ".join(data["providers"]) or "none",
        "Operations": ", ".join(data["operations"]) or "none",
        "Scenario ref status": "all cassette refs map to generated scenario pages"
        if data["all_refs_current_catalog_ids"]
        else f"{len(data['unmapped_scenario_refs'])} unmapped refs: {', '.join(data['unmapped_scenario_refs'])}",
        "Budget verdict": "all cassettes within recorded 2026 premium-app latency budgets"
        if data["all_within_budget"]
        else "one or more cassettes lacks an acceptable latency budget",
    }
    rows = "".join(f"<dt>{e(key)}</dt><dd>{badge(str(value)) if key == 'Replay status' else e(str(value))}</dd>" for key, value in values.items())
    return "<dl>" + rows + "</dl>" + p("Runtime replay is enabled with POD0_PROVIDER_CASSETTE_DIR and fails closed on request misses, so provider-backed validation can run without live credentials.")


def cassette_table(cassettes: list[dict[str, Any]], depth: int = 1) -> str:
    rows = []
    for item in cassettes:
        metrics = item["metrics"]
        rows.append(
            "<tr>"
            f"<td>{e(item['id'])}</td>"
            f"<td>{e(item['provider'])}</td>"
            f"<td>{e(item['operation'])}</td>"
            f"<td>{scenario_links_cell(item['scenario_ref_links'], depth)}</td>"
            f"<td>{e(', '.join(item['nmp_rules']))}</td>"
            f"<td>{e(metrics.get('recorded_latency_ms'))} ms</td>"
            f"<td>{e(metrics.get('replay_latency_ms'))} ms</td>"
            f"<td>{e(metrics.get('budget_ms'))} ms</td>"
            f"<td>{badge('pass' if metrics.get('acceptable_for_2026_premium') else 'incomplete')}</td>"
            "</tr>"
        )
    return "<table><caption>Provider replay fixtures</caption><thead><tr><th>Cassette</th><th>Provider</th><th>Operation</th><th>Scenarios</th><th>NMP Rules</th><th>Recorded</th><th>Replay</th><th>Budget</th><th>2026 Gate</th></tr></thead><tbody>" + "".join(rows) + "</tbody></table>"


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


def scenario_refs_block(data: dict[str, Any], depth: int) -> str:
    refs = []
    by_id = {
        link["id"]: link
        for item in data["cassettes"]
        for link in item["scenario_ref_links"]
    }
    for ref in data["scenario_refs"]:
        link = by_id.get(ref, {"id": ref, "mapped": False})
        refs.append(scenario_link_item(link, depth))
    unmapped = ""
    if data["unmapped_scenario_refs"]:
        missing = "".join(f"<li>{e(ref)}</li>" for ref in data["unmapped_scenario_refs"])
        unmapped = f"<h3>Unmapped Refs</h3><p>These refs do not correspond to generated catalog pages and must block replay readiness.</p><ul>{missing}</ul>"
    return (
        f"<p>{len(data['mapped_scenario_refs'])} current catalog scenario references are covered by at least one provider cassette; "
        f"{len(data['unmapped_scenario_refs'])} refs are unmapped.</p>"
        f"<ul class=\"link-list\">{''.join(refs)}</ul>{unmapped}"
    )


def catalog_scenario_index(catalog: Path) -> dict[str, dict[str, str]]:
    if not catalog.exists():
        return {}
    return {
        scenario.scenario_id: {
            "id": scenario.scenario_id,
            "slug": scenario.slug,
            "title": scenario.title,
            "category": scenario.category,
        }
        for scenario in parse_catalog(catalog)
    }


def scenario_ref_links(refs: list[str], catalog_index: dict[str, dict[str, str]]) -> list[dict[str, Any]]:
    links = []
    for ref in refs:
        scenario = catalog_index.get(ref)
        links.append({**scenario, "mapped": True} if scenario else {"id": ref, "mapped": False, "slug": "", "title": "", "category": ""})
    return links


def scenario_links_cell(links: list[dict[str, Any]], depth: int) -> str:
    return ", ".join(scenario_link_inline(link, depth) for link in links)


def scenario_link_inline(link: dict[str, Any], depth: int) -> str:
    if link["mapped"]:
        return f"<a href=\"{rel('scenarios/' + link['slug'] + '/', depth)}\">{e(link['id'])}</a>"
    return badge(f"{link['id']} unmapped")


def scenario_link_item(link: dict[str, Any], depth: int) -> str:
    if link["mapped"]:
        href = rel("scenarios/" + link["slug"] + "/", depth)
        return f"<li><a href=\"{href}\">{e(link['id'])}</a> - {e(link['title'])}</li>"
    return f"<li>{badge(link['id'] + ' unmapped')}</li>"


def read_json(path: Path, fallback: dict[str, Any]) -> dict[str, Any]:
    if not path.exists():
        return fallback
    return json.loads(path.read_text())
