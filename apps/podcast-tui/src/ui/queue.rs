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
        .title(format!(" Up Next ({}) ", state.queue.len()));

    if state.queue.is_empty() {
        let text = Paragraph::new("Queue is empty. Press 'a' on an episode to add.").block(block);
        frame.render_widget(text, area);
        return;
    }

    let items: Vec<ListItem> = state
        .queue
        .iter()
        .enumerate()
        .map(|(i, ep)| {
            let selected = i == state.selected_queue;
            let base_style = if selected {
                Style::default()
                    .fg(Color::Black)
                    .bg(Color::Cyan)
                    .add_modifier(Modifier::BOLD)
            } else {
                Style::default().fg(Color::White)
            };
            let mut spans = vec![
                Span::styled(format!("{}. ", i + 1), Style::default().fg(Color::DarkGray)),
                Span::styled(&ep.title, base_style),
            ];
            let mut meta = Vec::new();
            if let Some(dur) = ep.duration_secs {
                meta.push(format::duration(dur));
            }
            let active_download = state
                .downloads
                .iter()
                .find(|download| download.episode_id == ep.id)
                .map(|download| download.state.as_str());
            if let Some(download_status) =
                format::download_status(ep.download_path.as_deref(), active_download)
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
        .collect();

    let list = List::new(items).block(block);
    frame.render_widget(list, area);
}
