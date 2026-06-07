use ratatui::layout::{Alignment, Constraint, Layout, Rect};
use ratatui::style::{Modifier, Style};
use ratatui::text::{Line, Span};
use ratatui::widgets::{Gauge, Paragraph};
use ratatui::Frame;

use crate::app::AppState;
use crate::ui::theme;

pub fn render(frame: &mut Frame<'_>, area: Rect, state: &AppState) {
    let Some(ref np) = state.now_playing else {
        let block = theme::panel("Player", false);
        let inner = block.inner(area);
        frame.render_widget(block, area);
        let empty = Paragraph::new("Nothing playing").alignment(Alignment::Center);
        frame.render_widget(empty, inner);
        return;
    };

    let activity = if np.is_playing {
        format!("Now Playing {}", theme::meter(state.motion_tick))
    } else {
        "Now Playing paused".to_owned()
    };
    let block = theme::panel(activity, np.is_playing);
    let inner = block.inner(area);
    frame.render_widget(block, area);

    let rows = Layout::vertical([
        Constraint::Length(1), // title
        Constraint::Length(1), // context
        Constraint::Length(1), // progress
    ])
    .split(inner);

    let status_indicator = if np.is_playing {
        Span::styled(
            format!("{} ▶ ", theme::spinner(state.motion_tick)),
            Style::default().fg(theme::pulse_color(state.motion_tick)),
        )
    } else {
        Span::styled("⏸ ", Style::default().fg(theme::WARN))
    };
    let title_line = Line::from(vec![
        status_indicator,
        Span::styled(
            &np.episode_title,
            theme::text().add_modifier(Modifier::BOLD),
        ),
    ]);
    frame.render_widget(Paragraph::new(title_line), rows[0]);

    let pct = if np.duration_secs > 0.0 {
        (np.position_secs / np.duration_secs * 100.0).clamp(0.0, 100.0)
    } else {
        0.0
    };
    let context_line = Line::from(vec![
        Span::styled(&np.podcast_title, theme::accent()),
        Span::styled(
            format!(
                "  {:.0}%  {:.1}x  volume {:.0}%",
                pct,
                np.speed,
                np.volume * 100.0
            ),
            theme::muted(),
        ),
    ]);
    frame.render_widget(Paragraph::new(context_line), rows[1]);

    let (pos_label, dur_label) = (format_time(np.position_secs), format_time(np.duration_secs));
    let ratio = if np.duration_secs > 0.0 {
        np.position_secs / np.duration_secs
    } else {
        0.0
    };

    let label = format!("{} / {}", pos_label, dur_label);
    let gauge = Gauge::default()
        .ratio(ratio.clamp(0.0, 1.0))
        .label(label)
        .gauge_style(Style::default().fg(theme::ACCENT).bg(theme::TRACK));
    frame.render_widget(gauge, rows[2]);
}

fn format_time(secs: f64) -> String {
    let total = secs as u64;
    let hours = total / 3600;
    let minutes = (total % 3600) / 60;
    let seconds = total % 60;
    if hours > 0 {
        format!("{}:{:02}:{:02}", hours, minutes, seconds)
    } else {
        format!("{}:{:02}", minutes, seconds)
    }
}
