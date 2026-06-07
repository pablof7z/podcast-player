use ratatui::layout::Rect;
use ratatui::text::{Line, Span};
use ratatui::widgets::{List, ListItem, Paragraph};
use ratatui::Frame;

use crate::app::AppState;
use crate::ui::{format, theme};

pub fn render(frame: &mut Frame<'_>, area: Rect, state: &AppState) {
    let block = theme::panel(format!("Bookmarks ({})", state.bookmarks.len()), true);

    if state.bookmarks.is_empty() {
        let text = Paragraph::new("No starred episodes. Press 's' on an episode to bookmark it.")
            .style(theme::muted())
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
                theme::selected()
            } else {
                theme::text()
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
                    theme::muted(),
                ));
            }
            ListItem::new(Line::from(spans))
        })
        .collect::<Vec<_>>();

    frame.render_widget(List::new(items).block(block), area);
}
