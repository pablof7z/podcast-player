use super::*;
#[test]
fn fetch_contacts_returns_nostr_pending_envelope() {
    let v = handle_fetch_contacts();
    assert_eq!(v["ok"], true);
    assert_eq!(v["status"], "nostr_pending");
}

