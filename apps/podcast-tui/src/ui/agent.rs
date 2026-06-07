use ratatui::layout::{Constraint, Layout, Rect};
use ratatui::style::{Modifier, Style};
use ratatui::text::{Line, Span};
use ratatui::widgets::{Block, List, ListItem, Paragraph, Wrap};
use ratatui::Frame;

use crate::app::{AgentSection, AppState};
use crate::ui::{format, theme};

pub fn render(frame: &mut Frame<'_>, area: Rect, state: &AppState) {
    let rows = Layout::vertical([Constraint::Length(2), Constraint::Min(6)]).split(area);
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
    let rows = Layout::vertical([Constraint::Length(1), Constraint::Length(1)]).split(area);
    let spans = AgentSection::all()
        .iter()
        .map(|section| {
            let label = format!(" {} ", section.label());
            if *section == state.agent_section {
                Span::styled(label, theme::selected())
            } else {
                Span::styled(label, Style::default().fg(theme::MUTED).bg(theme::BG))
            }
        })
        .collect::<Vec<_>>();
    frame.render_widget(
        Paragraph::new(Line::from(spans)).style(Style::default().bg(theme::SURFACE)),
        rows[0],
    );

    let pulse = if state.agent_is_busy {
        Span::styled(
            format!(
                "{} thinking {}",
                theme::spinner(state.motion_tick),
                theme::wave(state.motion_tick, 12)
            ),
            Style::default()
                .fg(theme::pulse_color(state.motion_tick))
                .bg(theme::BG)
                .add_modifier(Modifier::BOLD),
        )
    } else {
        Span::styled("ready", theme::muted())
    };
    let telemetry = Line::from(vec![
        theme::badge("Agent", theme::ACCENT_ALT),
        Span::styled(" ", Style::default().bg(theme::BG)),
        pulse,
        theme::separator(),
        Span::styled(
            format!("{} messages", state.agent_messages.len()),
            Style::default().fg(theme::TEXT).bg(theme::BG),
        ),
        theme::separator(),
        Span::styled(
            format!("{} tasks", state.agent_tasks.len()),
            Style::default().fg(theme::TEXT).bg(theme::BG),
        ),
        theme::separator(),
        Span::styled(
            format!("{} facts", state.memory_facts.len()),
            Style::default().fg(theme::TEXT).bg(theme::BG),
        ),
    ]);
    frame.render_widget(
        Paragraph::new(telemetry).style(Style::default().bg(theme::BG)),
        rows[1],
    );
}

