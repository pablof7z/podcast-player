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

`data/skill-grounding.json` records the review-skill scaffold that each scenario
page requires before product-quality scores can rise above `2`.
