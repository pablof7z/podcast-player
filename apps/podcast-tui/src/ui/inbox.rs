use ratatui::layout::Rect;
use ratatui::style::Style;
use ratatui::text::{Line, Span};
use ratatui::widgets::{List, ListItem, Paragraph};
use ratatui::Frame;

use crate::app::AppState;
use crate::ui::{format, theme};

pub fn render(frame: &mut Frame<'_>, area: Rect, state: &AppState) {
    let block = theme::panel(format!("Inbox ({})", state.inbox.len()), true);

    if state.inbox.is_empty() {
        let text = Paragraph::new("Inbox is empty. Listen to episodes to triage them.")
            .style(theme::muted())
            .block(block);
        frame.render_widget(text, area);
        return;
    }

    let items: Vec<ListItem> = state
        .inbox
        .iter()
        .enumerate()
        .map(|(i, row)| {
            let is_selected = i == state.selected_inbox;
            let base_style = if is_selected {
                theme::selected()
            } else {
                theme::text()
            };

            let mut spans = vec![Span::styled(&row.episode_title, base_style)];

            let mut meta_parts = Vec::new();
            if !row.podcast_title.is_empty() {
                meta_parts.push(row.podcast_title.clone());
            }
            if let Some(dur) = row.duration_secs {
                meta_parts.push(format::duration(dur));
            }
            if row.priority_score > 0.0 {
                meta_parts.push(format!("{:.0}%", row.priority_score * 100.0));
            }
            if !row.ai_categories.is_empty() {
                meta_parts.push(row.ai_categories.join(", "));
            }
            if let Some(download) = state
                .downloads
                .iter()
                .find(|download| download.episode_id == row.episode_id)
            {
                meta_parts.push(format!("download {}", download.state));
            }
            if !meta_parts.is_empty() {
                spans.push(Span::styled(
                    format!("  {}", meta_parts.join(" | ")),
                    theme::muted(),
                ));
            }

            if let Some(ref reason) = row.priority_reason {
                spans.push(Span::styled(
                    format!("  — {reason}"),
                    Style::default().fg(theme::WARN),
                ));
            }

            ListItem::new(Line::from(spans))
        })
        .collect();

    let list = List::new(items).block(block);
    frame.render_widget(list, area);
}
