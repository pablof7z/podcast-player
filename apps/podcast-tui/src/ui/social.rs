use ratatui::layout::{Constraint, Layout, Rect};
use ratatui::style::Modifier;
use ratatui::text::{Line, Span};
use ratatui::widgets::{Block, List, ListItem, Paragraph};
use ratatui::Frame;

use crate::app::AppState;
use crate::ui::{format, theme};

pub fn render(frame: &mut Frame<'_>, area: Rect, state: &AppState) {
    let rows = Layout::vertical([
        Constraint::Length(5),
        Constraint::Percentage(48),
        Constraint::Percentage(52),
    ])
    .split(area);
    render_account(frame, rows[0], state);
    render_relays(frame, rows[1], state);
    render_contacts(frame, rows[2], state);
}

fn render_account(frame: &mut Frame<'_>, area: Rect, state: &AppState) {
    let block = block("Account");
    let lines = if let Some(account) = &state.active_account {
        vec![
            Line::from(vec![
                Span::styled("npub ", theme::muted()),
                Span::styled(format::short_id(&account.npub), theme::text()),
            ]),
            Line::from(vec![
                Span::styled("mode ", theme::muted()),
                Span::styled(&account.mode, theme::text()),
            ]),
        ]
    } else {
        vec![Line::from("No active Nostr account.")]
    };
    frame.render_widget(
        Paragraph::new(lines).style(theme::text()).block(block),
        area,
    );
}

fn render_relays(frame: &mut Frame<'_>, area: Rect, state: &AppState) {
    let block = block(format!("Relays ({})", state.configured_relays.len()));
    if state.configured_relays.is_empty() {
        frame.render_widget(
            Paragraph::new("No configured relays projected.")
                .style(theme::muted())
                .block(block),
            area,
        );
        return;
    }
    let items = state
        .configured_relays
        .iter()
        .map(|relay| {
            ListItem::new(Line::from(vec![
                Span::styled(&relay.role, theme::accent()),
                Span::styled(format!("  {}", relay.url), theme::text()),
            ]))
        })
        .collect::<Vec<_>>();
    frame.render_widget(List::new(items).block(block), area);
}

fn render_contacts(frame: &mut Frame<'_>, area: Rect, state: &AppState) {
    let block = block(format!("Contacts ({})", state.social_following_count));
    if state.social_contacts.is_empty() {
        let text = Paragraph::new("No contacts projected. Press 'r' to fetch contacts.")
            .style(theme::muted())
            .block(block);
        frame.render_widget(text, area);
        return;
    }
    let items = state
        .social_contacts
        .iter()
        .map(|contact| {
            let name = contact.display_name.as_deref().unwrap_or(&contact.npub);
            ListItem::new(Line::from(vec![
                Span::styled(name, theme::text().add_modifier(Modifier::BOLD)),
                Span::styled(
                    format!("  {}", format::short_id(&contact.npub)),
                    theme::muted(),
                ),
            ]))
        })
        .collect::<Vec<_>>();
    frame.render_widget(List::new(items).block(block), area);
}

fn block(title: impl Into<String>) -> Block<'static> {
    theme::panel(title, false)
}
