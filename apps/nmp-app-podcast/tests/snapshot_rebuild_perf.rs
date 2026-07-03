//! Populated-library measurement of the merged perf stack (#264 off-main decode,
//! #265 audio rev-discipline + clean_html memo).
//!
//! Unlike `snapshot_transport_perf.rs` (which serializes hand-built structs),
//! this drives a REAL kernel handle through the `PodcastApp` UniFFI facade and a seeded library, so
//! it measures the actual `build_snapshot_payload` rebuild (store lock + map all
//! episodes + clean_html) and empirically verifies the rev-discipline:
//!   - a `Playing` position tick must NOT bump `rev` (no rebuild during playback);
//!   - a `Paused` / `star_episode` (durable change) MUST bump `rev` (one rebuild).
//!
//! Heavy (seeds thousands of episodes via per-episode dispatch), so it's
//! `#[ignore]` by default. Run explicitly:
//!   cargo test -p nmp-app-podcast --test snapshot_rebuild_perf --release -- --ignored --nocapture

use std::time::Instant;

use nmp_app_podcast::ffi::PodcastApp;

const DESCRIPTION: &str = "In this episode we sit down with our guest to unpack the \
week's biggest stories, dig into the research behind the headlines, and answer \
listener questions from the mailbag. We cover the new findings, what they mean for \
you, and where the experts disagree. Plus: a lightning round, a few tangents, and \
our picks of the week. Full show notes and transcript on our website.";

fn dispatch(app: &PodcastApp, payload: serde_json::Value) -> serde_json::Value {
    // ADR-0064: route through the typed byte doorway.
    let body = payload.to_string();
    match app.dispatch_action_json_for_rust("podcast", &body) {
        Ok(correlation_id) => serde_json::json!({ "correlation_id": correlation_id }),
        Err(error) => serde_json::json!({ "error": error }),
    }
}

/// Count episodes in the current snapshot by decoding the projected payload.
fn episode_count(app: &PodcastApp) -> usize {
    let json = app.podcast_snapshot().unwrap_or_else(|| "{}".to_owned());
    serde_json::from_str::<nmp_app_podcast::ffi::PodcastUpdate>(&json)
        .map(|u| u.library.iter().map(|p| p.episodes.len()).sum())
        .unwrap_or(0)
}

/// `create_podcast`/`add_episode` are processed asynchronously on the kernel
/// actor thread, so a dispatch returns before the store write lands. Poll until
/// the library reaches `expected` episodes (or `timeout_ms` elapses).
fn wait_for_seed(app: &PodcastApp, expected: usize, timeout_ms: u128) -> usize {
    let t = Instant::now();
    loop {
        let c = episode_count(app);
        if c >= expected || t.elapsed().as_millis() > timeout_ms {
            return c;
        }
        std::thread::sleep(std::time::Duration::from_millis(50));
    }
}

/// Pull the full snapshot (the build+serialize the iOS pull path pays) and
/// return (payload_bytes, micros).
fn timed_snapshot(app: &PodcastApp) -> (usize, u128) {
    let t = Instant::now();
    let payload = app.podcast_snapshot();
    let us = t.elapsed().as_micros();
    (payload.as_deref().map(str::len).unwrap_or(0), us)
}

fn uuid(n: usize, salt: u8) -> String {
    format!(
        "{:08x}-{:04x}-4{:03x}-8{:03x}-{:012x}",
        n,
        salt as u32,
        n & 0xfff,
        n & 0xfff,
        n
    )
}

fn seed(app: &PodcastApp, shows: usize, eps_per_show: usize) {
    for s in 0..shows {
        let pid = uuid(s, 0xAA);
        dispatch(
            app,
            serde_json::json!({
                "op": "create_podcast",
                "podcast_id": pid,
                "title": format!("The Reasonably Named Podcast Number {s}"),
                "description": DESCRIPTION,
                "author": "A Reasonably Named Production Company, LLC",
                "feed_url": format!("https://feeds.example.com/show-{s}/rss.xml"),
            }),
        );
        for i in 0..eps_per_show {
            let n = s * eps_per_show + i;
            dispatch(
                app,
                serde_json::json!({
                    "op": "add_episode",
                    "podcast_id": pid,
                    "episode_id": uuid(n, 0xBB),
                    "title": format!("Episode {n}: A Reasonably Long Episode Title"),
                    "enclosure_url": format!("https://traffic.example.com/{pid}/ep-{n}.mp3"),
                    "description": DESCRIPTION,
                    "duration_secs": 3600.0 + n as f64,
                }),
            );
        }
    }
}

