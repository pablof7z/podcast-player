use ratatui::layout::Rect;
use ratatui::style::Style;
use ratatui::text::{Line, Span};
use ratatui::widgets::{List, ListItem, Paragraph};
use ratatui::Frame;

use crate::app::AppState;
use crate::ui::{format, theme};

pub fn render(frame: &mut Frame<'_>, area: Rect, state: &AppState) {
    let block = theme::panel(format!("Up Next ({})", state.queue.len()), true);

    if state.queue.is_empty() {
        let text = Paragraph::new("Queue is empty. Press 'a' on an episode to add.")
            .style(theme::muted())
            .block(block);
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
                theme::selected()
            } else {
                theme::text()
            };
            let mut spans = vec![
                theme::selected_prefix(selected, state.motion_tick),
                Span::styled(format!("{}. ", i + 1), Style::default().fg(theme::MUTED)),
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
                    theme::muted(),
                ));
            }
            ListItem::new(Line::from(spans))
        })
        .collect();

    let list = List::new(items).block(block);
    frame.render_widget(list, area);
}
