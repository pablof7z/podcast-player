use ratatui::layout::{Constraint, Layout, Rect};
use ratatui::style::{Color, Modifier, Style};
use ratatui::text::{Line, Span};
use ratatui::widgets::{List, ListItem, Paragraph, Wrap};
use ratatui::Frame;

use crate::app::AppState;
use crate::rows::DownloadRow;
use crate::ui::{format, theme};

pub fn render(frame: &mut Frame<'_>, area: Rect, state: &AppState) {
    let cols =
        Layout::horizontal([Constraint::Percentage(62), Constraint::Percentage(38)]).split(area);

    render_list(frame, cols[0], state);
    render_detail(frame, cols[1], state);
}

fn render_list(frame: &mut Frame<'_>, area: Rect, state: &AppState) {
    let block = theme::panel(format!("Downloads ({})", state.downloads.len()), true);

    if state.downloads.is_empty() {
        let text = Paragraph::new("No active, queued, paused, or failed downloads.")
            .style(theme::muted())
            .block(block);
        frame.render_widget(text, area);
        return;
    }

    let items = state
        .downloads
        .iter()
        .enumerate()
        .map(|(index, download)| {
            let selected = index == state.selected_download;
            let base = if selected {
                theme::selected()
            } else {
                theme::text()
            };
            let title = title_for_download(state, download);
            let progress = format!("{:>3}%", (download.progress.clamp(0.0, 1.0) * 100.0) as u8);
            let active = download.state == "active";
            let mut spans = vec![
                Span::styled(
                    format!("{:<10}", status_label(download, state.motion_tick)),
                    status_style(download, state.motion_tick),
                ),
                Span::styled(format!(" {progress} "), theme::muted()),
                Span::styled(
                    progress_bar(download.progress, 14, state.motion_tick, active),
                    Style::default().fg(if active {
                        theme::pulse_color(state.motion_tick)
                    } else {
                        theme::ACCENT_ALT
                    }),
                ),
                Span::styled("  ", Style::default()),
                Span::styled(title, base),
            ];
            if download.kind != "episode" {
                spans.push(Span::styled(
                    format!("  {}", download.kind),
                    Style::default().fg(theme::ACCENT_ALT),
                ));
            }
            ListItem::new(Line::from(spans))
        })
        .collect::<Vec<_>>();

    frame.render_widget(List::new(items).block(block), area);
}

fn render_detail(frame: &mut Frame<'_>, area: Rect, state: &AppState) {
    let title = state
        .downloads
        .get(state.selected_download)
        .map(|download| {
            format!(
                "Download Detail {}",
                status_label(download, state.motion_tick)
            )
        })
        .unwrap_or_else(|| "Download Detail".to_owned());
    let block = theme::panel(title, false);

    let Some(download) = state.downloads.get(state.selected_download) else {
        frame.render_widget(
            Paragraph::new("No download selected.")
                .style(theme::muted())
                .block(block),
            area,
        );
        return;
    };

    let title = title_for_download(state, download);
    let size = download
        .total_bytes
        .map(format::bytes)
        .unwrap_or_else(|| "unknown".to_string());
    let url = if download.url.is_empty() {
        "unknown".to_string()
    } else {
        download.url.clone()
    };

    let mut lines = vec![
        Line::from(Span::styled(
            title,
            Style::default().add_modifier(Modifier::BOLD),
        )),
        Line::from(""),
        Line::from(format!("id: {}", download.episode_id)),
        Line::from(format!("kind: {}", download.kind)),
        Line::from(format!("state: {}", download.state)),
        Line::from(vec![
            Span::styled("progress: ", theme::muted()),
            Span::styled(
                progress_bar(
                    download.progress,
                    22,
                    state.motion_tick,
                    download.state == "active",
                ),
                Style::default().fg(status_color(download, state.motion_tick)),
            ),
            Span::styled(
                format!(" {:.0}%", download.progress.clamp(0.0, 1.0) * 100.0),
                theme::text(),
            ),
        ]),
        Line::from(format!("size: {size}")),
        Line::from(format!("url: {url}")),
        Line::from(""),
        Line::from("Enter toggle  p pause  r resume  d cancel  x cancel all  D delete file"),
    ];

    if let Some(error) = &download.error {
        lines.push(Line::from(""));
        lines.push(Line::from(vec![
            Span::styled("error: ", Style::default().fg(theme::DANGER)),
            Span::styled(error, Style::default().fg(theme::DANGER)),
        ]));
    }

    frame.render_widget(
        Paragraph::new(lines)
            .style(theme::text())
            .block(block)
            .wrap(Wrap { trim: true }),
        area,
    );
}

fn title_for_download(state: &AppState, download: &DownloadRow) -> String {
    state
        .library
        .iter()
        .flat_map(|podcast| podcast.episodes.iter())
        .find(|episode| episode.id == download.episode_id)
        .map(|episode| episode.title.clone())
        .unwrap_or_else(|| format::short_id(&download.episode_id))
}

fn status_label(download: &DownloadRow, tick: u64) -> String {
    match download.state.as_str() {
        "active" => format!("{} active", theme::spinner(tick)),
        "queued" => "queued".to_owned(),
        "paused" => "paused".to_owned(),
        "failed" => "failed".to_owned(),
        other => other.to_owned(),
    }
}

fn status_style(download: &DownloadRow, tick: u64) -> Style {
    Style::default()
        .fg(status_color(download, tick))
        .add_modifier(Modifier::BOLD)
}

fn status_color(download: &DownloadRow, tick: u64) -> Color {
    match download.state.as_str() {
        "active" => theme::pulse_color(tick),
        "queued" => theme::WARN,
        "paused" => theme::ACCENT_ALT,
        "failed" => theme::DANGER,
        _ => theme::MUTED,
    }
}

fn progress_bar(progress: f32, width: usize, tick: u64, active: bool) -> String {
    let clamped = progress.clamp(0.0, 1.0);
    let filled = (clamped * width as f32).round() as usize;
    let filled = filled.min(width);
    let mut cells = vec!["░"; width];
    for cell in cells.iter_mut().take(filled) {
        *cell = "█";
    }
    if active && filled < width {
        let shimmer = (tick as usize % width).max(filled);
        cells[shimmer.min(width - 1)] = "▒";
    }
    cells.join("")
}
