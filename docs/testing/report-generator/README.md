# Pod0 Scenario Report Generator

This generator turns the BDD catalog in `docs/testing/scenarios/catalog/` into a
static report site with one page and one `data.json` record per scenario.

Run it from the repository root:

```sh
python3 docs/testing/report-generator/generate_scenario_report.py \
  --out build/pod0-scenario-report
```

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
- preserved `assets/` content when regenerating over an existing Pages checkout
- preserved evidence-bearing per-scenario `data.json` fields when an existing
  record uses the same schema
- copied repo screenshots from `docs/images/` and `docs/testing/scenarios/` into
  the existing Pages asset path conventions

Each scenario record also includes structured `product_context`, `flow_steps`,
`execution`, `review_grounding`, `quality_review`, `coherence`, `readiness`,
`evidence.missing`, `instrumentation_gaps`, and `risks` fields. These are
intentionally first-class JSON fields so future importers can populate observed
runs without scraping prose.

## Review Skill Grounding

This pass used:

```sh
npx skills search "liquid glass iOS primitives mobile frontend design UI polish UX"
npx skills use vabole/apple-skills@ios-liquid-glass
npx skills use phazurlabs/ux-ui-mastery --skill "Mobile UX Design"
```

`data/skill-grounding.json` records these selected skills and the template
impact:

- iOS Liquid Glass: hierarchy, harmony, consistency, control-layer glass use,
  GlassEffect composition, semantic foreground styles, and Reduce
  Motion/Transparency behavior.
- Mobile UX Design: mobile-first task focus, iOS navigation conventions, touch
  ergonomics, interruption recovery, state resilience, and performance-as-UX
  budgets.

UI, UX, accessibility, performance, and product-coherence scores must stay at
`2` or below until the relevant evidence and grounded critique are attached.

## Regression Tests

Run the focused generator contract tests with:

```sh
python3 -m unittest docs/testing/report-generator/tests/test_generator_contract.py
```

The tests assert that generation creates a home page plus per-scenario pages and
`data.json` records, required deep-review sections are present, selected skill
metadata is preserved, and existing Pages assets/issues/evidence-bearing scenario
records survive regeneration.
