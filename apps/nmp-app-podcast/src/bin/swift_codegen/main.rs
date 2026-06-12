//! swift-codegen — emit `App/Sources/Bridge/Generated/*.generated.swift`
//! from the Rust projection type definitions.
//!
//! ## Approach
//!
//! This is a **hand-rolled emitter**: the type manifests are encoded here as
//! Rust data structures, in direct correspondence to the Rust projection types
//! in `src/ffi/projections/` and `src/player/state.rs`. The emitter writes
//! Swift `Decodable` structs that mirror those Rust structs.
//!
//! Why hand-rolled (not schemars)?
//! 1. `schemars` would add a heavy derive-macro dep to the main crate — bad
//!    for cross-compile (Android, iOS) build times and dependency surface.
//! 2. The Swift files have non-trivial custom decode logic (property wrappers,
//!    `decodeIfPresent` with explicit defaults) that schemars schema → Swift
//!    cannot reproduce without a bespoke schema→Swift transform anyway.
//! 3. A hand-rolled manifest is explicit and auditable: every field is
//!    listed, defaults are documented, and diffs are readable.
//!
//! ## Contract
//!
//! The emitter enforces the critical wire contract:
//! - Swift fields are **camelCase** with NO explicit `CodingKeys` enum, except
//!   `PodcastSettingsSnapshot` — see below.
//! - The decoder uses `.convertFromSnakeCase`, so camelCase Swift ↔
//!   snake_case Rust is handled automatically.
//! - Explicit snake_case `CodingKeys` = the #371 freeze hazard; the emitter
//!   never emits them for the auto-camelCase types.
//!
//! ## SettingsSnapshot — the one explicit-CodingKeys type
//!
//! `PodcastSettingsSnapshot.generated.swift` IS now generated. It is the single
//! type that carries a full explicit `CodingKeys` enum: most keys are
//! auto-camelCase, but ~15 fields override to raw snake_case (e.g.
//! `ollama_chat_url`, `stt_provider`, `assembly_ai_*`) and the BYOK credential
//! ID/label fields use uppercase acronyms (`...BYOKKeyID`) whose
//! `.convertFromSnakeCase` round-trip lands on a different converted key. Its
//! custom `init(from:)` seeds every field from `self.init()` (the canonical
//! default mirror of the kernel's `PodcastStore::new()`) and overwrites only the
//! keys present on the wire, so an absent key keeps its default and the decoder
//! can never throw `keyNotFound`. The drift gate covers it like every other
//! Generated/ file.
//!
//! ## Usage
//!
//!   cargo run -p nmp-app-podcast --bin swift-codegen -- \
//!       --out ../../App/Sources/Bridge/Generated
//!
//! (The `--out` default is the project-relative path used by CI.)

use std::path::PathBuf;

mod types;
mod emit;

fn main() {
    let args: Vec<String> = std::env::args().collect();

    // Parse optional --out <dir>
    let out_dir: PathBuf = {
        let mut d = None;
        let mut i = 1;
        while i < args.len() {
            if args[i] == "--out" && i + 1 < args.len() {
                d = Some(PathBuf::from(&args[i + 1]));
                i += 2;
            } else {
                i += 1;
            }
        }
        d.unwrap_or_else(|| {
            // Default: resolve relative to the manifest dir (where Cargo.toml is).
            // This allows `cargo run` from the workspace root to still find the
            // right target directory.
            let manifest = std::env::var("CARGO_MANIFEST_DIR")
                .unwrap_or_else(|_| ".".to_string());
            PathBuf::from(manifest)
                .join("../../App/Sources/Bridge/Generated")
        })
    };

    println!("swift-codegen: writing generated files to {}", out_dir.display());

    std::fs::create_dir_all(&out_dir)
        .expect("failed to create output directory");

    for (filename, content) in emit::all_files() {
        let path = out_dir.join(filename);
        let existing = std::fs::read_to_string(&path).unwrap_or_default();
        if existing == content {
            println!("  unchanged: {filename}");
        } else {
            std::fs::write(&path, &content)
                .unwrap_or_else(|e| panic!("failed to write {}: {e}", path.display()));
            println!("  updated:   {filename}");
        }
    }

    println!("swift-codegen: done.");
}
