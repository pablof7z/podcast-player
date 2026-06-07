use super::*;
#[test]
fn audio_command_load_serde_roundtrips() {
    let cmd = AudioCommand::load("https://ex.com/ep.mp3", 12.5);
    let json = serde_json::to_string(&cmd).expect("encode");
    assert_eq!(
        json,
        r#"{"type":"load","url":"https://ex.com/ep.mp3","position_secs":12.5}"#
    );
    let decoded: AudioCommand = serde_json::from_str(&json).expect("decode");
    assert_eq!(decoded, cmd);
}
#[test]
fn audio_command_play_pause_stop_have_no_payload() {
    for (cmd, expected) in [
        (AudioCommand::Play, r#"{"type":"play"}"#),
        (AudioCommand::Pause, r#"{"type":"pause"}"#),
        (AudioCommand::Stop, r#"{"type":"stop"}"#),
    ] {
        assert_eq!(serde_json::to_string(&cmd).expect("encode"), expected);
    }
}
#[test]
fn audio_command_sleep_timer_handles_none_and_some() {
    let arm = AudioCommand::SetSleepTimer { secs: Some(1800) };
    assert_eq!(
        serde_json::to_string(&arm).expect("encode"),
        r#"{"type":"set_sleep_timer","secs":1800}"#
    );
    let cancel = AudioCommand::SetSleepTimer { secs: None };
    assert_eq!(
        serde_json::to_string(&cancel).expect("encode"),
        r#"{"type":"set_sleep_timer","secs":null}"#
    );
}
#[test]
fn audio_report_playing_serde_roundtrips() {
    let rep = AudioReport::Playing {
        url: "https://ex.com/ep.mp3".into(),
        position_secs: 90.0,
        duration_secs: 1800.0,
    };
    let json = serde_json::to_string(&rep).expect("encode");
    let decoded: AudioReport = serde_json::from_str(&json).expect("decode");
    assert_eq!(decoded, rep);
}
#[test]
fn audio_report_failed_carries_url_and_error() {
    let rep = AudioReport::Failed {
        url: "https://ex.com/bad.mp3".into(),
        error: "transport: timeout".into(),
    };
    let json = serde_json::to_string(&rep).expect("encode");
    assert!(json.contains("\"type\":\"failed\""));
    assert!(json.contains("transport: timeout"));
}
#[test]
fn audio_report_sleep_timer_fired_has_no_payload() {
    assert_eq!(
        serde_json::to_string(&AudioReport::SleepTimerFired).expect("encode"),
        r#"{"type":"sleep_timer_fired"}"#
    );
}
#[test]
fn namespace_matches_canonical_capability_plan() {
    assert_eq!(AUDIO_CAPABILITY_NAMESPACE, "nmp.audio.capability");
}
