//! Tests for the SQLite durable sidecar (`podcast_knowledge::sqlite`).

use std::io::Write;

use podcast_transcripts::TranscriptChunk;

use crate::sqlite::KnowledgeSqliteStore;
use crate::types::{EmbeddingVector, KnowledgeChunk};

fn make_chunk(episode_id: &str, idx: u32, text: &str) -> KnowledgeChunk {
    KnowledgeChunk::without_embedding(TranscriptChunk {
        episode_id: episode_id.to_owned(),
        chunk_index: idx,
        start_secs: idx as f64 * 10.0,
        end_secs: idx as f64 * 10.0 + 9.9,
        word_count: text.split_whitespace().count() as u32,
        text: text.to_owned(),
    })
}

fn make_chunk_with_embedding(episode_id: &str, idx: u32, embedding: Vec<f32>) -> KnowledgeChunk {
    KnowledgeChunk::with_embedding(
        TranscriptChunk {
            episode_id: episode_id.to_owned(),
            chunk_index: idx,
            start_secs: 0.0,
            end_secs: 9.9,
            word_count: 5,
            text: "chunk with embedding".to_owned(),
        },
        EmbeddingVector::new(embedding),
    )
}

/// Round-trip: insert chunks, drop the store, reopen on same path, load_all
/// must return the same chunks in the same order.
#[test]
fn durability_round_trip() {
    let dir = tempfile::tempdir().expect("tempdir");
    let db_path = dir.path().join("knowledge.sqlite");

    let chunk_a = make_chunk("ep-1", 0, "hello world machine learning");
    let chunk_b = make_chunk("ep-1", 1, "deep neural networks podcast");
    let chunk_c = make_chunk("ep-2", 0, "another episode chunk");

    // Session 1: write chunks.
    {
        let store = KnowledgeSqliteStore::open(&db_path);
        store.upsert(&chunk_a).unwrap();
        store.upsert(&chunk_b).unwrap();
        store.upsert(&chunk_c).unwrap();
    }
    // `store` dropped — connection closed.

    // Session 2: reopen and load_all.
    {
        let store2 = KnowledgeSqliteStore::open(&db_path);
        let mut loaded = store2.load_all();
        // Sort for deterministic comparison (SQLite has no guaranteed order).
        loaded.sort_by(|a, b| {
            a.chunk.episode_id.cmp(&b.chunk.episode_id)
                .then(a.chunk.chunk_index.cmp(&b.chunk.chunk_index))
        });

        assert_eq!(loaded.len(), 3, "must reload all 3 chunks");

        assert_eq!(loaded[0].chunk.episode_id, "ep-1");
        assert_eq!(loaded[0].chunk.chunk_index, 0);
        assert_eq!(loaded[0].chunk.text, "hello world machine learning");

        assert_eq!(loaded[1].chunk.episode_id, "ep-1");
        assert_eq!(loaded[1].chunk.chunk_index, 1);
        assert_eq!(loaded[1].chunk.text, "deep neural networks podcast");

        assert_eq!(loaded[2].chunk.episode_id, "ep-2");
        assert_eq!(loaded[2].chunk.chunk_index, 0);
        assert_eq!(loaded[2].chunk.text, "another episode chunk");
    }
}

/// Embedding round-trip: a chunk with an `EmbeddingVector` serialises to BLOB
/// and deserialises back to the same f32 values.
#[test]
fn embedding_round_trip() {
    let dir = tempfile::tempdir().expect("tempdir");
    let db_path = dir.path().join("knowledge_emb.sqlite");

    let emb = vec![0.1_f32, 0.2, 0.3, -0.4, 0.5];
    let chunk = make_chunk_with_embedding("ep-emb", 0, emb.clone());

    {
        let store = KnowledgeSqliteStore::open(&db_path);
        store.upsert(&chunk).unwrap();
    }

    {
        let store2 = KnowledgeSqliteStore::open(&db_path);
        let loaded = store2.load_all();
        assert_eq!(loaded.len(), 1);
        let ev = loaded[0].embedding.as_ref().expect("embedding must be present");
        assert_eq!(ev.dim(), emb.len());
        for (got, expected) in ev.as_slice().iter().zip(&emb) {
            assert!(
                (got - expected).abs() < 1e-6,
                "f32 round-trip mismatch: got {got}, expected {expected}"
            );
        }
    }
}

