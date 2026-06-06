use ratatui::layout::Rect;
use ratatui::style::{Color, Modifier, Style};
use ratatui::text::{Line, Span};
use ratatui::widgets::{Block, Borders, List, ListItem, Paragraph};
use ratatui::Frame;

use crate::app::AppState;
use crate::ui::format;

pub fn render(frame: &mut Frame<'_>, area: Rect, state: &AppState) {
    let block = Block::default()
        .borders(Borders::ALL)
        .border_style(Style::default().fg(Color::DarkGray))
        .title(format!(" Clips ({}) ", state.clips.len()));

    if state.clips.is_empty() {
        let text =
            Paragraph::new("No clips yet. Press 'c' on an episode or while playing.").block(block);
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
                Style::default()
                    .fg(Color::Black)
                    .bg(Color::Cyan)
                    .add_modifier(Modifier::BOLD)
            } else {
                Style::default().fg(Color::White)
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
                    Style::default().fg(Color::DarkGray),
                ),
            ];
            ListItem::new(Line::from(spans))
        })
        .collect::<Vec<_>>();

    frame.render_widget(List::new(items).block(block), area);
}
