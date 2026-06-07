use super::*;
use super::types::AssemblyAIResponse;

#[test]
fn parses_comma_separated_model_fallbacks() {
    assert_eq!(
        speech_models("assemblyai:universal-3-pro, universal-2"),
        vec!["universal-3-pro", "universal-2"]
    );
    assert_eq!(speech_models(" "), vec!["universal-3-pro", "universal-2"]);
}

#[test]
fn rejects_non_remote_audio_sources() {
    let error = remote_audio_url("file:///tmp/show.mp3").unwrap_err();
    assert_eq!(error.kind(), "invalid_audio_url");
}

#[test]
fn decodes_completed_response_to_result() {
    let raw: AssemblyAIResponse = decode_response(
        r#"{
          "id":"tx_1",
          "status":"completed",
          "audio_duration":1.25,
          "language_code":"en",
          "text":"Hello",
          "words":[{"text":"Hello","start":0,"end":500,"confidence":0.9,"speaker":"A"}],
          "utterances":[{"text":"Hello","start":0,"end":500,"confidence":0.9,"speaker":"A","words":[{"text":"Hello","start":0,"end":500}]}],
          "usage":{"cost":0.01,"seconds":1.25,"input_tokens":2,"output_tokens":3,"total_tokens":5}
        }"#,
    )
    .unwrap();
    let result = raw.into_result("universal-3-pro,universal-2".to_owned(), 42);
    assert_eq!(result.status.as_deref(), Some("completed"));
    assert_eq!(result.words.len(), 1);
    assert_eq!(result.utterances.len(), 1);
    assert_eq!(
        result.usage.as_ref().and_then(|usage| usage.total_tokens),
        Some(5)
    );
    assert_eq!(result.latency_ms, 42);
}

#[test]
fn provider_status_maps_to_stable_kinds() {
    assert_eq!(
        AssemblyAITranscriptError::ProviderStatus(401, String::new()).kind(),
        "invalid_key"
    );
    assert_eq!(
        AssemblyAITranscriptError::ProviderStatus(429, String::new()).kind(),
        "rate_limited"
    );
}
