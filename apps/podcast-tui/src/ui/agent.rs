use ratatui::layout::{Constraint, Layout, Rect};
use ratatui::style::{Color, Modifier, Style};
use ratatui::text::{Line, Span};
use ratatui::widgets::{Block, Borders, List, ListItem, Paragraph, Wrap};
use ratatui::Frame;

use crate::app::AppState;
use crate::ui::format;

pub fn render(frame: &mut Frame<'_>, area: Rect, state: &AppState) {
    let columns =
        Layout::horizontal([Constraint::Percentage(58), Constraint::Percentage(42)]).split(area);
    render_conversation(frame, columns[0], state);
    render_agent_sidecar(frame, columns[1], state);
}

fn render_conversation(frame: &mut Frame<'_>, area: Rect, state: &AppState) {
    let busy = if state.agent_is_busy { " busy" } else { "" };
    let block = Block::default()
        .borders(Borders::ALL)
        .border_style(Style::default().fg(Color::DarkGray))
        .title(format!(" Agent Chat{} ", busy));

    if state.agent_messages.is_empty() {
        let text = Paragraph::new("No agent messages. Press Enter or 'i' to compose.")
            .block(block)
            .wrap(Wrap { trim: true });
        frame.render_widget(text, area);
        return;
    }

    let lines = state
        .agent_messages
        .iter()
        .flat_map(|message| {
            let role_style = if message.role == "user" {
                Style::default()
                    .fg(Color::Cyan)
                    .add_modifier(Modifier::BOLD)
            } else {
                Style::default()
                    .fg(Color::Yellow)
                    .add_modifier(Modifier::BOLD)
            };
            [
                Line::from(vec![
                    Span::styled(format!("{}: ", message.role), role_style),
                    Span::raw(message.content.clone()),
                ]),
                Line::from(""),
            ]
        })
        .collect::<Vec<_>>();

    frame.render_widget(
        Paragraph::new(lines).block(block).wrap(Wrap { trim: true }),
        area,
    );
}

fn render_agent_sidecar(frame: &mut Frame<'_>, area: Rect, state: &AppState) {
    let rows = Layout::vertical([
        Constraint::Percentage(30),
        Constraint::Percentage(25),
        Constraint::Percentage(25),
        Constraint::Percentage(20),
    ])
    .split(area);
    render_picks(frame, rows[0], state);
    render_tasks(frame, rows[1], state);
    render_notes(frame, rows[2], state);
    render_memory(frame, rows[3], state);
}

fn render_picks(frame: &mut Frame<'_>, area: Rect, state: &AppState) {
    let block = side_block("Picks");
    if state.agent_picks.is_empty() {
        frame.render_widget(Paragraph::new("No picks projected.").block(block), area);
        return;
    }
    let items = state
        .agent_picks
        .iter()
        .map(|pick| {
            ListItem::new(Line::from(vec![
                Span::styled(&pick.episode_title, Style::default().fg(Color::White)),
                Span::styled(
                    format!("  {:.0}% {}", pick.pick_score * 100.0, pick.pick_reason),
                    Style::default().fg(Color::DarkGray),
                ),
            ]))
        })
        .collect::<Vec<_>>();
    frame.render_widget(List::new(items).block(block), area);
}

fn render_tasks(frame: &mut Frame<'_>, area: Rect, state: &AppState) {
    let block = side_block("Tasks");
    if state.agent_tasks.is_empty() {
        frame.render_widget(Paragraph::new("No scheduled tasks.").block(block), area);
        return;
    }
    let items = state
        .agent_tasks
        .iter()
        .map(|task| {
            ListItem::new(Line::from(vec![
                Span::styled(&task.title, Style::default().fg(Color::White)),
                Span::styled(
                    format!("  {} | {}", task.status, task.schedule),
                    Style::default().fg(Color::DarkGray),
                ),
            ]))
        })
        .collect::<Vec<_>>();
    frame.render_widget(List::new(items).block(block), area);
}

fn render_notes(frame: &mut Frame<'_>, area: Rect, state: &AppState) {
    let block = side_block("Agent Notes");
    if state.agent_notes.is_empty() {
        frame.render_widget(
            Paragraph::new("Press 'r' to fetch inbound notes.").block(block),
            area,
        );
        return;
    }
    let items = state
        .agent_notes
        .iter()
        .map(|note| {
            let trust = if note.trusted { "trusted" } else { "untrusted" };
            ListItem::new(Line::from(vec![
                Span::styled(
                    format::short_id(&note.author_npub),
                    Style::default().fg(Color::Cyan),
                ),
                Span::styled(
                    format!("  {}  {}", trust, note.content),
                    Style::default().fg(Color::White),
                ),
            ]))
        })
        .collect::<Vec<_>>();
    frame.render_widget(List::new(items).block(block), area);
}

fn render_memory(frame: &mut Frame<'_>, area: Rect, state: &AppState) {
    let block = side_block("Memory");
    if state.memory_facts.is_empty() {
        frame.render_widget(Paragraph::new("No memory facts.").block(block), area);
        return;
    }
    let items = state
        .memory_facts
        .iter()
        .map(|fact| {
            ListItem::new(Line::from(vec![
                Span::styled(&fact.key, Style::default().fg(Color::White)),
                Span::styled(
                    format!(" = {}", fact.value),
                    Style::default().fg(Color::DarkGray),
                ),
            ]))
        })
        .collect::<Vec<_>>();
    frame.render_widget(List::new(items).block(block), area);
}

fn side_block(title: &str) -> Block<'_> {
    Block::default()
        .borders(Borders::ALL)
        .border_style(Style::default().fg(Color::DarkGray))
        .title(format!(" {title} "))
}
