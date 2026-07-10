//! Rev-gated cache for the threading projection build.
//!
//! Split out of `threading_projection.rs` to keep that file under the
//! AGENTS.md 500-line hard cap (the rev-cache rekeying pushed it over).
//! Reaches back into the parent module (`super::`) for the shared types
//! (`EpisodeThreadInput`, `ThreadingProjection`) and builders
//! (`collect_thread_inputs`, `build_projection`) — private items of a
//! module are visible to its child modules, so no visibility widening was
//! needed to make this split.

use std::sync::atomic::Ordering;
use std::sync::Arc;

use super::{build_projection, collect_thread_inputs, EpisodeThreadInput, ThreadingProjection};
use crate::ffi::handle::PodcastHandle;

/// Fetch the `(inputs, projection)` pair for the library's current rev,
/// rebuilding only on a cache miss.
///
/// `build_projection` scans every episode (categorization + candidate-mention
/// selection) and `collect_thread_inputs` clones each episode's transcript
/// data — real work that both FFI entry points need, and that HomeView's
/// `.task` blocks can trigger several times per launch as the library and
/// categorizer cache settle.
///
/// Keyed by `domain_revs.library` (podcasts + episodes + categories + inbox),
/// NOT the global `state.infra.rev`. The global rev bumps on every domain's
/// mutation — including `Domain::Playback` position ticks, which fire at
/// `emitHz` (4/sec) whenever something is playing. On a real ~2k-episode
/// library the cold rebuild here measured ~1s; keying off the global rev
/// meant a single playback tick during that window invalidated an
/// already-fresh cache entry, so this could cold-rebuild several times in
/// the first ~15s of a session even though the library itself hadn't
/// changed. `domain_revs.library` only advances on an actual library-content
/// mutation (see `state/domain.rs`), so the common case is one rebuild per
/// genuine change instead of one per unrelated tick anywhere in the app.
///
/// Known gap: LLM-assisted background categorization
/// (`categorization.rs::bump_background_rev`) bumps only the global rev, not
/// `domain_revs.library` — a categorization completing while this cache is
/// warm won't invalidate it until some other library-domain mutation
/// happens to follow. This is a pre-existing narrow staleness window (LLM
/// categorization is opt-in/credentialed, already async, and was never
/// synchronized with this cache even under the old global-rev key in the
/// sense that the two could race); tracked as a follow-up rather than
/// blocking this fix, which addresses the dominant (steady 4 Hz) source of
/// over-invalidation.
///
/// Returns `None` only if the store mutex is poisoned.
pub(super) fn projection_and_inputs_for_current_rev(
    handle: &PodcastHandle,
) -> Option<(Arc<Vec<EpisodeThreadInput>>, Arc<ThreadingProjection>)> {
    let rev = handle.state.infra.domain_revs.library.load(Ordering::Relaxed);
    if let Ok(cache) = handle.threading_projection_cache.lock() {
        if let Some((cached_rev, ref inputs, ref projection)) = *cache {
            if cached_rev == rev {
                return Some((Arc::clone(inputs), Arc::clone(projection)));
            }
        }
    }

    let categories = handle.state.categories.categories_snapshot();
    let inputs = {
        let store = handle.state.library.store.lock().ok()?;
        collect_thread_inputs(&store, handle)
    };
    let projection = build_projection(inputs.clone(), &categories);
    let inputs = Arc::new(inputs);
    let projection = Arc::new(projection);

    if let Ok(mut cache) = handle.threading_projection_cache.lock() {
        *cache = Some((rev, Arc::clone(&inputs), Arc::clone(&projection)));
    }
    Some((inputs, projection))
}
