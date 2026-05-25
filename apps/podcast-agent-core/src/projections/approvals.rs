//! Pending-approvals projection helpers.
//!
//! The state itself lives inside [`crate::projections::ConversationActor`] —
//! conversations and approvals share a logical owner (an approval is
//! always attached to a conversation). This module exposes a thin
//! read-side façade so the snapshot serializer + UI can pull a
//! deterministic, sorted view without re-implementing the predicate.

use chrono::{DateTime, Utc};

use crate::types::PendingApproval;

/// Sorted, expiration-filtered view over a slice of [`PendingApproval`].
///
/// `now` is supplied by the caller so the projection layer can run in
/// the kernel tick (which owns the wall clock) without this helper
/// implicitly calling `Utc::now()`.
///
/// Approvals are returned in `requested_at` ascending order — the UI
/// renders oldest-first so users handle the queue in arrival order.
pub fn sorted_active_approvals(
    approvals: &[PendingApproval],
    now: DateTime<Utc>,
) -> Vec<PendingApproval> {
    let mut out: Vec<PendingApproval> = approvals
        .iter()
        .filter(|a| !a.is_expired_at(now))
        .cloned()
        .collect();
    out.sort_by_key(|a| a.requested_at);
    out
}

#[cfg(test)]
mod tests {
    use super::*;
    use uuid::Uuid;

    fn ts(secs: i64) -> DateTime<Utc> {
        DateTime::<Utc>::from_timestamp(secs, 0).unwrap()
    }

    fn approval(secs: i64, expires: Option<i64>) -> PendingApproval {
        PendingApproval {
            id: Uuid::new_v4(),
            conversation_id: Uuid::nil(),
            action_description: format!("action @ {secs}"),
            requested_at: ts(secs),
            expires_at: expires.map(ts),
        }
    }

    #[test]
    fn sorts_by_requested_at_ascending() {
        let approvals = vec![approval(30, None), approval(10, None), approval(20, None)];
        let out = sorted_active_approvals(&approvals, ts(0));
        assert_eq!(out.len(), 3);
        assert_eq!(out[0].requested_at, ts(10));
        assert_eq!(out[1].requested_at, ts(20));
        assert_eq!(out[2].requested_at, ts(30));
    }

    #[test]
    fn drops_expired_approvals() {
        let approvals = vec![
            approval(10, Some(15)),     // expired at now=100
            approval(20, None),         // no expiry → always active
            approval(30, Some(1_000)),  // expires at 1_000, still active at now=100
            approval(40, Some(40)),     // boundary: expires_at == now → expired
        ];
        let out = sorted_active_approvals(&approvals, ts(100));
        assert_eq!(out.len(), 2);
        assert_eq!(out[0].requested_at, ts(20));
        assert_eq!(out[1].requested_at, ts(30));
    }
}
