use ratatui::layout::{Constraint, Layout, Rect};
use ratatui::style::{Color, Modifier, Style};
use ratatui::text::{Line, Span};
use ratatui::widgets::{Block, Borders, List, ListItem, Paragraph, Wrap};
use ratatui::Frame;

use crate::app::{AgentSection, AppState};
use crate::ui::format;

pub fn render(frame: &mut Frame<'_>, area: Rect, state: &AppState) {
    let rows = Layout::vertical([Constraint::Length(1), Constraint::Min(6)]).split(area);
    render_section_bar(frame, rows[0], state);
    let columns =
        Layout::horizontal([Constraint::Percentage(58), Constraint::Percentage(42)]).split(rows[1]);
    render_conversation(frame, columns[0], state);
    match state.agent_section {
        AgentSection::Chat => render_agent_help(frame, columns[1], state),
        AgentSection::Picks => render_picks(frame, columns[1], state),
        AgentSection::Tasks => render_tasks(frame, columns[1], state),
        AgentSection::Notes => render_notes(frame, columns[1], state),
        AgentSection::Memory => render_memory(frame, columns[1], state),
    }
}

fn render_section_bar(frame: &mut Frame<'_>, area: Rect, state: &AppState) {
    let spans = AgentSection::all()
        .iter()
        .map(|section| {
            let label = format!(" {} ", section.label());
            if *section == state.agent_section {
                Span::styled(
                    label,
                    Style::default()
                        .fg(Color::Black)
                        .bg(Color::Cyan)
                        .add_modifier(Modifier::BOLD),
                )
            } else {
                Span::styled(label, Style::default().fg(Color::DarkGray))
            }
        })
        .collect::<Vec<_>>();
    frame.render_widget(Paragraph::new(Line::from(spans)), area);
}

fn render_conversation(frame: &mut Frame<'_>, area: Rect, state: &AppState) {
    let busy = if state.agent_is_busy { " busy" } else { "" };
    let block = block(&format!("Agent Chat{busy}"));

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

fn render_agent_help(frame: &mut Frame<'_>, area: Rect, state: &AppState) {
    let lines = vec![
        Line::from("h/l switch agent section"),
        Line::from("Enter or i compose chat"),
        Line::from("c or x clear chat"),
        Line::from(""),
        Line::from(format!("Picks: {}", state.agent_picks.len())),
        Line::from(format!("Tasks: {}", state.agent_tasks.len())),
        Line::from(format!("Notes: {}", state.agent_notes.len())),
        Line::from(format!("Memory facts: {}", state.memory_facts.len())),
    ];
    frame.render_widget(Paragraph::new(lines).block(block("Agent")), area);
}

fn render_picks(frame: &mut Frame<'_>, area: Rect, state: &AppState) {
    let block = block("Picks  p play  a queue  A next");
    if state.agent_picks.is_empty() {
        frame.render_widget(Paragraph::new("No picks projected.").block(block), area);
        return;
    }
    let items = state
        .agent_picks
        .iter()
        .enumerate()
        .map(|(index, pick)| {
            let base = row_style(index == state.selected_agent_pick);
            ListItem::new(Line::from(vec![
                Span::styled(&pick.episode_title, base),
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
    let block = block("Tasks  n new  r run  e enable  d delete");
    if state.agent_tasks.is_empty() {
        frame.render_widget(Paragraph::new("No scheduled tasks.").block(block), area);
        return;
    }
    let items = state
        .agent_tasks
        .iter()
        .enumerate()
        .map(|(index, task)| {
            let base = row_style(index == state.selected_agent_task);
            let enabled = if task.is_enabled { "on" } else { "off" };
            ListItem::new(Line::from(vec![
                Span::styled(&task.title, base),
                Span::styled(
                    format!("  {} | {} | {}", enabled, task.status, task.schedule),
                    Style::default().fg(Color::DarkGray),
                ),
            ]))
        })
        .collect::<Vec<_>>();
    frame.render_widget(List::new(items).block(block), area);
}

fn render_notes(frame: &mut Frame<'_>, area: Rect, state: &AppState) {
    let block = block("Agent Notes  r fetch  n publish");
    if state.agent_notes.is_empty() {
        frame.render_widget(
            Paragraph::new("No notes projected. Press 'r' to fetch inbound notes.").block(block),
            area,
        );
        return;
    }
    let items = state
        .agent_notes
        .iter()
        .enumerate()
        .map(|(index, note)| {
            let trust = if note.trusted { "trusted" } else { "untrusted" };
            let base = row_style(index == state.selected_agent_note);
            ListItem::new(Line::from(vec![
                Span::styled(format::short_id(&note.author_npub), base),
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
    let block = block("Memory  n new  d forget  x clear");
    if state.memory_facts.is_empty() {
        frame.render_widget(Paragraph::new("No memory facts.").block(block), area);
        return;
    }
    let items = state
        .memory_facts
        .iter()
        .enumerate()
        .map(|(index, fact)| {
            let base = row_style(index == state.selected_memory_fact);
            ListItem::new(Line::from(vec![
                Span::styled(&fact.key, base),
                Span::styled(
                    format!(" = {}  ({})", fact.value, fact.source),
                    Style::default().fg(Color::DarkGray),
                ),
            ]))
        })
        .collect::<Vec<_>>();
    frame.render_widget(List::new(items).block(block), area);
}

fn row_style(selected: bool) -> Style {
    if selected {
        Style::default()
            .fg(Color::Black)
            .bg(Color::Cyan)
            .add_modifier(Modifier::BOLD)
    } else {
        Style::default().fg(Color::White)
    }
}

fn block(title: impl Into<String>) -> Block<'static> {
    let title = title.into();
    Block::default()
        .borders(Borders::ALL)
        .border_style(Style::default().fg(Color::DarkGray))
        .title(format!(" {title} "))
}
