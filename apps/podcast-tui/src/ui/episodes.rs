use ratatui::layout::Rect;
use ratatui::style::Style;
use ratatui::text::{Line, Span};
use ratatui::widgets::{List, ListItem};
use ratatui::Frame;

use crate::app::{AppState, Pane};
use crate::ui::{format, theme};

pub fn render(frame: &mut Frame<'_>, area: Rect, state: &AppState) {
    let is_focused = state.focused == Pane::Episodes;
    let block = theme::panel(format!("Episodes ({})", state.episodes.len()), is_focused);

    if state.episodes.is_empty() {
        let text = ratatui::widgets::Paragraph::new("Select a podcast to see episodes.")
            .style(theme::muted())
            .block(block);
        frame.render_widget(text, area);
        return;
    }

    let items: Vec<ListItem> = state
        .episodes
        .iter()
        .enumerate()
        .map(|(i, ep)| {
            let is_selected = i == state.selected_episode;
            let base_style = if is_selected {
                theme::selected()
            } else {
                theme::text()
            };

            let mut spans = Vec::new();
            if ep.played {
                spans.push(Span::styled("  ", base_style));
            } else {
                spans.push(Span::styled("● ", Style::default().fg(theme::ACCENT)));
            }

            spans.push(Span::styled(&ep.title, base_style));

            let mut meta_parts = Vec::new();
            if let Some(dur) = ep.duration_secs {
                meta_parts.push(format::duration(dur));
            }
            if let Some(pos) = ep.playback_position_secs {
                if pos > 0.0 {
                    meta_parts.push(format!(
                        "{:.0}%",
                        (pos / ep.duration_secs.unwrap_or(1.0)) * 100.0
                    ));
                }
            }
            let active_download = state
                .downloads
                .iter()
                .find(|download| download.episode_id == ep.id)
                .map(|download| download.state.as_str());
            if let Some(download_status) =
                format::download_status(ep.download_path.as_deref(), active_download)
            {
                meta_parts.push(download_status);
            }
            if !meta_parts.is_empty() {
                spans.push(Span::styled(
                    format!("  {}", meta_parts.join(" | ")),
                    theme::muted(),
                ));
            }

            ListItem::new(Line::from(spans))
        })
        .collect();

    let list = List::new(items).block(block);
    frame.render_widget(list, area);
}
