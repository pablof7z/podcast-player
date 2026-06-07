use ratatui::layout::Rect;
use ratatui::text::{Line, Span};
use ratatui::widgets::{List, ListItem, Paragraph};
use ratatui::Frame;

use crate::app::AppState;
use crate::ui::{format, theme};

pub fn render(frame: &mut Frame<'_>, area: Rect, state: &AppState) {
    let block = theme::panel(format!("Clips ({})", state.clips.len()), true);

    if state.clips.is_empty() {
        let text = Paragraph::new("No clips yet. Press 'c' on an episode or while playing.")
            .style(theme::muted())
            .block(block);
        frame.render_widget(text, area);
        return;
    }

    let items = state
        .clips
        .iter()
        .enumerate()
        .map(|(index, clip)| {
            let selected = index == state.selected_clip;
            let base = if selected {
                theme::selected()
            } else {
                theme::text()
            };
            let title = clip.title.as_deref().unwrap_or(&clip.episode_title);
            let range = format!(
                "{}-{}",
                format::duration(clip.start_secs),
                format::duration(clip.end_secs)
            );
            let spans = vec![
                Span::styled(title, base),
                Span::styled(
                    format!(
                        "  {} | {} | {}",
                        range, clip.podcast_title, clip.episode_title
                    ),
                    theme::muted(),
                ),
            ];
            ListItem::new(Line::from(spans))
        })
        .collect::<Vec<_>>();

    frame.render_widget(List::new(items).block(block), area);
}
