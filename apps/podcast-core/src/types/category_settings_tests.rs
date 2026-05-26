use super::*;
#[test]
fn category_settings_round_trip() {
    let value = CategorySettings::default_for(Uuid::nil());
    let json = serde_json::to_string(&value).unwrap();
    let back: CategorySettings = serde_json::from_str(&json).unwrap();
    assert_eq!(value, back);
}

