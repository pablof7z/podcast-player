# Pod0 Scenario Report Generator

This generator turns the BDD catalog in `docs/testing/scenarios/catalog/` into a
static report site with one page and one `data.json` record per scenario.

Run it from the repository root:

```sh
python3 docs/testing/report-generator/generate_scenario_report.py \
  --out build/pod0-scenario-report
```

Evidence-backed scenario records live under `docs/testing/evidence/`. The
generator reads `docs/testing/evidence/scenario-records/*.json` as overlays on
top of catalog-derived scaffold records, copies
`docs/testing/evidence/assets/` into the generated `assets/` directory, and
keeps untouched catalog rows scaffolded as `incomplete`.

The generator is intentionally strict:

- The catalog `INDEX.md` total must match the parsed row count.
- Every catalog row must parse as `Given ..., when ..., then ...`.
- Every generated scenario record must contain all required sections and scores
  from `docs/testing/scenario-report.schema.json`.
- Every generated scenario page is `incomplete` until real screenshots, UI
  trees, metrics, cassettes, accessibility evidence, UI/UX critique, and issue
  links are attached.
- Artifact paths in generated JSON must exist in the generated site.
- Rollup counts must agree with per-scenario records.

The generated site includes:

- `scenarios/<scenario-id>/index.html`
- `scenarios/<scenario-id>/data.json`
- `scenarios/index.html`
- category index pages under `scenarios/<category>/`
- tag pages under `tags/<tag>/`
- rollups for verdict, provider mode, NMP boundary, performance requirements,
  and issues
- JSON rollups under `data/`

Each scenario record also includes structured `product_context`, `flow_steps`,
`execution`, `review_grounding`, `quality_review`, `coherence`, `readiness`,
`evidence.missing`, `instrumentation_gaps`, and `risks` fields. These are
intentionally first-class JSON fields so future importers can populate observed
runs without scraping prose.

## Review Skill Grounding

This pass used:

```sh
npx skills search "iOS UI polish Apple Human Interface Guidelines accessibility UX performance mobile design review Liquid Glass"
npx skills use alirezarezvani/claude-skills@apple-hig-expert
npx skills use vabole/apple-skills@ios-liquid-glass
```

The local `web-design-guidelines` skill was also loaded and its current Web
Interface Guidelines were fetched. `data/skill-grounding.json` records these
selected skills and the template impact:

- Apple HIG Expert: 44 pt targets, contrast, Dynamic Type, VoiceOver, safe
  areas, semantic colors, SF typography, and iPhone navigation ergonomics.
- iOS Liquid Glass: hierarchy, harmony, consistency, control-layer glass use,
  and Reduce Motion/Transparency behavior.
- Web Interface Guidelines: semantic static pages, skip links, focus states,
  reduced motion, readable tables, overflow-safe content, and report-page
  accessibility/performance.

UI, UX, accessibility, performance, and product-coherence scores must stay at
`2` or below until the relevant evidence and grounded critique are attached.
