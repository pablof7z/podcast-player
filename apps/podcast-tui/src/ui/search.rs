use ratatui::layout::Rect;
use ratatui::text::{Line, Span};
use ratatui::widgets::{List, ListItem, Paragraph};
use ratatui::Frame;

use crate::app::AppState;
use crate::ui::theme;

pub fn render(frame: &mut Frame<'_>, area: Rect, state: &AppState) {
    let block = theme::panel(format!("Search ({})", state.search_results.len()), true);

    if state.search_results.is_empty() {
        let msg = if state.search_input.is_empty() {
            "Press '/' to search iTunes."
        } else {
            "No results."
        };
        let text = Paragraph::new(msg).style(theme::muted()).block(block);
        frame.render_widget(text, area);
        return;
    }

    let items: Vec<ListItem> = state
        .search_results
        .iter()
        .enumerate()
        .map(|(i, result)| {
            let is_selected = i == state.selected_search;
            let base_style = if is_selected {
                theme::selected()
            } else {
                theme::text()
            };

            let mut spans = vec![Span::styled(&result.title, base_style)];
            if let Some(ref author) = result.author {
                spans.push(Span::styled(format!(" — {author}"), theme::muted()));
            }
            ListItem::new(Line::from(spans))
        })
        .collect();

    let list = List::new(items).block(block);
    frame.render_widget(list, area);
}
