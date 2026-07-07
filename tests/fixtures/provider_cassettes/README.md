# Provider Cassettes

These fixtures are deterministic, redacted provider envelopes for Pod0
validation. They let agents and CI replay provider-backed scenarios without
live LLM, STT, TTS, search, or relay credentials.

Verify them with:

```bash
cargo run -p nmp-app-podcast --bin provider-cassettes -- verify tests/fixtures/provider_cassettes
```

Contract:

- `body_sha256` is SHA-256 over the canonical JSON request body.
- `fingerprint` is SHA-256 over provider, operation, method, URL, and canonical
  body. Authorization headers are intentionally excluded from the fingerprint.
- Secrets must be represented only as redacted markers.
- `metrics` records both observed live latency and deterministic replay latency.
- Every cassette lists current generated BDD catalog IDs in `scenario_refs`
  (for example `TR-005`, not legacy hand-authored refs such as `E2`). Use
  suite-wide refs such as `LLM-012` or `OFFLINE-008` only when the fixture
  materially contributes to that replay/sanitizer gate.
- Every cassette lists NMP doctrine rules in `nmp_rules` that the replay helps
  validate.
