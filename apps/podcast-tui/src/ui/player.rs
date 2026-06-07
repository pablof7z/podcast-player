use ratatui::layout::{Alignment, Constraint, Layout, Rect};
use ratatui::style::{Modifier, Style};
use ratatui::text::{Line, Span};
use ratatui::widgets::{Gauge, Paragraph, Sparkline};
use ratatui::Frame;

use crate::app::AppState;
use crate::ui::theme;

pub fn render(frame: &mut Frame<'_>, area: Rect, state: &AppState) {
    let Some(ref np) = state.now_playing else {
        let block = theme::panel_with_footer("Player", "Select an episode and press p", false);
        let inner = block.inner(area);
        frame.render_widget(block, area);
        let rows = Layout::vertical([
            Constraint::Length(1),
            Constraint::Length(1),
            Constraint::Min(1),
        ])
        .split(inner);
        frame.render_widget(
            Paragraph::new("Nothing playing")
                .alignment(Alignment::Center)
                .style(theme::muted()),
            rows[0],
        );
        frame.render_widget(
            Paragraph::new(theme::wave(state.motion_tick / 2, 24))
                .alignment(Alignment::Center)
                .style(Style::default().fg(theme::TRACK)),
            rows[1],
        );
        return;
    };

    let activity = if np.is_playing {
        format!("Now Playing {}", theme::meter(state.motion_tick))
    } else {
        "Now Playing paused".to_owned()
    };
    let footer = "Space play/pause  ←/→ seek  +/- volume";
    let block = theme::panel_with_footer(activity, footer, np.is_playing);
    let inner = block.inner(area);
    frame.render_widget(block, area);

    let rows = Layout::vertical([
        Constraint::Length(1), // title
        Constraint::Length(1), // context
        Constraint::Length(1), // waveform
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

    let sample_count = rows[2].width.saturating_sub(2).clamp(12, 80) as usize;
    let tick = if np.is_playing { state.motion_tick } else { 0 };
    let samples = theme::waveform_samples(tick, sample_count);
    let waveform_style = if np.is_playing {
        Style::default().fg(theme::pulse_color(state.motion_tick))
    } else {
        theme::muted()
    };
    let waveform = Sparkline::default()
        .data(&samples)
        .max(8)
        .style(waveform_style);
    frame.render_widget(waveform, rows[2]);

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
        .gauge_style(
            Style::default()
                .fg(theme::pulse_color(state.motion_tick))
                .bg(theme::TRACK),
        );
    frame.render_widget(gauge, rows[3]);
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
