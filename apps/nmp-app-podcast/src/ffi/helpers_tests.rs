use super::strip_html;
#[test]
fn strips_basic_tags() {
    assert_eq!(strip_html("<p>Hello <b>world</b>.</p>"), "Hello world .");
}
#[test]
fn decodes_named_entities() {
    assert_eq!(strip_html("Tom &amp; Jerry"), "Tom & Jerry");
    assert_eq!(strip_html("it&rsquo;s"), "it\u{2019}s");
}
#[test]
fn decodes_numeric_entities() {
    assert_eq!(strip_html("&#39;hello&#39;"), "'hello'");
    assert_eq!(strip_html("&#x2019;"), "\u{2019}");
}
#[test]
fn collapses_whitespace() {
    assert_eq!(strip_html("<p>A</p><p>B</p>"), "A B");
}
#[test]
fn empty_input_returns_empty() {
    assert_eq!(strip_html(""), "");
}
#[test]
fn plain_text_passes_through() {
    assert_eq!(strip_html("No tags here."), "No tags here.");
}
#[test]
fn strips_anchor_and_list_tags() {
    let input = r#"<ul><li>Point A</li><li>Point B</li></ul>"#;
    assert_eq!(strip_html(input), "Point A Point B");
}
#[test]
fn mixed_entities_and_tags() {
    let input = "<p>Subscribe at <a href=\"https://ex.com\">our site</a> &amp; enjoy!</p>";
    assert_eq!(strip_html(input), "Subscribe at our site & enjoy!");
}
#[test]
fn newlines_and_tabs_collapsed() {
    let input = "Line 1\n\nLine 2\t\tLine 3";
    assert_eq!(strip_html(input), "Line 1 Line 2 Line 3");
}
#[test]
fn tags_only_produces_empty_string() {
    // RSS descriptions that are purely structural tags with no visible text
    // must produce "" so callers can filter → None rather than store empty.
    assert_eq!(strip_html("<br/><br/>"), "");
    assert_eq!(strip_html("<p></p>"), "");
    assert_eq!(strip_html("<div><span></span></div>"), "");
}
#[test]
fn multibyte_chars_pass_through() {
    assert_eq!(strip_html("café & résumé"), "café & résumé");
    assert_eq!(strip_html("<p>日本語</p>"), "日本語");
}

