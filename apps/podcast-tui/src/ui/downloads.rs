use ratatui::layout::{Constraint, Layout, Rect};
use ratatui::style::{Color, Modifier, Style};
use ratatui::text::{Line, Span};
use ratatui::widgets::{Block, Borders, List, ListItem, Paragraph, Wrap};
use ratatui::Frame;

use crate::app::AppState;
use crate::rows::DownloadRow;
use crate::ui::format;

pub fn render(frame: &mut Frame<'_>, area: Rect, state: &AppState) {
    let cols =
        Layout::horizontal([Constraint::Percentage(62), Constraint::Percentage(38)]).split(area);

    render_list(frame, cols[0], state);
    render_detail(frame, cols[1], state);
}

fn render_list(frame: &mut Frame<'_>, area: Rect, state: &AppState) {
    let block = Block::default()
        .borders(Borders::ALL)
        .border_style(Style::default().fg(Color::DarkGray))
        .title(format!(" Downloads ({}) ", state.downloads.len()));

    if state.downloads.is_empty() {
        let text = Paragraph::new("No active, queued, paused, or failed downloads.").block(block);
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
                Style::default()
                    .fg(Color::Black)
                    .bg(Color::Cyan)
                    .add_modifier(Modifier::BOLD)
            } else {
                Style::default().fg(Color::White)
            };
            let title = title_for_download(state, download);
            let progress = format!("{:>3}%", (download.progress.clamp(0.0, 1.0) * 100.0) as u8);
            let mut spans = vec![
                Span::styled(format!("{:<7}", download.state), status_style(download)),
                Span::styled(
                    format!(" {progress} "),
                    Style::default().fg(Color::DarkGray),
                ),
                Span::styled(
                    progress_bar(download.progress, 12),
                    Style::default().fg(Color::Cyan),
                ),
                Span::styled("  ", Style::default()),
                Span::styled(title, base),
            ];
            if download.kind != "episode" {
                spans.push(Span::styled(
                    format!("  {}", download.kind),
                    Style::default().fg(Color::Magenta),
                ));
            }
            ListItem::new(Line::from(spans))
        })
        .collect::<Vec<_>>();

    frame.render_widget(List::new(items).block(block), area);
}

fn render_detail(frame: &mut Frame<'_>, area: Rect, state: &AppState) {
    let block = Block::default()
        .borders(Borders::ALL)
        .border_style(Style::default().fg(Color::DarkGray))
        .title(" Download Detail ");

    let Some(download) = state.downloads.get(state.selected_download) else {
        frame.render_widget(Paragraph::new("No download selected.").block(block), area);
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
        Line::from(format!(
            "progress: {:.0}%",
            download.progress.clamp(0.0, 1.0) * 100.0
        )),
        Line::from(format!("size: {size}")),
        Line::from(format!("url: {url}")),
        Line::from(""),
        Line::from("Enter toggle  p pause  r resume  d cancel  x cancel all  D delete file"),
    ];

    if let Some(error) = &download.error {
        lines.push(Line::from(""));
        lines.push(Line::from(vec![
            Span::styled("error: ", Style::default().fg(Color::Red)),
            Span::styled(error, Style::default().fg(Color::Red)),
        ]));
    }

    frame.render_widget(
        Paragraph::new(lines).block(block).wrap(Wrap { trim: true }),
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

fn status_style(download: &DownloadRow) -> Style {
    let color = match download.state.as_str() {
        "active" => Color::Green,
        "queued" => Color::Yellow,
        "paused" => Color::Blue,
        "failed" => Color::Red,
        _ => Color::DarkGray,
    };
    Style::default().fg(color)
}

fn progress_bar(progress: f32, width: usize) -> String {
    let clamped = progress.clamp(0.0, 1.0);
    let filled = (clamped * width as f32).round() as usize;
    format!("{}{}", "#".repeat(filled), "-".repeat(width - filled))
}
