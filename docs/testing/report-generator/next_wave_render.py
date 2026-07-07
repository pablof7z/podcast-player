from __future__ import annotations

import html
from typing import Any

from catalog import slugify
from next_wave import next_wave_export, scenario_entry_for


def render_next_wave_home(records: list[dict[str, Any]], manifest: dict[str, Any], depth: int) -> str:
    data = next_wave_export(records, manifest)
    cards = [
        ("Status", badge(data["status"]), "Planning only; no execution is implied."),
        ("Targets", str(data["target_count"]), "Focused scenario pages in this wave."),
        ("Mapped", str(data["mapped_count"]), "Targets found in the current catalog."),
        ("Not run", str(data["not_run_count"]), "Targets still awaiting evidence-backed runs."),
    ]
    html_cards = "".join(
        f"<article class=\"next-wave-card\"><span>{e(label)}</span><strong>{value}</strong><p>{e(help_text)}</p></article>"
        for label, value, help_text in cards
    )
    top_targets = data["scenarios"][:6]
    links = "".join(
        f"<li><a href=\"{rel(item.get('scenario_url', 'next-wave/'), depth)}\">{e(item['scenario_id'])}</a> - {e(item.get('title', 'not in catalog'))}</li>"
        for item in top_targets
    )
    body = (
        f"<div class=\"next-wave-grid\">{html_cards}</div>"
        + p(data["cluster"]["scope"])
        + f"<p><a href=\"{rel('next-wave/', depth)}\">Open the full execution manifest</a> &middot; <a href=\"{rel('data/next-wave.json', depth)}\">Raw JSON</a></p>"
        + f"<ol>{links}</ol>"
    )
    return section("Next Execution Wave", body)


def render_next_wave_page(records: list[dict[str, Any]], manifest: dict[str, Any], depth: int) -> str:
    data = next_wave_export(records, manifest)
    rows = "".join(
        "<tr>"
        f"<td>{e(item['priority'])}</td>"
        f"<td><a href=\"{rel(item.get('scenario_url', '#'), depth)}\">{e(item['scenario_id'])}</a></td>"
        f"<td>{e(item.get('title', 'not in catalog'))}</td>"
        f"<td>{badge(item.get('execution_status', item['catalog_status']))}</td>"
        f"<td>{e(len(item['screenshot_requirements']))}</td>"
        f"<td>{e(len(item['performance_metrics']))}</td>"
        f"<td>{e(len(item['issue_filing_gates']))}</td>"
        "</tr>"
        for item in data["scenarios"]
    )
    table = (
        "<table><caption>Planned foundation wave targets</caption><thead><tr>"
        "<th>Priority</th><th>Scenario</th><th>Title</th><th>Status</th><th>Screenshots</th><th>Metrics</th><th>Issue Gates</th>"
        f"</tr></thead><tbody>{rows}</tbody></table>"
    )
    body = [
        hero(data["title"], f"{data['target_count']} planned targets for {e(data['cluster']['title'])}. Status: {badge(data['status'])}"),
        key_values(
            {
                "Wave": data["wave_id"],
                "Cluster": f"{data['cluster']['title']} ({data['cluster']['id']})",
                "Created": data["created_at"],
                "Search": data["search_command"],
                "Loaded skills": ", ".join(data["loaded_skills"]),
                "Mapped targets": f"{data['mapped_count']} of {data['target_count']}",
            }
        ),
        section("Execution Principles", ordered(data["execution_principles"])),
        section("Common Capture Requirements", ordered(data["common_capture_requirements"])),
        section("Scenario Targets", table),
        section("Per-Scenario Manifest", "".join(scenario_detail(item, depth) for item in data["scenarios"])),
    ]
    return page("Next Execution Wave", depth, "\n".join(body))


def scenario_next_wave_block(record: dict[str, Any], manifest: dict[str, Any]) -> str:
    entry = scenario_entry_for(record, manifest)
    if not entry:
        return ""
    return scenario_detail({**entry, "execution_status": record["execution"]["status"]}, 2)


def scenario_detail(entry: dict[str, Any], depth: int) -> str:
    values = {
        "Priority": str(entry["priority"]),
        "Scenario": entry["scenario_id"],
        "Runbook": entry["runbook"],
        "Execution status": entry.get("execution_status", entry.get("catalog_status", "planned")),
    }
    return (
        f"<article class=\"next-wave-detail\" id=\"{slugify(entry['scenario_id'])}\">"
        f"<h3>{e(entry['scenario_id'])}</h3>"
        + key_values(values)
        + requirement_table("Screenshot requirements", entry["screenshot_requirements"], ["id", "step_id", "description", "must_include", "must_not_include"])
        + requirement_table("Performance metrics to collect", entry["performance_metrics"], ["id", "name", "budget", "method", "required"])
        + requirement_table("UI, UX, Liquid Glass checks", entry["ui_ux_liquid_glass_checks"], ["id", "area", "check", "skill_refs"])
        + requirement_table("Issue-filing gates", entry["issue_filing_gates"], ["id", "severity", "file_issue_if", "affected_dimensions"])
        + "</article>"
    )


def requirement_table(title: str, rows_data: list[dict[str, Any]], keys: list[str]) -> str:
    headers = "".join(f"<th>{e(key.replace('_', ' ').title())}</th>" for key in keys)
    rows = ""
    for row in rows_data:
        cells = "".join(f"<td>{cell(row.get(key, ''))}</td>" for key in keys)
        rows += f"<tr>{cells}</tr>"
    return f"<table><caption>{e(title)}</caption><thead><tr>{headers}</tr></thead><tbody>{rows}</tbody></table>"


def cell(value: Any) -> str:
    if isinstance(value, list):
        return e(", ".join(str(item) for item in value))
    if isinstance(value, bool):
        return e("yes" if value else "no")
    return e(str(value))


def page(title: str, depth: int, body: str) -> str:
    return f"""<!doctype html>
<html lang=\"en\">
<head>
  <meta charset=\"utf-8\">
  <meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">
  <title>{e(title)}</title>
  <link rel=\"stylesheet\" href=\"{rel('styles.css', depth)}\">
  <link rel=\"icon\" href=\"{rel('assets/favicon.svg', depth)}\" type=\"image/svg+xml\">
</head>
<body>
  <a class=\"skip-link\" href=\"#content\">Skip to content</a>
  <main id=\"content\">
    {body}
  </main>
</body>
</html>
"""


def hero(title: str, subtitle: str) -> str:
    return f"<header class=\"hero\"><p class=\"eyebrow\">Pod0 Validation</p><h1>{e(title)}</h1><p>{subtitle}</p></header>"


def section(title: str, body: str) -> str:
    return f"<section id=\"{slugify(title)}\"><h2>{e(title)}</h2>{body}</section>"


def p(text: str) -> str:
    return f"<p>{e(text)}</p>"


def ordered(items: list[str]) -> str:
    return "<ol>" + "".join(f"<li>{e(item)}</li>" for item in items) + "</ol>"


def key_values(values: dict[str, str]) -> str:
    return "<dl>" + "".join(f"<dt>{e(key)}</dt><dd>{e(value)}</dd>" for key, value in values.items()) + "</dl>"


def badge(value: str) -> str:
    return f"<span class=\"badge badge-{slugify(str(value))}\">{e(value)}</span>"


def rel(path: str, depth: int) -> str:
    if path.startswith(("http://", "https://", "../", "./", "#")):
        return path
    return ("../" * depth) + path


def e(value: Any) -> str:
    return html.escape(str(value), quote=True)
