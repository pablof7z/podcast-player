from __future__ import annotations

import json
from pathlib import Path
from typing import Any

from render import badge, e, hero, page, p, rel, section


def architecture_scan_data(evidence_root: Path) -> dict[str, Any]:
    scan = latest_scan(evidence_root)
    if scan is None:
        return {
            "scan_id": "not-recorded",
            "generated_at": "",
            "source_commit": "",
            "status": "not_recorded",
            "counts": {
                "total": 0,
                "by_severity": {},
                "by_rule": {},
                "hard_errors": 0,
            },
            "linked_issues": [],
            "top_rules": [],
            "hard_error_findings": [],
            "findings": [],
        }
    return scan


def latest_scan(evidence_root: Path) -> dict[str, Any] | None:
    paths = sorted(evidence_root.glob("nmp-architecture-scan-*.json"))
    if not paths:
        return None
    return json.loads(paths[-1].read_text())


def render_architecture_scan_home(data: dict[str, Any], depth: int) -> str:
    counts = data["counts"]
    hard_errors = counts.get("hard_errors", 0)
    status = data.get("status", "not_recorded")
    return section(
        "NMP Architecture Scan",
        "<div class=\"next-wave-grid\">"
        + scan_card("Status", badge(status), "Current D0-D10 scan gate.")
        + scan_card("Hard errors", str(hard_errors), "D3/D8 scanner findings blocking architecture confidence.")
        + scan_card("Findings", str(counts.get("total", 0)), "Warnings and errors needing review.")
        + scan_card("Linked issues", str(len(data.get("linked_issues", []))), "GitHub follow-up entries tied to this scan.")
        + "</div>"
        + p("This is static triage, not proof of compliance. Hard errors keep the NMP/Chirp parity gate blocked until fixed and re-scanned.")
        + f"<p><a href=\"{rel('architecture-scan/', depth)}\">Open the architecture scan report</a> &middot; <a href=\"{rel('data/architecture-scan.json', depth)}\">Raw JSON</a></p>",
    )


def render_architecture_scan_page(data: dict[str, Any], depth: int) -> str:
    counts = data["counts"]
    subtitle = (
        f"{counts.get('hard_errors', 0)} hard errors and "
        f"{counts.get('total', 0)} total scanner findings."
    )
    body = [
        hero("NMP Architecture Scan", subtitle),
        section("Scan Gate", scan_gate(data)),
        section("Linked Issues", linked_issues_table(data.get("linked_issues", []))),
        section("Rule Rollup", rule_rollup_table(data.get("top_rules", []))),
        section("Hard Error Findings", finding_table(data.get("hard_error_findings", []), depth)),
        section("Raw Evidence", f"<p><a href=\"{rel('data/architecture-scan.json', depth)}\">Download raw scan JSON</a></p>"),
    ]
    return page("NMP Architecture Scan", depth, "\n".join(body))


def scan_gate(data: dict[str, Any]) -> str:
    counts = data["counts"]
    by_severity = counts.get("by_severity", {})
    by_rule = counts.get("by_rule", {})
    values = {
        "Status": badge(data.get("status", "not_recorded")),
        "Scan ID": data.get("scan_id", ""),
        "Generated": data.get("generated_at", ""),
        "Source commit": data.get("source_commit", ""),
        "Total findings": counts.get("total", 0),
        "Hard errors": counts.get("hard_errors", 0),
        "Warnings": by_severity.get("warning", 0),
        "Rules hit": ", ".join(f"{rule}: {count}" for rule, count in sorted(by_rule.items())),
    }
    rows = "".join(f"<dt>{e(str(key))}</dt><dd>{value if key == 'Status' else e(str(value))}</dd>" for key, value in values.items())
    command = data.get("scanner", {}).get("command", "")
    return "<dl>" + rows + "</dl>" + f"<p><strong>Command:</strong> <code>{e(command)}</code></p>"


def linked_issues_table(issues: list[dict[str, Any]]) -> str:
    if not issues:
        return p("No linked issues recorded for this scan.")
    rows = "".join(
        "<tr>"
        f"<td><a href=\"{e(issue['url'])}\">{e(issue['id'])}</a></td>"
        f"<td>{e(issue.get('scope', ''))}</td>"
        f"<td>{e(', '.join(issue.get('rules', [])))}</td>"
        "</tr>"
        for issue in issues
    )
    return "<table><caption>GitHub issues tracking scan findings</caption><thead><tr><th>Issue</th><th>Scope</th><th>Rules</th></tr></thead><tbody>" + rows + "</tbody></table>"


def rule_rollup_table(rules: list[dict[str, Any]]) -> str:
    if not rules:
        return p("No scanner rule rollup recorded.")
    rows = "".join(
        "<tr>"
        f"<td>{e(item['rule'])}</td>"
        f"<td>{badge(item.get('severity', 'warning'))}</td>"
        f"<td>{e(str(item['count']))}</td>"
        f"<td>{e(item.get('reason', ''))}</td>"
        "</tr>"
        for item in rules
    )
    return "<table><caption>Findings by NMP rule</caption><thead><tr><th>Rule</th><th>Highest Severity</th><th>Count</th><th>Reason</th></tr></thead><tbody>" + rows + "</tbody></table>"


def finding_table(findings: list[dict[str, Any]], depth: int) -> str:
    if not findings:
        return p("No hard-error findings recorded.")
    rows = "".join(
        "<tr>"
        f"<td>{badge(item['severity'])}</td>"
        f"<td>{e(item['rule'])}</td>"
        f"<td><code>{e(item['path'])}:{e(str(item['line']))}</code></td>"
        f"<td><code>{e(item['match'])}</code></td>"
        f"<td>{issue_link_for(item, depth)}</td>"
        "</tr>"
        for item in findings
    )
    return "<table><caption>D3/D8 hard errors blocking NMP architecture confidence</caption><thead><tr><th>Severity</th><th>Rule</th><th>Location</th><th>Match</th><th>Issue</th></tr></thead><tbody>" + rows + "</tbody></table>"


def issue_link_for(item: dict[str, Any], depth: int) -> str:
    rule = item.get("rule", "")
    if rule == "D8/no-polling":
        return '<a href="https://github.com/pablof7z/podcast-player/issues/740">GH-740</a>'
    if rule == "D3/no-hardcoded-relay":
        return '<a href="https://github.com/pablof7z/podcast-player/issues/741">GH-741</a>'
    return f'<a href="{rel("issues/", depth)}">Issue ledger</a>'


def scan_card(label: str, value: str, help_text: str) -> str:
    return f"<article class=\"next-wave-card\"><span>{e(label)}</span><strong>{value}</strong><p>{e(help_text)}</p></article>"
