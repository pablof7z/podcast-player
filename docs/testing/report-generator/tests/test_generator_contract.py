from __future__ import annotations

import json
import sys
import tempfile
import unittest
from pathlib import Path

GENERATOR_DIR = Path(__file__).resolve().parents[1]
DOCS_TESTING_DIR = GENERATOR_DIR.parent
sys.path.insert(0, str(GENERATOR_DIR))

from catalog import parse_catalog  # noqa: E402
from contract import SKILL_GROUNDING  # noqa: E402
from generate_scenario_report import write_site  # noqa: E402
from records import build_report, validate_schema_contract  # noqa: E402


GENERATED_AT = "2026-07-05T00:00:00Z"
SITE_BASE = "https://example.test/podcast-player/"

REQUIRED_SCENARIO_SECTIONS = [
    "What Was Attempted And Test Intent",
    "Flow Overview And Steps",
    "Results And Verdict",
    "UI Polish Report",
    "UX Polish Report",
    "Performance Metrics And Interaction Latency",
    "Product Coherence And Cluster Judgment",
    "Product-Level Assessment",
    "Data And Control-Plane Setup",
    "Navigation, Orientation, And Information Architecture",
    "Animation, Transition, And Haptics Quality",
    "Risk Severity And Validation Confidence",
]


class ScenarioReportGeneratorTests(unittest.TestCase):
    def test_generates_index_and_required_per_scenario_pages(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            catalog = write_catalog(root / "catalog")
            out = root / "site"

            records = build_records(catalog, root)
            validate_schema_contract(records, DOCS_TESTING_DIR / "scenario-report.schema.json")
            write_site(records, out, catalog, root)

            self.assertTrue((out / "index.html").exists())
            self.assertTrue((out / "scenarios" / "index.html").exists())
            self.assertTrue((out / "scenarios" / "smoke-001" / "index.html").exists())
            self.assertTrue((out / "scenarios" / "smoke-001" / "data.json").exists())
            self.assertTrue((out / "scenarios" / "smoke-002" / "index.html").exists())
            self.assertEqual(len(list((out / "scenarios").glob("*/data.json"))), 2)

            home = (out / "index.html").read_text()
            scenario_page = (out / "scenarios" / "smoke-001" / "index.html").read_text()
            self.assertNotIn("Required Detailed Sections", home)
            for section in REQUIRED_SCENARIO_SECTIONS:
                self.assertIn(section, scenario_page)

            data = json.loads((out / "scenarios" / "smoke-001" / "data.json").read_text())
            self.assertEqual(data["page"]["canonical_url"], "https://example.test/podcast-player/scenarios/smoke-001/")
            self.assertEqual(data["review_grounding"]["search_command"], 'npx skills search "liquid glass iOS primitives mobile frontend design UI polish UX"')
            self.assertEqual(
                [skill["name"] for skill in SKILL_GROUNDING if skill["selected"]],
                ["vabole/apple-skills@ios-liquid-glass", "phazurlabs/ux-ui-mastery@Mobile UX Design"],
            )

    def test_preserves_existing_pages_assets_and_issue_index(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            catalog = write_catalog(root / "catalog")
            out = root / "site"
            old_asset = out / "assets" / "scenarios" / "smoke-001" / "old-shot.jpg"
            old_asset.parent.mkdir(parents=True)
            old_asset.write_bytes(b"old image")
            old_issues = {"issues": [{"id": "ISSUE-1", "url": "https://example.test/1"}], "counts": {"open": 1, "fixed": 0}}
            (out / "data").mkdir()
            (out / "data" / "issues.json").write_text(json.dumps(old_issues))

            records = build_records(catalog, root)
            old_record = dict(records[0])
            old_record["execution"] = {**old_record["execution"], "status": "pass"}
            old_record["metrics"] = [
                {
                    "id": "metric-screen-settle",
                    "name": "Screen settle",
                    "value": 120,
                    "unit": "ms",
                    "budget": "<200ms",
                    "status": "pass",
                    "method": "fixture",
                    "evidence_refs": ["artifact:old-shot"],
                }
            ]
            old_record["evidence"] = {
                **old_record["evidence"],
                "artifacts": [
                    *old_record["evidence"]["artifacts"],
                    {
                        "id": "artifact:old-shot",
                        "type": "screenshot",
                        "path": "assets/scenarios/smoke-001/old-shot.jpg",
                        "description": "Previous validated screenshot.",
                        "required": True,
                        "redaction": {"status": "not_needed"},
                    },
                ],
            }
            previous_record_path = out / "scenarios" / "smoke-001" / "data.json"
            previous_record_path.parent.mkdir(parents=True)
            previous_record_path.write_text(json.dumps(old_record))

            write_site(records, out, catalog, root)

            self.assertEqual(old_asset.read_bytes(), b"old image")
            self.assertEqual(json.loads((out / "data" / "issues.json").read_text()), old_issues)
            merged = json.loads(previous_record_path.read_text())
            self.assertEqual(merged["execution"]["status"], "pass")
            self.assertEqual(merged["metrics"][0]["id"], "metric-screen-settle")
            self.assertIn("artifact:old-shot", {artifact["id"] for artifact in merged["evidence"]["artifacts"]})


def write_catalog(catalog: Path) -> Path:
    catalog.mkdir(parents=True)
    (catalog / "INDEX.md").write_text("| Group | Count |\n|---|---:|\n| **Total** | **2** |\n")
    (catalog / "01-smoke.md").write_text(
        "\n".join(
            [
                "# Smoke Catalog",
                "",
                "## Smoke And Report Shape",
                "",
                "| ID | Scenario | Evidence |",
                "|---|---|---|",
                "| SMOKE-001 | Given a seeded library, when the listener opens Library, then subscribed shows render with stable navigation. | ss: library screenshot; perf: screen settle metric; deps: seeded library; boundary: D1,D5. |",
                "| SMOKE-002 | Given offline mode, when the listener opens a cached show, then cached episodes remain available. | ss: offline screenshot; perf: none; deps: offline fixture; boundary: D5. |",
            ]
        )
        + "\n"
    )
    return catalog


def build_records(catalog: Path, repo: Path) -> list[dict[str, object]]:
    scenarios = parse_catalog(catalog)
    return [build_report(scenario, scenarios, repo, GENERATED_AT, SITE_BASE) for scenario in scenarios]


if __name__ == "__main__":
    unittest.main()
