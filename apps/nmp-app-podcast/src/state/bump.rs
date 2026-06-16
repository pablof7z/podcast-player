//! [`BumpHandle`] — the capture-safe snapshot-bump primitive.
//!
//! Split out of `state/mod.rs` to keep that file under the 500-line hard
//! ceiling (AGENTS.md).  See the type docs for why a background task must
//! capture this rather than a full [`Infra`](super::Infra).

use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::Arc;

use crate::snapshot_signal::SnapshotUpdateSignal;

use super::{Domain, DomainRevs};

/// A clonable snapshot-bump primitive that carries the rev/signal/domain-rev
/// counters but **not** the `Arc<Runtime>`.
///
/// This is the capture-safe slice of [`Infra`](super::Infra) for code that runs
/// **inside** a task spawned on `infra.runtime`.  Capturing a full `Infra` there
/// would keep the runtime alive via its own task (a self-reference cycle), so
/// the runtime would never drop and the task would outlive the owning `NmpApp`
/// → use-after-free.
///
/// `BumpHandle::bump` is the single canonical bump implementation;
/// [`Infra::bump`](super::Infra::bump) delegates to it.
#[derive(Clone)]
pub struct BumpHandle {
    rev: Arc<AtomicU64>,
    signal: Option<SnapshotUpdateSignal>,
    domain_revs: Arc<DomainRevs>,
    domain: Domain,
}

impl BumpHandle {
    /// Construct a bump handle from the individual `Infra` primitives.
    /// `pub(crate)` so only [`Infra::bump_handle`](super::Infra::bump_handle)
    /// (and tests) build one — the canonical source of the field values.
    pub(crate) fn new(
        rev: Arc<AtomicU64>,
        signal: Option<SnapshotUpdateSignal>,
        domain_revs: Arc<DomainRevs>,
        domain: Domain,
    ) -> Self {
        Self {
            rev,
            signal,
            domain_revs,
            domain,
        }
    }

    /// Bump the snapshot rev — both the global rev AND the scoped domain rev.
    ///
    /// Identical semantics to the former inline body of
    /// [`Infra::bump`](super::Infra::bump): advance the domain counter first (so
    /// a consumer reading the frame produced by the global-rev tick observes the
    /// matching domain delta), then either post `MarkChangedSinceEmit` via the
    /// signal (production) or `fetch_add` the global rev directly (tests with no
    /// signal).
    pub fn bump(&self) {
        self.domain_revs
            .counter(self.domain)
            .fetch_add(1, Ordering::Relaxed);
        match &self.signal {
            Some(s) => s.bump(),
            None => {
                self.rev.fetch_add(1, Ordering::Relaxed);
            }
        }
    }
}
