use super::*;

#[test]
fn settings_default_round_trip() {
    let value = Settings::default();
    let json = serde_json::to_string(&value).unwrap();
    let back: Settings = serde_json::from_str(&json).unwrap();
    assert_eq!(value, back);
}

#[test]
fn settings_with_credentials_round_trip() {
    let mut value = Settings::default();
    value.open_router_credential_source = OpenRouterCredentialSource::Byok;
    value.open_router.byok_key_id = Some("k1".into());
    value.open_router.byok_key_label = Some("Personal".into());
    let json = serde_json::to_string(&value).unwrap();
    let back: Settings = serde_json::from_str(&json).unwrap();
    assert_eq!(value, back);
}