/// Upsert idempotency: upserting the same `(episode_id, chunk_index)` a second
/// time replaces the row rather than duplicating it.
#[test]
fn upsert_replaces_existing_row() {
    let dir = tempfile::tempdir().expect("tempdir");
    let db_path = dir.path().join("knowledge_upsert.sqlite");

    let store = KnowledgeSqliteStore::open(&db_path);
    store.upsert(&make_chunk("ep-u", 0, "original text")).unwrap();
    store.upsert(&make_chunk("ep-u", 0, "updated text")).unwrap();

    let loaded = store.load_all();
    assert_eq!(loaded.len(), 1, "upsert must not duplicate rows");
    assert_eq!(loaded[0].chunk.text, "updated text");
}

/// delete_episode removes all rows for the given episode and only those rows.
#[test]
fn delete_episode_removes_only_that_episode() {
    let dir = tempfile::tempdir().expect("tempdir");
    let db_path = dir.path().join("knowledge_del.sqlite");

    let store = KnowledgeSqliteStore::open(&db_path);
    store.upsert(&make_chunk("ep-del", 0, "chunk zero")).unwrap();
    store.upsert(&make_chunk("ep-del", 1, "chunk one")).unwrap();
    store.upsert(&make_chunk("ep-keep", 0, "keep me")).unwrap();

    store.delete_episode("ep-del").unwrap();

    let loaded = store.load_all();
    assert_eq!(loaded.len(), 1, "only ep-keep must remain");
    assert_eq!(loaded[0].chunk.episode_id, "ep-keep");
}

/// Corrupt-file quarantine: writing garbage bytes to the DB path must not
/// panic.  The resulting store is an empty in-memory fallback; the corrupt
/// file is renamed to `<path>.corrupt-<ts>`.
#[test]
fn corrupt_file_quarantined() {
    let dir = tempfile::tempdir().expect("tempdir");
    let db_path = dir.path().join("knowledge_corrupt.sqlite");

    // Write garbage so Connection::open succeeds but migration fails (or
    // the file is not a valid SQLite header).
    {
        let mut f = std::fs::File::create(&db_path).expect("create file");
        f.write_all(b"this is definitely not a sqlite database!!!!!").unwrap();
    }
    assert!(db_path.exists(), "garbage file must exist before open");

    // Must not panic.
    let store = KnowledgeSqliteStore::open(&db_path);

    // In-memory fallback: empty store.
    let chunks = store.load_all();
    assert!(chunks.is_empty(), "corrupt-file fallback must be empty");

    // Corrupt file must have been quarantined (renamed away).
    assert!(
        !db_path.exists(),
        "original corrupt file must be renamed/quarantined"
    );

    // A `.corrupt-<ts>` sibling must exist.
    let siblings: Vec<_> = std::fs::read_dir(dir.path())
        .unwrap()
        .filter_map(|e| e.ok())
        .map(|e| e.file_name().to_string_lossy().into_owned())
        .collect();
    let quarantine_exists = siblings
        .iter()
        .any(|name| name.starts_with("knowledge_corrupt.sqlite.corrupt-"));
    assert!(quarantine_exists, "quarantine file must exist; found: {siblings:?}");
}

/// Rename of the former `replace_episode_chunks_is_atomic` — this asserts the
/// happy-path final row set (full replacement), not rollback.
#[test]
fn replace_episode_chunks_replaces_full_set() {
    let dir = tempfile::tempdir().expect("tempdir");
    let db_path = dir.path().join("knowledge_replace.sqlite");
    let store = KnowledgeSqliteStore::open(&db_path);

    // Seed 3 chunks.
    store.upsert(&make_chunk("ep-1", 0, "old zero")).unwrap();
    store.upsert(&make_chunk("ep-1", 1, "old one")).unwrap();
    store.upsert(&make_chunk("ep-1", 2, "old two")).unwrap();

    // Replace with a single new chunk.
    store
        .replace_episode_chunks("ep-1", &[make_chunk("ep-1", 0, "new only")])
        .unwrap();

    let loaded = store.load_all();
    assert_eq!(loaded.len(), 1, "replace must leave exactly the new set");
    assert_eq!(loaded[0].chunk.text, "new only");
}

