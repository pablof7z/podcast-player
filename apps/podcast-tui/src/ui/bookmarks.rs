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
        .title(format!(" Bookmarks ({}) ", state.bookmarks.len()));

    if state.bookmarks.is_empty() {
        let text = Paragraph::new("No starred episodes. Press 's' on an episode to bookmark it.")
            .block(block);
        frame.render_widget(text, area);
        return;
    }

    let items = state
        .bookmarks
        .iter()
        .enumerate()
        .map(|(index, episode)| {
            let selected = index == state.selected_bookmark;
            let base = if selected {
                Style::default()
                    .fg(Color::Black)
                    .bg(Color::Cyan)
                    .add_modifier(Modifier::BOLD)
            } else {
                Style::default().fg(Color::White)
            };
            let mut spans = vec![Span::styled(&episode.title, base)];
            let mut meta = Vec::new();
            if let Some(show) = &episode.podcast_title {
                meta.push(show.clone());
            }
            if let Some(duration) = episode.duration_secs {
                meta.push(format::duration(duration));
            }
            if episode.played {
                meta.push("played".to_string());
            }
            let active_download = state
                .downloads
                .iter()
                .find(|download| download.episode_id == episode.id)
                .map(|download| download.state.as_str());
            if let Some(download_status) =
                format::download_status(episode.download_path.as_deref(), active_download)
            {
                meta.push(download_status);
            }
            if !meta.is_empty() {
                spans.push(Span::styled(
                    format!("  {}", meta.join(" | ")),
                    Style::default().fg(Color::DarkGray),
                ));
            }
            ListItem::new(Line::from(spans))
        })
        .collect::<Vec<_>>();

    frame.render_widget(List::new(items).block(block), area);
}
