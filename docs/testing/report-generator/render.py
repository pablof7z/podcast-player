from __future__ import annotations

import html
from typing import Any

from catalog import slugify
from contract import SECTION_LABELS
from records import count_boundaries, count_by, count_tags, missing_evidence_for, rollups_for


def render_home(records: list[dict[str, Any]], depth: int) -> str:
    rollups = rollups_for(records)
    body = [
        hero("Pod0 Scenario Validation Report", f"{len(records)} generated scenario pages. Current verdict: incomplete until run evidence is attached."),
        stat_band(rollups["by_verdict"]),
        section("Scenario Page System", p("Each BDD catalog scenario now has a stable page, JSON record, source link, required sections, score scaffold, skill-grounding rubric, and rollup membership.")),
        link_list("Indexes", [("All scenarios", rel("scenarios/", depth)), ("Tags", rel("tags/", depth)), ("Issues", rel("issues/", depth)), ("Performance rollup", rel("rollups/performance/", depth)), ("Raw scenario JSON", rel("data/scenarios.json", depth))]),
    ]
    return page("Pod0 Validation Report", depth, "\n".join(body))


def render_scenario_index(records: list[dict[str, Any]], depth: int, title: str) -> str:
    rows = "\n".join(
        f"<tr><td><a href=\"{rel('scenarios/' + r['scenario']['slug'] + '/', depth)}\">{e(r['scenario']['id'])}</a></td><td>{e(r['scenario']['title'])}</td><td>{e(r['scenario']['category'])}</td><td>{badge(r['verdict']['overall'])}</td><td>{e(', '.join(missing_evidence_for(r)))}</td></tr>"
        for r in records
    )
    table = f"<table><thead><tr><th>ID</th><th>Scenario</th><th>Category</th><th>Verdict</th><th>Missing Evidence</th></tr></thead><tbody>{rows}</tbody></table>"
    return page(title, depth, hero(title, f"{len(records)} scenario page records") + section("Scenario Table", table))


def render_scenario_page(record: dict[str, Any], depth: int) -> str:
    scenario = record["scenario"]
    nav = record["page"]["navigation"]
    nav_links = [
        ("All scenarios", rel("scenarios/", depth)),
        ("Category", rel(f"scenarios/{slugify(scenario['category'])}/", depth)),
        ("Data JSON", "data.json"),
    ]
    if nav.get("previous_url"):
        nav_links.append(("Previous", nav["previous_url"]))
    if nav.get("next_url"):
        nav_links.append(("Next", nav["next_url"]))
    body = [
        nav_bar(nav_links),
        hero(f"{scenario['id']} - {scenario['title']}", f"{scenario['category']} - {badge(record['verdict']['overall'])}"),
        section("BDD", bdd_block(scenario["bdd"])),
        section("Run Metadata", key_values(metadata_for(record))),
        section("Grouped Scores", score_table(record["group_scores"])),
        section("Dimension Scores", score_table(record["dimension_scores"])),
        section("Required Page Sections", "\n".join(render_required_section(key, value) for key, value in record["sections"].items())),
        section("Evidence Registry", artifact_table(record["evidence"]["artifacts"], depth)),
        section("Next Actions", action_list(record["next_actions"])),
    ]
    return page(f"{scenario['id']} - {scenario['title']}", depth, "\n".join(body))


def metadata_for(record: dict[str, Any]) -> dict[str, str]:
    return {
        "Source": record["scenario"]["source_path"],
        "Generated": record["page"]["generated_at"],
        "Commit": record["run"]["source_commit"],
        "Branch": record["run"].get("branch", ""),
        "Provider mode": record["run"]["provider_mode"],
        "Generator": record["run"]["generator_version"],
    }


def bdd_block(bdd: dict[str, list[str]]) -> str:
    return f"<dl><dt>Given</dt><dd>{e('; '.join(bdd['given']))}</dd><dt>When</dt><dd>{e('; '.join(bdd['when']))}</dd><dt>Then</dt><dd>{e('; '.join(bdd['then']))}</dd></dl>"