/// Real rollback proof: a transaction shaped like `replace_episode_chunks`
/// that aborts on the Nth INSERT (CHECK violation) must leave the prior
/// committed rows untouched — no partial write.
#[test]
fn transaction_rolls_back_leaving_no_partial_state() {
    use rusqlite::{params, Connection};

    let conn = Connection::open_in_memory().unwrap();
    // A table with a CHECK that the failing row violates.
    conn.execute_batch(
        "CREATE TABLE t (
             episode_id TEXT NOT NULL,
             chunk_index INTEGER NOT NULL CHECK (chunk_index >= 0),
             text TEXT NOT NULL,
             PRIMARY KEY (episode_id, chunk_index)
         );",
    )
    .unwrap();

    // Prior committed state: one row for a DIFFERENT episode that must survive.
    conn.execute(
        "INSERT INTO t (episode_id, chunk_index, text) VALUES ('keep', 0, 'survivor')",
        [],
    )
    .unwrap();

    // Transaction shaped like replace_episode_chunks: DELETE target + INSERT batch,
    // where the 2nd INSERT violates the CHECK (chunk_index = -1) and aborts.
    let result: Result<(), rusqlite::Error> = (|| {
        let tx = conn.unchecked_transaction()?;
        tx.execute("DELETE FROM t WHERE episode_id = ?1", params!["keep"])?;
        tx.execute(
            "INSERT INTO t (episode_id, chunk_index, text) VALUES ('keep', 0, 'rewrite')",
            [],
        )?;
        // This violates CHECK (chunk_index >= 0) → aborts the transaction.
        tx.execute(
            "INSERT INTO t (episode_id, chunk_index, text) VALUES ('keep', -1, 'bad')",
            [],
        )?;
        tx.commit()
    })();

    assert!(result.is_err(), "the bad INSERT must error out");

    // The original survivor row must be intact — the DELETE + first INSERT
    // rolled back with the failed transaction (no partial write).
    let count: i64 = conn
        .query_row("SELECT COUNT(*) FROM t", [], |r| r.get(0))
        .unwrap();
    assert_eq!(count, 1, "exactly the original committed row survives");
    let text: String = conn
        .query_row(
            "SELECT text FROM t WHERE episode_id = 'keep' AND chunk_index = 0",
            [],
            |r| r.get(0),
        )
        .unwrap();
    assert_eq!(text, "survivor", "the row must be the pre-transaction value, not 'rewrite'");
}

/// replace_episode_chunks with empty slice leaves zero rows for the episode.
#[test]
fn replace_episode_chunks_empty_slice_clears_episode() {
    let dir = tempfile::tempdir().expect("tempdir");
    let db_path = dir.path().join("replace_empty.sqlite");

    let store = KnowledgeSqliteStore::open(&db_path);
    store.upsert(&make_chunk("ep-2", 0, "keep")).unwrap();
    store.upsert(&make_chunk("ep-clear", 0, "will be gone")).unwrap();

    store.replace_episode_chunks("ep-clear", &[]).unwrap();

    let loaded = store.load_all();
    assert_eq!(loaded.len(), 1);
    assert_eq!(loaded[0].chunk.episode_id, "ep-2");
}

/// upsert_embedding attaches to a NULL-embedding row.
#[test]
fn upsert_embedding_attaches_to_null_row() {
    let dir = tempfile::tempdir().expect("tempdir");
    let db_path = dir.path().join("upsert_emb.sqlite");

    let store = KnowledgeSqliteStore::open(&db_path);
    store.upsert(&make_chunk("ep-emb", 0, "some text")).unwrap();

    let emb: Vec<f32> = (0..1024).map(|i| i as f32 / 1024.0).collect();
    let ev = EmbeddingVector::new(emb.clone());
    store.upsert_embedding("ep-emb", 0, "some text", &ev).unwrap();

    let loaded = store.load_all();
    assert_eq!(loaded.len(), 1);
    let got = loaded[0].embedding.as_ref().expect("embedding must be present");
    assert_eq!(got.dim(), 1024);
    for (got_v, exp_v) in got.as_slice().iter().zip(&emb) {
        assert!((got_v - exp_v).abs() < 1e-6, "value mismatch");
    }
}

