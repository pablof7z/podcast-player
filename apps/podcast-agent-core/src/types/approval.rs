//! Pending-approval domain.
//!
//! When the agent wants to perform a side-effecting action (publish a clip,
//! send a DM, delete a note, …) the orchestration layer parks a
//! [`PendingApproval`] on the conversation. The UI renders an approval
//! sheet; the user either accepts ([`ApprovalDecision::Approved`]) or
//! refuses with an optional reason ([`ApprovalDecision::Denied`]).
//!
//! Approvals are first-class projection state — they live alongside
//! conversations in the [`crate::projections::ConversationActor`].

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

/// One outstanding "ask" the agent has parked for human review.
///
/// `expires_at` is optional: approvals that never expire (e.g. background
/// briefings the user finds the next morning) leave it `None`; time-bound
/// approvals (e.g. "send this DM in the next 60s") supply an absolute
/// deadline. The projection layer culls expired approvals at decision
/// time — there is no separate sweep task.
#[derive(Clone, Debug, Deserialize, PartialEq, Serialize)]
pub struct PendingApproval {
    pub id: Uuid,
    pub conversation_id: Uuid,
    /// Human-readable summary the approval sheet renders verbatim.
    pub action_description: String,
    pub requested_at: DateTime<Utc>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub expires_at: Option<DateTime<Utc>>,
}

impl PendingApproval {
    /// Constructor that stamps `id` + `requested_at`. Tests that need
    /// deterministic ids should build the struct literally.
    pub fn new(conversation_id: Uuid, action_description: impl Into<String>) -> Self {
        Self {
            id: Uuid::new_v4(),
            conversation_id,
            action_description: action_description.into(),
            requested_at: Utc::now(),
            expires_at: None,
        }
    }

    /// Return whether the approval has expired relative to `now`.
    ///
    /// `now` is taken as a parameter so projection code (which runs in
    /// the kernel tick) can supply a stable clock without this type
    /// implicitly calling `Utc::now()`.
    pub fn is_expired_at(&self, now: DateTime<Utc>) -> bool {
        match self.expires_at {
            Some(deadline) => now >= deadline,
            None => false,
        }
    }
}

/// What the user said about a [`PendingApproval`].
#[derive(Clone, Debug, Deserialize, PartialEq, Serialize)]
#[serde(tag = "kind", rename_all = "snake_case")]
pub enum ApprovalDecision {
    /// User accepted; the orchestration layer should fire the side
    /// effect now.
    Approved,
    /// User refused. `reason` is the optional free-form text the
    /// sheet collects — surfaced back into the conversation transcript
    /// so the agent has context for follow-ups.
    Denied {
        #[serde(default, skip_serializing_if = "Option::is_none")]
        reason: Option<String>,
    },
}

#[cfg(test)]
mod tests {
    use super::*;

    fn ts(secs: i64) -> DateTime<Utc> {
        DateTime::<Utc>::from_timestamp(secs, 0).unwrap()
    }

    #[test]
    fn pending_approval_round_trips() {
        let a = PendingApproval {
            id: Uuid::nil(),
            conversation_id: Uuid::nil(),
            action_description: "publish clip".into(),
            requested_at: ts(1_700_000_000),
            expires_at: Some(ts(1_700_001_000)),
        };
        let j = serde_json::to_string(&a).expect("encode");
        let d: PendingApproval = serde_json::from_str(&j).expect("decode");
        assert_eq!(d, a);
    }

    #[test]
    fn pending_approval_omits_none_expiry() {
        let a = PendingApproval::new(Uuid::nil(), "noop");
        let j = serde_json::to_string(&a).expect("encode");
        assert!(!j.contains("\"expires_at\""));
    }

    #[test]
    fn approval_decision_serde_tag() {
        let approved = ApprovalDecision::Approved;
        let j = serde_json::to_string(&approved).expect("encode");
        assert_eq!(j, r#"{"kind":"approved"}"#);

        let denied = ApprovalDecision::Denied {
            reason: Some("too risky".into()),
        };
        let j = serde_json::to_string(&denied).expect("encode");
        assert_eq!(j, r#"{"kind":"denied","reason":"too risky"}"#);

        let denied_none = ApprovalDecision::Denied { reason: None };
        let j = serde_json::to_string(&denied_none).expect("encode");
        assert_eq!(j, r#"{"kind":"denied"}"#);
    }

    #[test]
    fn approval_decision_round_trips() {
        let cases = [
            ApprovalDecision::Approved,
            ApprovalDecision::Denied {
                reason: Some("nope".into()),
            },
            ApprovalDecision::Denied { reason: None },
        ];
        for c in cases {
            let j = serde_json::to_string(&c).expect("encode");
            let d: ApprovalDecision = serde_json::from_str(&j).expect("decode");
            assert_eq!(d, c);
        }
    }

    #[test]
    fn expiry_check_uses_supplied_clock() {
        let mut a = PendingApproval::new(Uuid::nil(), "noop");
        a.expires_at = Some(ts(1_700_000_000));
        assert!(!a.is_expired_at(ts(1_699_999_999)));
        assert!(a.is_expired_at(ts(1_700_000_000)));
        assert!(a.is_expired_at(ts(1_700_000_001)));

        a.expires_at = None;
        // No expiry → never expires, even far in the future. We pick a
        // very-large-but-valid chrono timestamp (year ~4000 fits well
        // inside the supported range).
        assert!(!a.is_expired_at(ts(64_060_588_800)));
    }
}
