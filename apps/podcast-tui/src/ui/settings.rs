use ratatui::layout::{Constraint, Layout, Rect};
use ratatui::style::{Color, Modifier, Style};
use ratatui::text::{Line, Span};
use ratatui::widgets::{Block, Borders, List, ListItem, Paragraph};
use ratatui::Frame;

use crate::app::AppState;
use crate::settings_catalog::SETTINGS_ITEMS;

pub fn render(frame: &mut Frame<'_>, area: Rect, state: &AppState) {
    let columns =
        Layout::horizontal([Constraint::Percentage(55), Constraint::Percentage(45)]).split(area);
    render_interactive_settings(frame, columns[0], state);
    render_provider_summary(frame, columns[1], state);
}

fn render_interactive_settings(frame: &mut Frame<'_>, area: Rect, state: &AppState) {
    let block = Block::default()
        .borders(Borders::ALL)
        .border_style(Style::default().fg(Color::DarkGray))
        .title(" Settings ");

    let items = SETTINGS_ITEMS
        .iter()
        .enumerate()
        .map(|(index, item)| {
            let selected = index == state.selected_setting;
            let base = if selected {
                Style::default()
                    .fg(Color::Black)
                    .bg(Color::Cyan)
                    .add_modifier(Modifier::BOLD)
            } else {
                Style::default().fg(Color::White)
            };
            ListItem::new(Line::from(vec![
                Span::styled(item.label(), base),
                Span::styled(
                    format!("  {}", item.value(state)),
                    Style::default().fg(Color::DarkGray),
                ),
            ]))
        })
        .collect::<Vec<_>>();

    frame.render_widget(List::new(items).block(block), area);
}

fn render_provider_summary(frame: &mut Frame<'_>, area: Rect, state: &AppState) {
    let block = Block::default()
        .borders(Borders::ALL)
        .border_style(Style::default().fg(Color::DarkGray))
        .title(" Models And Providers ");

    let settings = &state.settings;
    let lines = vec![
        Line::from(vec![
            Span::styled("Agent initial  ", Style::default().fg(Color::DarkGray)),
            Span::raw(&settings.agent_initial_model_name),
        ]),
        Line::from(vec![
            Span::styled("Agent thinking ", Style::default().fg(Color::DarkGray)),
            Span::raw(&settings.agent_thinking_model_name),
        ]),
        Line::from(vec![
            Span::styled("Wiki           ", Style::default().fg(Color::DarkGray)),
            Span::raw(&settings.wiki_model_name),
        ]),
        Line::from(vec![
            Span::styled("Categorization ", Style::default().fg(Color::DarkGray)),
            Span::raw(&settings.categorization_model_name),
        ]),
        Line::from(vec![
            Span::styled("STT            ", Style::default().fg(Color::DarkGray)),
            Span::raw(&settings.effective_stt_provider),
        ]),
        Line::from(vec![
            Span::styled("ElevenLabs TTS ", Style::default().fg(Color::DarkGray)),
            Span::raw(&settings.eleven_labs_tts_model),
        ]),
        Line::from(vec![
            Span::styled("Blossom        ", Style::default().fg(Color::DarkGray)),
            Span::raw(&settings.blossom_server_url),
        ]),
        Line::from(""),
        Line::from(format!("Relays: {}", state.configured_relays.len())),
        Line::from(format!("Categories: {}", state.categories.len())),
        Line::from(format!("Downloads: {}", state.downloads.len())),
    ];

    frame.render_widget(Paragraph::new(lines).block(block), area);
}
