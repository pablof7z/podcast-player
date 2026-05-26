use super::*;
#[test]
fn fetch_comments_returns_ok_envelope() {
    let v = handle_fetch_comments("00000000-0000-0000-0000-000000000001");
    assert_eq!(v["ok"], true);
}
#[test]
fn post_comment_returns_pending_status() {
    let v = handle_post_comment("ep-1", "great episode");
    assert_eq!(v["ok"], true);
    assert_eq!(v["status"], "nostr_relay_pending");
}
#[test]
fn post_comment_rejects_empty_content() {
    let v = handle_post_comment("ep-1", "");
    assert_eq!(v["ok"], false);
    let v = handle_post_comment("ep-1", "   ");
    assert_eq!(v["ok"], false);
}

