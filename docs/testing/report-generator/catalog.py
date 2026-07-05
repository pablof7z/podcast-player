from __future__ import annotations

import re
import textwrap
from dataclasses import dataclass
from pathlib import Path


ROW_RE = re.compile(r"^\|\s*([A-Z0-9]+-\d{3})\s*\|\s*(.*?)\s*\|\s*(.*?)\s*\|\s*$")
BDD_RE = re.compile(r"^Given (.*), when (.*), then (.*)\.?$", re.IGNORECASE)


@dataclass(frozen=True)
class Scenario:
    order: int
    scenario_id: str
    slug: str
    title: str
    category: str
    category_slug: str
    source_path: str
    source_file: str
    source_line: int
    sentence: str
    bdd: dict[str, list[str]]
    evidence: dict[str, str]
    tags: list[str]
    boundaries: list[str]
    dependencies: list[str]
    cassettes: list[str]
    provider_mode: str
    performance_required: bool


def slugify(value: str) -> str:
    slug = re.sub(r"[^a-z0-9]+", "-", value.lower()).strip("-")
    return re.sub(r"-+", "-", slug) or "unknown"


def parse_catalog(catalog_dir: Path) -> list[Scenario]:
    scenarios: list[Scenario] = []
    for path in sorted(p for p in catalog_dir.glob("*.md") if p.name != "INDEX.md"):
        category = ""
        for lineno, line in enumerate(path.read_text().splitlines(), 1):
            if line.startswith("## "):
                category = line[3:].strip()
                continue
            match = ROW_RE.match(line)
            if not match:
                continue
            scenario_id, sentence, evidence_cell = match.groups()
            bdd = parse_bdd(sentence)
            evidence = parse_evidence(evidence_cell)
            boundaries = split_boundaries(evidence.get("boundary", ""))
            cassettes = extract_cassettes(evidence.get("deps", ""))
            category_slug = slugify(category)
            scenarios.append(
                Scenario(
                    order=len(scenarios) + 1,
                    scenario_id=scenario_id,
                    slug=slugify(scenario_id),
                    title=title_from_bdd(bdd),
                    category=category,
                    category_slug=category_slug,
                    source_path=f"{path.as_posix()}:{lineno}",
                    source_file=path.name,
                    source_line=lineno,
                    sentence=sentence,
                    bdd=bdd,
                    evidence=evidence,
                    tags=tags_for(scenario_id, category_slug, evidence, boundaries),
                    boundaries=boundaries,
                    dependencies=[evidence["deps"]] if evidence.get("deps") else [],
                    cassettes=cassettes,
                    provider_mode=provider_mode_for(evidence),
                    performance_required=evidence.get("perf", "").lower() not in {"", "none"},
                )
            )
    expected = parse_expected_total(catalog_dir / "INDEX.md")
    if expected is not None and expected != len(scenarios):
        raise ValueError(f"Catalog INDEX declares {expected} scenarios but parsed {len(scenarios)}")
    if not scenarios:
        raise ValueError(f"No scenarios parsed from {catalog_dir}")
    return scenarios


def parse_expected_total(index_path: Path) -> int | None:
    if not index_path.exists():
        return None
    match = re.search(r"\|\s*\*\*Total\*\*\s*\|\s*\*\*(\d+)\*\*", index_path.read_text())
    return int(match.group(1)) if match else None


def parse_evidence(cell: str) -> dict[str, str]:
    result: dict[str, str] = {}
    for part in cell.strip().rstrip(".").split(";"):
        if ":" not in part:
            continue
        key, value = part.split(":", 1)
        result[key.strip().lower()] = value.strip().strip(".")
    return result


def parse_bdd(sentence: str) -> dict[str, list[str]]:
    match = BDD_RE.match(sentence)
    if not match:
        raise ValueError(f"Could not parse BDD sentence: {sentence}")
    given, when, then = (part.strip().rstrip(".") for part in match.groups())
    return {"given": [given], "when": [when], "then": [then]}


def title_from_bdd(bdd: dict[str, list[str]]) -> str:
    raw = bdd["then"][0].strip()
    title = raw[:1].upper() + raw[1:]
    return textwrap.shorten(title, width=96, placeholder="...")


def split_boundaries(value: str) -> list[str]:
    if not value or value.lower() == "none":
        return []
    return [item.strip() for item in re.split(r",|\band\b", value) if item.strip()]


def extract_cassettes(text: str) -> list[str]:
    cassettes = re.findall(r"`([^`]*cassettes/[^`]*)`", text)
    if "cassette" in text.lower() and not cassettes:
        cassettes.append(slugify(text))
    return cassettes


def provider_mode_for(evidence: dict[str, str]) -> str:
    deps = evidence.get("deps", "").lower()
    provider_tokens = ["cassette", "provider", "llm", "stt", "tts"]
    return "blocked" if any(token in deps for token in provider_tokens) else "none"


def tags_for(scenario_id: str, category_slug: str, evidence: dict[str, str], boundaries: list[str]) -> list[str]:
    tags = {scenario_id.split("-", 1)[0].lower(), category_slug, "catalog-scaffold"}
    if evidence.get("ss", "").lower() not in {"", "none"}:
        tags.add("visual-evidence-required")
    if evidence.get("perf", "").lower() not in {"", "none"}:
        tags.add("performance-required")
    deps = evidence.get("deps", "").lower()
    if "cassette" in deps:
        tags.add("cassette-required")
    if any(token in deps for token in ["relay", "nostr", "nip-"]):
        tags.add("nostr-or-relay")
    for boundary in boundaries:
        tags.add(slugify(boundary))
    return sorted(tags)