fn render_conversation(frame: &mut Frame<'_>, area: Rect, state: &AppState) {
    let title = if state.agent_is_busy {
        format!("Agent Chat {} thinking", theme::spinner(state.motion_tick))
    } else {
        "Agent Chat".to_owned()
    };
    let block = block(title, state.agent_is_busy);

    if state.agent_messages.is_empty() {
        let text = Paragraph::new("No agent messages. Press Enter or 'i' to compose.")
            .style(theme::muted())
            .block(block)
            .wrap(Wrap { trim: true });
        frame.render_widget(text, area);
        return;
    }

    let lines = state
        .agent_messages
        .iter()
        .flat_map(|message| {
            let role = if message.role == "user" {
                theme::badge("You", theme::ACCENT)
            } else {
                theme::badge("Agent", theme::WARN)
            };
            [
                Line::from(vec![
                    role,
                    Span::raw(" "),
                    Span::styled(message.content.clone(), theme::text()),
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
        Line::from(vec![
            theme::quiet_badge("h/l"),
            Span::styled(" switch section", theme::text()),
        ]),
        Line::from(vec![
            theme::quiet_badge("Enter"),
            Span::styled(" compose chat", theme::text()),
        ]),
        Line::from(vec![
            theme::quiet_badge("c/x"),
            Span::styled(" clear chat", theme::text()),
        ]),
        Line::from(""),
        metric_line("Picks", state.agent_picks.len(), theme::ACCENT),
        metric_line("Tasks", state.agent_tasks.len(), theme::WARN),
        metric_line("Notes", state.agent_notes.len(), theme::ACCENT_ALT),
        metric_line("Memory", state.memory_facts.len(), theme::GOOD),
    ];
    frame.render_widget(
        Paragraph::new(lines)
            .style(theme::text())
            .block(block("Agent", false)),
        area,
    );
}

fn render_picks(frame: &mut Frame<'_>, area: Rect, state: &AppState) {
    let block = block("Picks  p play  a queue  A next", false);
    if state.agent_picks.is_empty() {
        frame.render_widget(
            Paragraph::new("No picks projected.")
                .style(theme::muted())
                .block(block),
            area,
        );
        return;
    }
    let items = state
        .agent_picks
        .iter()
        .enumerate()
        .map(|(index, pick)| {
            let base = row_style(index == state.selected_agent_pick);
            ListItem::new(Line::from(vec![
                theme::selected_prefix(index == state.selected_agent_pick, state.motion_tick),
                Span::styled(&pick.episode_title, base),
                Span::styled(
                    format!("  {:.0}% {}", pick.pick_score * 100.0, pick.pick_reason),
                    theme::muted(),
                ),
            ]))
        })
        .collect::<Vec<_>>();
    frame.render_widget(List::new(items).block(block), area);
}

fn render_tasks(frame: &mut Frame<'_>, area: Rect, state: &AppState) {
    let block = block("Tasks  n new  r run  e enable  d delete", false);
    if state.agent_tasks.is_empty() {
        frame.render_widget(
            Paragraph::new("No scheduled tasks.")
                .style(theme::muted())
                .block(block),
            area,
        );
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
                theme::selected_prefix(index == state.selected_agent_task, state.motion_tick),
                Span::styled(&task.title, base),
                Span::styled(
                    format!("  {} | {} | {}", enabled, task.status, task.schedule),
                    theme::muted(),
                ),
            ]))
        })
        .collect::<Vec<_>>();
    frame.render_widget(List::new(items).block(block), area);
}

fn render_notes(frame: &mut Frame<'_>, area: Rect, state: &AppState) {
    let block = block("Agent Notes  r fetch  n publish", false);
    if state.agent_notes.is_empty() {
        frame.render_widget(
            Paragraph::new("No notes projected. Press 'r' to fetch inbound notes.")
                .style(theme::muted())
                .block(block),
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
                theme::selected_prefix(index == state.selected_agent_note, state.motion_tick),
                Span::styled(format::short_id(&note.author_npub), base),
                Span::styled(format!("  {}  {}", trust, note.content), theme::text()),
            ]))
        })
        .collect::<Vec<_>>();
    frame.render_widget(List::new(items).block(block), area);
}

fn render_memory(frame: &mut Frame<'_>, area: Rect, state: &AppState) {
    let block = block("Memory  n new  d forget  x clear", false);
    if state.memory_facts.is_empty() {
        frame.render_widget(
            Paragraph::new("No memory facts.")
                .style(theme::muted())
                .block(block),
            area,
        );
        return;
    }
    let items = state
        .memory_facts
        .iter()
        .enumerate()
        .map(|(index, fact)| {
            let base = row_style(index == state.selected_memory_fact);
            ListItem::new(Line::from(vec![
                theme::selected_prefix(index == state.selected_memory_fact, state.motion_tick),
                Span::styled(&fact.key, base),
                Span::styled(
                    format!(" = {}  ({})", fact.value, fact.source),
                    theme::muted(),
                ),
            ]))
        })
        .collect::<Vec<_>>();
    frame.render_widget(List::new(items).block(block), area);
}

fn metric_line(label: &str, count: usize, color: ratatui::style::Color) -> Line<'static> {
    Line::from(vec![
        theme::badge(label, color),
        Span::styled(format!(" {count}"), theme::text()),
    ])
}

fn row_style(selected: bool) -> Style {
    if selected {
        theme::selected()
    } else {
        theme::text()
    }
}

fn block(title: impl Into<String>, focused: bool) -> Block<'static> {
    theme::panel(title, focused)
}
