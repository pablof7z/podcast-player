use ratatui::layout::Rect;
use ratatui::style::Style;
use ratatui::text::{Line, Span};
use ratatui::widgets::{List, ListItem, Paragraph};
use ratatui::Frame;

use crate::app::{AppState, Pane};
use crate::ui::theme;

pub fn render(frame: &mut Frame<'_>, area: Rect, state: &AppState) {
    let is_focused = state.focused == Pane::Library;
    let block = theme::panel(format!("Library ({})", state.library.len()), is_focused);

    if state.library.is_empty() {
        let text = Paragraph::new("No podcasts. Press 'n' to subscribe.")
            .style(theme::muted())
            .block(block);
        frame.render_widget(text, area);
        return;
    }

    let items: Vec<ListItem> = state
        .library
        .iter()
        .enumerate()
        .map(|(i, podcast)| {
            let is_selected = i == state.selected_podcast;
            let title_style = if is_selected {
                theme::selected()
            } else {
                theme::text()
            };

            let mut spans = vec![
                theme::selected_prefix(is_selected, state.motion_tick),
                Span::styled(&podcast.title, title_style),
            ];
            if podcast.unplayed_count > 0 {
                spans.push(Span::styled(
                    format!(" ({})", podcast.unplayed_count),
                    Style::default().fg(theme::WARN),
                ));
            }
            ListItem::new(Line::from(spans))
        })
        .collect();

    let list = List::new(items).block(block);
    frame.render_widget(list, area);
}