/// Race guard: if a chunk's text changed (concurrent re-ingest) between the
/// embed-task spawn and its write-back, `upsert_embedding` guarded on the
/// captured text must NOT bind the stale embedding — the row stays NULL.
#[test]
fn upsert_embedding_skips_when_text_changed() {
    let dir = tempfile::tempdir().expect("tempdir");
    let db_path = dir.path().join("knowledge_race.sqlite");
    let store = KnowledgeSqliteStore::open(&db_path);

    // Persist a NULL-embedding chunk with text "A" (the text the embed task captured).
    store.upsert(&make_chunk("ep-race", 0, "text A")).unwrap();

    // Simulate a concurrent re-ingest that replaced the row with text "B".
    store
        .replace_episode_chunks("ep-race", &[make_chunk("ep-race", 0, "text B")])
        .unwrap();

    // Late embed write-back keyed on the STALE captured text "text A".
    let stale = EmbeddingVector::new(vec![0.5_f32; 1024]);
    store
        .upsert_embedding("ep-race", 0, "text A", &stale)
        .unwrap();

    // The stale embedding must NOT have landed — text mismatch → zero rows updated.
    let loaded = store.load_all();
    assert_eq!(loaded.len(), 1);
    assert_eq!(loaded[0].chunk.text, "text B", "current text must be B");
    assert!(
        loaded[0].embedding.is_none(),
        "stale embedding for text A must NOT bind to the text-B row (stays NULL)"
    );

    // And a fresh write-back keyed on the CURRENT text "text B" must succeed.
    let fresh = EmbeddingVector::new(vec![0.25_f32; 1024]);
    store
        .upsert_embedding("ep-race", 0, "text B", &fresh)
        .unwrap();
    let loaded2 = store.load_all();
    let ev = loaded2[0].embedding.as_ref().expect("fresh embedding must bind");
    assert_eq!(ev.dim(), 1024);
}

/// null_embedding_chunks returns only NULL rows and respects limit.
#[test]
fn null_embedding_chunks_returns_only_null_rows_and_respects_limit() {
    let dir = tempfile::tempdir().expect("tempdir");
    let db_path = dir.path().join("null_emb.sqlite");

    let store = KnowledgeSqliteStore::open(&db_path);
    store.upsert(&make_chunk("ep-a", 0, "no emb 1")).unwrap();
    store.upsert(&make_chunk("ep-a", 1, "no emb 2")).unwrap();
    store.upsert(&make_chunk("ep-a", 2, "no emb 3")).unwrap();
    // One chunk WITH embedding.
    store
        .upsert(&make_chunk_with_embedding("ep-a", 3, vec![1.0_f32; 4]))
        .unwrap();

    let null_rows = store.null_embedding_chunks(2);
    assert_eq!(null_rows.len(), 2, "limit must be respected");
    // None of the returned rows should be chunk_index=3 (which has an embedding).
    for (_, idx) in &null_rows {
        assert_ne!(*idx, 3, "embedded chunk must not appear in null list");
    }
}

/// 1024-dim round-trip via replace_episode_chunks.
#[test]
fn replace_episode_chunks_1024_dim_round_trip() {
    let dir = tempfile::tempdir().expect("tempdir");
    let db_path = dir.path().join("replace_1024.sqlite");

    let store = KnowledgeSqliteStore::open(&db_path);
    let emb: Vec<f32> = (0..1024).map(|i| (i as f32) * 0.001).collect();
    let chunk = make_chunk_with_embedding("ep-rt", 0, emb.clone());
    store.replace_episode_chunks("ep-rt", &[chunk]).unwrap();

    let loaded = store.load_all();
    assert_eq!(loaded.len(), 1);
    let got = loaded[0].embedding.as_ref().expect("embedding must be present");
    assert_eq!(got.dim(), 1024);
    for (got_v, exp_v) in got.as_slice().iter().zip(&emb) {
        assert!((got_v - exp_v).abs() < 1e-5, "bit mismatch: {got_v} vs {exp_v}");
    }
}
