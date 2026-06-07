use ratatui::layout::{Constraint, Layout, Rect};
use ratatui::style::{Modifier, Style};
use ratatui::text::{Line, Span};
use ratatui::widgets::{List, ListItem, Paragraph, Wrap};
use ratatui::Frame;

use crate::app::AppState;
use crate::ui::theme;

pub fn render(frame: &mut Frame<'_>, area: Rect, state: &AppState) {
    let columns =
        Layout::horizontal([Constraint::Percentage(42), Constraint::Percentage(58)]).split(area);
    render_articles(frame, columns[0], state);
    render_article_detail(frame, columns[1], state);
}

fn render_articles(frame: &mut Frame<'_>, area: Rect, state: &AppState) {
    let block = theme::panel(format!("Wiki ({})", state.wiki_articles.len()), true);

    if state.wiki_articles.is_empty() {
        let text = Paragraph::new("No wiki articles projected yet.")
            .style(theme::muted())
            .block(block);
        frame.render_widget(text, area);
        return;
    }

    let items = state
        .wiki_articles
        .iter()
        .enumerate()
        .map(|(index, article)| {
            let selected = index == state.selected_wiki;
            let base = if selected {
                theme::selected()
            } else {
                theme::text()
            };
            let mut spans = vec![
                theme::selected_prefix(selected, state.motion_tick),
                Span::styled(&article.topic, base),
            ];
            if article.is_generating {
                spans.push(Span::styled(
                    "  generating",
                    Style::default().fg(theme::WARN),
                ));
            }
            if article.generation_error.is_some() {
                spans.push(Span::styled("  failed", Style::default().fg(theme::DANGER)));
            }
            ListItem::new(Line::from(spans))
        })
        .collect::<Vec<_>>();

    frame.render_widget(List::new(items).block(block), area);
}

fn render_article_detail(frame: &mut Frame<'_>, area: Rect, state: &AppState) {
    let block = theme::panel("Article", false);

    let Some(article) = state.wiki_articles.get(state.selected_wiki) else {
        frame.render_widget(
            Paragraph::new("Select an article.")
                .style(theme::muted())
                .block(block),
            area,
        );
        return;
    };

    let mut lines = vec![
        Line::from(Span::styled(
            &article.topic,
            theme::text().add_modifier(Modifier::BOLD),
        )),
        Line::from(""),
        Line::from(article.summary.clone()),
    ];
    if !article.source_episode_ids.is_empty() {
        lines.push(Line::from(""));
        lines.push(Line::from(Span::styled(
            format!("Sources: {}", article.source_episode_ids.len()),
            theme::muted(),
        )));
    }
    if let Some(error) = &article.generation_error {
        lines.push(Line::from(""));
        lines.push(Line::from(Span::styled(
            error,
            Style::default().fg(theme::DANGER),
        )));
    }

    frame.render_widget(
        Paragraph::new(lines)
            .style(theme::text())
            .block(block)
            .wrap(Wrap { trim: true }),
        area,
    );
}
