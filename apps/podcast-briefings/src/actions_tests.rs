use super::*;

#[test]
fn action_ids_match_documented_strings() {
    assert_eq!(ACTION_BRIEFING_REQUEST, "podcast.briefing.request");
    assert_eq!(ACTION_BRIEFING_SCHEDULE, "podcast.briefing.schedule");
    assert_eq!(ACTION_BRIEFING_CANCEL, "podcast.briefing.cancel");
}

#[test]
fn request_briefing_action_is_unit_struct() {
    let a = RequestBriefingAction;
    let json = serde_json::to_string(&a).expect("encode");
    assert_eq!(json, "null");
    let decoded: RequestBriefingAction = serde_json::from_str(&json).expect("decode");
    assert_eq!(decoded, a);
}

#[test]
fn cancel_briefing_action_is_unit_struct() {
    let a = CancelBriefingAction;
    let json = serde_json::to_string(&a).expect("encode");
    assert_eq!(json, "null");
    let decoded: CancelBriefingAction = serde_json::from_str(&json).expect("decode");
    assert_eq!(decoded, a);
}

#[test]
fn schedule_briefing_action_round_trips() {
    let a = ScheduleBriefingAction {
        schedule: BriefingSchedule {
            time_of_day: 420,
            days: vec![1, 2, 3, 4, 5],
            enabled: true,
        },
    };
    let json = serde_json::to_string(&a).expect("encode");
    let decoded: ScheduleBriefingAction = serde_json::from_str(&json).expect("decode");
    assert_eq!(decoded, a);
}

#[test]
fn schedule_briefing_action_wire_shape_stable() {
    let a = ScheduleBriefingAction {
        schedule: BriefingSchedule {
            time_of_day: 420,
            days: vec![1, 2, 3, 4, 5],
            enabled: true,
        },
    };
    let json = serde_json::to_string(&a).expect("encode");
    assert!(json.contains("\"schedule\":{"));
    assert!(json.contains("\"time_of_day\":420"));
    assert!(json.contains("\"enabled\":true"));
}
