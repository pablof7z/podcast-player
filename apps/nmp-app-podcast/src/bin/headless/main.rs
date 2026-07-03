//! Headless scenario test binary for `nmp-app-podcast`.
//!
//! Boots the full NMP + Podcast kernel via the app-owned `PodcastApp` facade,
//! installs a real HTTP
//! capability host (reqwest), runs scripted scenarios, and exits 0 (all pass
//! or skip) or 1 (any failure).
//!
//! Usage:
//!   cargo run -p nmp-app-podcast --bin headless --features headless

mod capability_host;
mod fixtures;
mod harness;
mod mock_feed;
mod relay_client;
mod scenarios;
mod sign_tap;

use std::process::ExitCode;
use std::sync::Arc;

use nmp_app_podcast::ffi::PodcastApp;

fn main() -> ExitCode {
    // 1. Boot the app-owned UniFFI facade.
    let app = PodcastApp::new();

    // 2. Install the headless capability host (real HTTP, no-op stubs for
    //    audio/download/notification).
    capability_host::install(Arc::clone(&app));

    // 2b. Install the signed-event capture tap (update-frame callback) BEFORE
    //     start, so the nipf4_publish scenario can observe the kernel's signed
    //     output via the `signed_events` push projection. See sign_tap.rs.
    sign_tap::install(Arc::clone(&app));

    // 4. Set a temp data dir so store serialisation has somewhere to write.
    let temp_dir = tempfile::tempdir().expect("tempdir");
    app.set_podcast_data_dir(
        temp_dir
            .path()
            .to_str()
            .expect("temp dir is UTF-8")
            .to_owned(),
    );

    // 5. Declare the explicit all-builtins projection intent, then start the
    //    kernel actor. Visible-limit and emit-hz are test defaults.
    app.consume_all_builtin_projections();
    app.start(500, 10);

    // 6. Run all scenarios.
    let results = scenarios::run_all(&app);

    // 7. Print results.
    let mut any_fail = false;
    for (name, result) in &results {
        let label = result.label();
        match result {
            scenarios::ScenarioResult::Pass => {
                println!("{label:<6} {name}");
            }
            scenarios::ScenarioResult::Skip(reason) => {
                println!("{label:<6} {name} ({reason})");
            }
            scenarios::ScenarioResult::Fail(reason) => {
                println!("{label:<6} {name}: {reason}");
                any_fail = true;
            }
        }
    }

    // 8. Tear down.
    app.shutdown();

    if any_fail {
        ExitCode::FAILURE
    } else {
        ExitCode::SUCCESS
    }
}