def render_required_section(key: str, value: dict[str, Any]) -> str:
    notes = "".join(f"<li>{e(note)}</li>" for note in value.get("notes", []))
    refs = ", ".join(value.get("evidence_refs", [])) or "none"
    note_html = f"<ul>{notes}</ul>" if notes else ""
    return f"<article class=\"report-section\"><h3>{e(SECTION_LABELS[key])}</h3><p>{e(value['summary'])}</p><p class=\"muted\">Evidence refs: {e(refs)}</p>{note_html}</article>"


def write_tag_pages(records: list[dict[str, Any]], out: Any) -> dict[Any, str]:
    tags = count_tags(records)
    pages = {out / "tags" / "index.html": page("Tags", 1, hero("Tags", "Scenario filters by generated tag") + link_list("Tags", [(f"{tag} ({count})", f"{tag}/") for tag, count in tags.items()]))}
    for tag in tags:
        tagged = [record for record in records if tag in record["scenario"]["tags"]]
        pages[out / "tags" / tag / "index.html"] = render_scenario_index(tagged, 2, f"Tag: {tag}")
    return pages


def write_rollup_pages(records: list[dict[str, Any]], out: Any) -> dict[Any, str]:
    pages = {
        out / "issues" / "index.html": page("Issues", 1, hero("Issues", "No observed defects have been filed from generated scaffolds yet.") + p("Scenario pages remain incomplete until defects discovered during validation are linked here."))
    }
    for verdict in count_by(records, lambda r: r["verdict"]["overall"]):
        filtered = [r for r in records if r["verdict"]["overall"] == verdict]
        pages[out / "rollups" / "verdict" / verdict / "index.html"] = render_scenario_index(filtered, 3, f"Verdict: {verdict}")
    for provider in count_by(records, lambda r: r["run"]["provider_mode"]):
        filtered = [r for r in records if r["run"]["provider_mode"] == provider]
        pages[out / "rollups" / "provider" / provider / "index.html"] = render_scenario_index(filtered, 3, f"Provider mode: {provider}")
    for boundary in count_boundaries(records):
        filtered = [r for r in records if boundary in r["scenario"]["tags"]]
        pages[out / "rollups" / "nmp" / boundary / "index.html"] = render_scenario_index(filtered, 3, f"NMP boundary: {boundary}")
    perf = [r for r in records if "performance-required" in r["scenario"]["tags"]]
    pages[out / "rollups" / "performance" / "index.html"] = render_scenario_index(perf, 2, "Performance Metrics Required")
    return pages


def page(title: str, depth: int, body: str) -> str:
    return f"""<!doctype html>
<html lang=\"en\">
<head>
  <meta charset=\"utf-8\">
  <meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">
  <title>{e(title)}</title>
  <link rel=\"stylesheet\" href=\"{rel('styles.css', depth)}\">
</head>
<body>
  <main>
    {body}
  </main>
</body>
</html>
"""


def hero(title: str, subtitle: str) -> str:
    return f"<header class=\"hero\"><p class=\"eyebrow\">Pod0 Validation</p><h1>{e(title)}</h1><p>{subtitle}</p></header>"


def section(title: str, body: str) -> str:
    return f"<section><h2>{e(title)}</h2>{body}</section>"


def p(text: str) -> str:
    return f"<p>{e(text)}</p>"


def link_list(title: str, links: list[tuple[str, str]]) -> str:
    items = "".join(f"<li><a href=\"{href}\">{e(label)}</a></li>" for label, href in links)
    return section(title, f"<ul class=\"link-list\">{items}</ul>")


def nav_bar(links: list[tuple[str, str]]) -> str:
    return "<nav>" + "".join(f"<a href=\"{href}\">{e(label)}</a>" for label, href in links if href) + "</nav>"


def stat_band(counts: dict[str, int]) -> str:
    stats = "".join(f"<div><strong>{count}</strong><span>{e(name)}</span></div>" for name, count in counts.items())
    return f"<section class=\"stats\">{stats}</section>"


def key_values(values: dict[str, str]) -> str:
    return "<dl>" + "".join(f"<dt>{e(k)}</dt><dd>{e(str(v))}</dd>" for k, v in values.items()) + "</dl>"


