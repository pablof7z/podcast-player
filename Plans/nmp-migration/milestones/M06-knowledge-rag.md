# M6 — Knowledge / RAG

**Status:** unclaimed
**Scale:** L
**Depends on:** M5
**Blocks:** M7, M9
**Parallel work units:** 5

---

## Scope

`nmp.vector.capability` lands. `podcast-knowledge` orchestrates RAG
(vector + BM25 hybrid in Rust; raw KNN/BM25 from capability),
embeddings/reranker calls, wiki generation/verification.

**Per Codex review:** the capability surface is raw primitives only
(`KnnSearch`, `BM25Search`). `QueryHybrid` does not exist as a
capability — hybrid ranking + reranking are Rust policy.

Existing wiki pages + vector index migrated.

---

## Pre-flight

- [ ] M5 exit green.
- [ ] Confirm BACKLOG `cap-vector` ADR done.
- [ ] R11 decision: adopt sqlite-vec in place (no re-index) vs.
      background re-index. Default: adopt-in-place.

---

## Parallel work units

### Unit M6.A — `nmp.vector.capability` Rust + ADR

**Tasks:**
- [ ] `OpenIndex`, `Upsert`, `Delete`, `KnnSearch`, `BM25Search`,
      `Compact`.
- [ ] **No `QueryHybrid`** in capability.
- [ ] Android stub: ObjectBox or sqlite-vec on Android sketch.
- [ ] Web stub: IndexedDB-vec.

### Unit M6.B — `podcast-knowledge::rag`

**Tasks:**
- [ ] Hybrid search: KNN top-K + BM25 top-K + RRF (Reciprocal Rank
      Fusion).
- [ ] Reranker via OpenRouter / Cohere using `nmp.http.capability`
      (orchestration in Rust).
- [ ] Embedding generation via OpenRouter or local Ollama (capability
      negotiates HTTP only).

**Quality gates:**
- [ ] Unit tests cover RRF math + scope filtering.

### Unit M6.C — `podcast-knowledge::wiki`

**Tasks:**
- [ ] Port `WikiGenerator`, `WikiVerifier`, `WikiResponseParser`,
      `WikiPrompts`, `WikiTriggers`, `WikiStorage`.
- [ ] Wiki refresh decisions (when to regenerate).

**Quality gates:**
- [ ] Prompt-template snapshots match legacy.

### Unit M6.D — iOS VectorCapability executor

**Tasks:**
- [ ] `Capabilities/VectorCapability.swift` wraps existing
      sqlite-vec actor.
- [ ] Strict no-policy: no ranking, no scoring, no filtering beyond
      what the SQL request specifies.
- [ ] Adopt-in-place migration: opens legacy `vectors.sqlite` and
      validates schema; if compatible, uses as-is; if not, files toast
      and proceeds with empty (background re-index queued).

**Quality gates:**
- [ ] Search performance on a 10k-chunk index ≤ 200ms p99.

### Unit M6.E — UI: Wiki tab, Search, EpisodeDetail RAG hooks

Files:
- `App/Sources/Features/Wiki/*.swift`
- `App/Sources/Features/Wiki/WikiHomeViewModel.swift` (split — class
  excised).
- `App/Sources/Features/Search/*.swift`
- `App/Sources/Features/Search/PodcastSearchViewModel.swift` (split).

**Tasks:**
- [ ] Tooling: copy → split → token-swap → fidelity.
- [ ] Wiki render binds to `wiki_page` projection with citations.
- [ ] Search renders `rag_search_result` projection.

**Quality gates:**
- [ ] Goldens match.

---

## Sequential integration

- [ ] Merge A → B → C → D → E order.
- [ ] Live test: open Wiki tab, search a topic, see citations
      peek-to-source on a real episode.

---

## Exit checklist

- [ ] Semantic search returns results identical (or improved) vs.
      legacy.
- [ ] Wiki pages render with citations.
- [ ] `query_transcripts` and `query_wiki` agent tools (used in M7)
      have working underlying services.
- [ ] **Swift files deleted:**
  - `App/Sources/Knowledge/*.swift` (all 21)
  - `App/Sources/Services/RAGService.swift`, `RAGService+Adapters.swift`
  - `App/Sources/Services/WikiRefreshExecutor.swift`
  - `App/Sources/Features/Wiki/WikiHomeViewModel.swift` (class part)
  - `App/Sources/Features/Search/PodcastSearchViewModel.swift` (class part)
- [ ] M7 unblocked.

## Hand-off to M7

M7 can rely on: chunk search, wiki gen, embeddings, reranking all
working server-side from Rust. Agent tools `query_transcripts` /
`query_wiki` have backing services.
