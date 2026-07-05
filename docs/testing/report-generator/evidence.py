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
        normalize_observed_record(record)


def normalize_observed_record(record: dict[str, Any]) -> None:
    if record["execution"]["status"] == "not_run":
        return
    normalize_coherence(record)
    normalize_readiness(record)
    normalize_observed_sections(record)


def normalize_coherence(record: dict[str, Any]) -> None:
    scenario = record["scenario"]
    status = record["execution"]["status"]
    evidence_refs = observed_evidence_refs(record)
    if status == "fail":
        individual_status = "fail"
        individual_summary = (
            f"{scenario['id']} has current run evidence and currently fails its "
            "scenario-level product job; linked defects and revalidation remain required."
        )
    elif status == "pass_with_issues":
        individual_status = "pass_with_issues"
        individual_summary = (
            f"{scenario['id']} has current run evidence for the exercised product path, "
            "with remaining gaps tracked in missing evidence and follow-up."
        )
    else:
        individual_status = "incomplete"
        individual_summary = (
            f"{scenario['id']} has partial current run evidence, but required branches "
            "remain unvalidated."
        )

    record["coherence"]["individual_judgment"] = {
        "status": individual_status,
        "summary": individual_summary,
        "checks": [
            "observed scenario-level UI polish",
            "observed scenario-level UX polish",
            "observed performance/accessibility evidence",
            "scenario-level product fit",
        ],
        "evidence_refs": evidence_refs,
        "gaps": missing_evidence_labels(record),
    }
    record["coherence"]["group_judgment"] = {
        "status": "incomplete",
        "summary": (
            f"{record['coherence']['cluster']['title']} cluster coherence remains incomplete "
            f"until adjacent scenarios are judged together; {scenario['id']} now contributes "
            "current evidence and linked defects to that group view."
        ),
        "checks": [
            "related scenario consistency",
            "shared defect themes",
            "cluster readiness",
            "cross-flow state continuity",
        ],
        "evidence_refs": sorted(set(evidence_refs + ["rubric:review-skill-grounding"])),
        "gaps": ["Review adjacent scenario pages as a cluster before promoting group coherence."],
    }


def normalize_readiness(record: dict[str, Any]) -> None:
    status = record["execution"]["status"]
    missing = missing_evidence_labels(record)
    issue_ids = [issue["id"] for issue in record["issues"]]
    evidence_refs = observed_evidence_refs(record)
    record["readiness"]["ship_gate"] = "blocked" if status == "fail" else "incomplete"
    blockers = []
    if status == "fail":
        blockers.append("Current run evidence contains a functional failure that must be fixed and revalidated.")
    if issue_ids:
        blockers.append(f"Linked open defect(s): {', '.join(issue_ids)}.")
    if missing:
        blockers.append(f"Remaining missing evidence: {', '.join(missing)}.")
    blockers.append("Related scenario cluster coherence remains incomplete until adjacent pages are reviewed together.")
    record["readiness"]["blocking_reasons"] = blockers

    for gate in record["readiness"]["gates"]:
        gate_id = gate["id"]
        if gate_id == "required_evidence":
            gate["status"] = "pass_with_issues" if missing else "pass"
            gate["evidence_refs"] = evidence_refs
        elif gate_id == "skill_grounding":
            gate["status"] = "pass"
            gate["evidence_refs"] = ["rubric:review-skill-grounding"]
        elif gate_id == "score_integrity":
            gate["status"] = "pass_with_issues"
            gate["evidence_refs"] = evidence_refs
        elif gate_id == "product_coherence":
            gate["status"] = "incomplete"
            gate["evidence_refs"] = sorted(set(evidence_refs + ["rubric:review-skill-grounding"]))
        elif gate_id == "defect_tracking":
            gate["status"] = "pass_with_issues" if issue_ids else "incomplete"
            gate["evidence_refs"] = evidence_refs
        elif gate_id == "release_readiness":
            gate["status"] = "blocked" if status == "fail" or issue_ids else "incomplete"
            gate["evidence_refs"] = evidence_refs


def normalize_observed_sections(record: dict[str, Any]) -> None:
    refs = observed_evidence_refs(record)
    artifact_count = len([artifact for artifact in record["evidence"]["artifacts"] if not artifact["id"].startswith("catalog:")])
    fixed_issues = [issue for issue in record["issues"] if issue["status"] == "fixed"]
    open_issues = [issue for issue in record["issues"] if issue["status"] == "open"]
    record["sections"]["product_coherence_in_context"] = section(
        record["coherence"]["individual_judgment"]["summary"],
        refs,
        record["coherence"]["individual_judgment"]["gaps"],
    )
    record["sections"]["product_cluster_coherence"] = section(
        record["coherence"]["group_judgment"]["summary"],
        record["coherence"]["group_judgment"]["evidence_refs"],
        record["coherence"]["group_judgment"]["gaps"],
    )
    record["sections"]["readiness_gates"] = section(
        f"Ship gate is {record['readiness']['ship_gate']}; gates now reflect attached evidence, remaining missing evidence, linked defects, and cluster-level follow-up.",
        refs,
        record["readiness"]["blocking_reasons"],
    )
    record["sections"]["evidence_provenance"] = section(
        f"{artifact_count} non-catalog artifact(s) are attached with their published IDs, paths, redaction metadata, and run context.",
        refs,
        missing_evidence_labels(record),
    )
    record["sections"]["before_after_deltas"] = section(
        "Current evidence must be read as before/action/after deltas across the flow steps; any missing pair remains listed in instrumentation gaps.",
        refs,
        missing_evidence_labels(record),
    )
    record["sections"]["revalidation_status"] = section(
        f"{len(fixed_issues)} fixed issue(s) and {len(open_issues)} open issue(s) are linked; fixed issues require revalidation run IDs before closure is considered proven.",
        refs,
        [issue["id"] for issue in record["issues"] if not issue.get("revalidation_run_id")],
    )
    record["sections"]["owner_status"] = section(
        "Readiness gates, instrumentation gaps, risks, issues, and next actions carry owner/status fields for follow-through.",
        refs,
        record["readiness"]["blocking_reasons"],
    )


def observed_evidence_refs(record: dict[str, Any]) -> list[str]:
    refs = []
    for artifact in record["evidence"]["artifacts"]:
        artifact_id = artifact["id"]
        if artifact_id.startswith("catalog:"):
            continue
        refs.append(artifact_id)
    return sorted(set(refs))


def missing_evidence_labels(record: dict[str, Any]) -> list[str]:
    return [item["kind"] for item in record["evidence"]["missing"]]


def section(summary: str, refs: list[str], notes: list[str] | None = None) -> dict[str, Any]:
    return {"summary": summary, "evidence_refs": sorted(set(refs)), "notes": notes or []}


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
