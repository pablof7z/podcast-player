use super::*;
#[test]
fn person_round_trip() {
    let value = Person::new("Alice");
    let json = serde_json::to_string(&value).unwrap();
    let back: Person = serde_json::from_str(&json).unwrap();
    assert_eq!(value, back);
}