def score_table(scores: dict[str, dict[str, Any]]) -> str:
    rows = "".join(f"<tr><td>{e(name)}</td><td>{e(str(item['score']))}</td><td>{badge(item['status'])}</td><td>{e(item['rationale'])}</td></tr>" for name, item in scores.items())
    return f"<table><thead><tr><th>Dimension</th><th>Score</th><th>Status</th><th>Rationale</th></tr></thead><tbody>{rows}</tbody></table>"


def artifact_table(artifacts: list[dict[str, Any]], depth: int) -> str:
    rows = "".join(f"<tr><td>{e(a['id'])}</td><td>{e(a['type'])}</td><td><a href=\"{rel(a['path'], depth)}\">{e(a['path'])}</a></td><td>{e(a['description'])}</td></tr>" for a in artifacts)
    return f"<table><thead><tr><th>ID</th><th>Type</th><th>Path</th><th>Description</th></tr></thead><tbody>{rows}</tbody></table>"


def action_list(actions: list[dict[str, str]]) -> str:
    items = "".join(f"<li><strong>{e(a['title'])}</strong><br><span class=\"muted\">{e(a.get('status', ''))} - {e(a.get('owner', ''))}</span></li>" for a in actions)
    return f"<ol>{items}</ol>"


def badge(value: str) -> str:
    return f"<span class=\"badge badge-{slugify(value)}\">{e(value)}</span>"


def rel(path: str, depth: int) -> str:
    if path.startswith(("http://", "https://", "../", "./")):
        return path
    return ("../" * depth) + path


def e(value: str) -> str:
    return html.escape(str(value), quote=True)


def stylesheet() -> str:
    return """
:root { color-scheme: light; --ink: #182026; --muted: #5d6872; --line: #d7dee5; --soft: #f5f7f9; --accent: #146c94; --warn: #a35400; --ok: #1f7a4d; }
* { box-sizing: border-box; }
body { margin: 0; font: 16px/1.5 -apple-system, BlinkMacSystemFont, "SF Pro Text", "Segoe UI", sans-serif; color: var(--ink); background: #ffffff; }
main { max-width: 1180px; margin: 0 auto; padding: 28px 18px 64px; }
a { color: var(--accent); text-decoration-thickness: 1px; text-underline-offset: 3px; }
nav { display: flex; flex-wrap: wrap; gap: 10px; margin-bottom: 18px; }
nav a, .badge { border: 1px solid var(--line); border-radius: 999px; padding: 4px 10px; text-decoration: none; }
.hero { border-bottom: 3px solid var(--ink); padding: 18px 0 22px; margin-bottom: 24px; }
.eyebrow { color: var(--accent); font-weight: 700; text-transform: uppercase; letter-spacing: 0; margin: 0 0 6px; }
h1 { font-size: clamp(2rem, 4vw, 4rem); line-height: 1; margin: 0 0 12px; letter-spacing: 0; }
h2 { font-size: 1.35rem; margin: 36px 0 12px; }
h3 { font-size: 1.05rem; margin: 0 0 8px; }
section { margin: 24px 0; }
table { width: 100%; border-collapse: collapse; border: 1px solid var(--line); margin: 12px 0; }
th, td { text-align: left; vertical-align: top; border-bottom: 1px solid var(--line); padding: 9px 10px; }
th { background: var(--soft); font-size: 0.9rem; }
dl { display: grid; grid-template-columns: minmax(120px, 220px) 1fr; gap: 8px 14px; }
dt { font-weight: 700; }
dd { margin: 0; }
.stats { display: grid; grid-template-columns: repeat(auto-fit, minmax(150px, 1fr)); gap: 12px; }
.stats div { border: 1px solid var(--line); padding: 14px; }
.stats strong { display: block; font-size: 2rem; }
.stats span, .muted { color: var(--muted); }
.report-section { border-top: 1px solid var(--line); padding: 16px 0; }
.badge-incomplete { color: var(--warn); border-color: #d98f32; background: #fff7eb; }
.badge-pass { color: var(--ok); border-color: #71b894; background: #effaf4; }
.badge-fail { color: #9d2727; border-color: #d78585; background: #fff0f0; }
.link-list { columns: 2 280px; }
@media (max-width: 720px) { main { padding: 18px 12px 48px; } table { display: block; overflow-x: auto; } dl { grid-template-columns: 1fr; } }
"""
