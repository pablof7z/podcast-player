from __future__ import annotations

import json
import sys
import tempfile
import unittest
from pathlib import Path

GENERATOR_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(GENERATOR_DIR))

from architecture_scan_report import architecture_scan_data, render_architecture_scan_page  # noqa: E402


class ArchitectureScanReportTests(unittest.TestCase):
    def test_architecture_scan_report_renders_hard_error_issue_links(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            evidence = Path(temp) / "evidence"
            evidence.mkdir()
            (evidence / "nmp-architecture-scan-20260707T230200Z.json").write_text(
                json.dumps(
                    {
                        "scan_id": "nmp-architecture-scan-20260707T230200Z",
                        "generated_at": "2026-07-07T23:02:00Z",
                        "source_commit": "7098b7d9",
                        "scanner": {"command": "python3 nmp_architecture_scan.py --json --limit 0 ."},
                        "status": "blocked",
                        "counts": {
                            "total": 2,
                            "by_severity": {"error": 2},
                            "by_rule": {"D8/no-polling": 1, "D3/no-hardcoded-relay": 1},
                            "hard_errors": 2,
                        },
                        "linked_issues": [
                            {
                                "id": "GH-740",
                                "url": "https://github.com/pablof7z/podcast-player/issues/740",
                                "scope": "D8 burn-down",
                                "rules": ["D8/no-polling"],
                            },
                            {
                                "id": "GH-741",
                                "url": "https://github.com/pablof7z/podcast-player/issues/741",
                                "scope": "D3 burn-down",
                                "rules": ["D3/no-hardcoded-relay"],
                            },
                        ],
                        "top_rules": [
                            {
                                "rule": "D8/no-polling",
                                "severity": "error",
                                "count": 1,
                                "reason": "Polling or sleep-check loops are forbidden.",
                            }
                        ],
                        "hard_error_findings": [
                            {
                                "severity": "error",
                                "rule": "D8/no-polling",
                                "path": "App/Sources/Design/Haptics.swift",
                                "line": 76,
                                "match": "try? await Task.sleep(for: AppTheme.Timing.hapticTwoBeat)",
                                "reason": "Polling or sleep-check loops are forbidden.",
                            },
                            {
                                "severity": "error",
                                "rule": "D3/no-hardcoded-relay",
                                "path": "apps/podcast-tui/src/ui/settings.rs",
                                "line": 111,
                                "match": "wss://relay",
                                "reason": "Hardcoded relay URLs usually bypass outbox routing.",
                            },
                        ],
                        "findings": [],
                    }
                )
            )

            data = architecture_scan_data(evidence)
            self.assertEqual(data["counts"]["hard_errors"], 2)
            page = render_architecture_scan_page(data, 1)
            self.assertIn("NMP Architecture Scan", page)
            self.assertIn("GH-740", page)
            self.assertIn("GH-741", page)
            self.assertIn("App/Sources/Design/Haptics.swift:76", page)


if __name__ == "__main__":
    unittest.main()