#[test]
#[ignore = "heavy populated-library measurement; run with --ignored --nocapture"]
fn measure_populated_library_rebuild_and_rev_discipline() {
    let shows = 20usize;
    for &per in &[50usize, 180] {
        // Fresh app per scale so payloads don't accumulate across iterations.
        let app = PodcastApp::new();
        let total = shows * per;
        let t0 = Instant::now();
        seed(&app, shows, per);
        // Seeding is async on the actor thread — wait until the library is fully
        // populated before measuring, else we time a half-built library.
        let seeded = wait_for_seed(&app, total, 120_000);
        let seed_s = t0.elapsed().as_secs_f64();
        assert_eq!(
            seeded, total,
            "library did not fully seed ({seeded}/{total})"
        );

        // Warm the snapshot cache at the fully-seeded rev.
        let (payload_bytes, _) = timed_snapshot(&app);
        let first_ep = uuid(0, 0xBB);

        // COLD rebuild cost: a durable change (star) invalidates the rev-keyed
        // snapshot cache, so the next pull pays the full `build_podcast_update`
        // (store lock + map all episodes + memoized clean_html) + serialize.
        // star_episode is async on the actor — WAIT for rev to advance before
        // timing, else the snapshot returns the still-valid cached payload.
        // Median of several real rebuilds (toggle star each round).
        let mut cold: Vec<u128> = Vec::new();
        let mut warm: Vec<u128> = Vec::new();
        for _ in 0..7 {
            let r = app.podcast_snapshot_rev();
            dispatch(
                &app,
                serde_json::json!({"op": "star_episode", "episode_id": first_ep}),
            );
            let t = Instant::now();
            while app.podcast_snapshot_rev() == r && t.elapsed().as_millis() < 5000 {
                std::thread::sleep(std::time::Duration::from_millis(1));
            }
            // Let the actor fully drain (persist-to-disk etc.) so the rebuild
            // timing isn't contaminated by store-lock contention.
            std::thread::sleep(std::time::Duration::from_millis(150));
            let (_, us_cold) = timed_snapshot(&app); // cache miss → real rebuild
            let (_, us_warm) = timed_snapshot(&app); // cache hit
            cold.push(us_cold);
            warm.push(us_warm);
        }
        cold.sort_unstable();
        warm.sort_unstable();

        println!(
            "\n[{} shows x {} eps = {} episodes]  seed={:.1}s  payload={:.1} KB",
            shows,
            per,
            total,
            seed_s,
            payload_bytes as f64 / 1024.0
        );
        println!(
            "  full snapshot build+serialize (cold rebuild, median): {} µs",
            cold[cold.len() / 2]
        );
        println!(
            "  snapshot (warm, rev-unchanged cache hit, median):     {} µs",
            warm[warm.len() / 2]
        );

        // ── #265 rev-discipline: a Playing tick must NOT bump rev ───────────
        let rev_before = app.podcast_snapshot_rev();
        let play = serde_json::json!({"type":"playing","url":"https://traffic.example.com/x.mp3",
                "position_secs": 12.0, "duration_secs": 3600.0})
        .to_string();
        let _ = app.audio_report(play);
        let rev_after_play = app.podcast_snapshot_rev();

        // A durable report (Paused) MUST bump rev.
        let pause = serde_json::json!({"type":"paused","url":"https://traffic.example.com/x.mp3",
                "position_secs": 12.0})
        .to_string();
        let _ = app.audio_report(pause);
        let rev_after_pause = app.podcast_snapshot_rev();

        println!(
            "  rev before={} after_Playing={} after_Paused={}",
            rev_before, rev_after_play, rev_after_pause
        );
        assert_eq!(
            rev_before, rev_after_play,
            "#265 REGRESSION: a Playing position tick bumped rev (forces a full rebuild)"
        );
        assert!(
            rev_after_pause > rev_after_play,
            "a durable Paused report must bump rev so the library reprojects"
        );
        println!("  ✓ Playing tick did NOT bump rev (no rebuild); Paused did.");
    }
}
