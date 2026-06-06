use ratatui::layout::{Alignment, Rect};
use ratatui::style::{Color, Modifier, Style};
use ratatui::text::{Line, Span};
use ratatui::widgets::{Block, Borders, Clear, Paragraph, Wrap};
use ratatui::Frame;

use crate::app::{AppState, EpisodeRow, Mode};
use crate::ui::format;

pub fn render(frame: &mut Frame<'_>, area: Rect, state: &AppState) {
    let block = Block::default()
        .borders(Borders::ALL)
        .border_style(Style::default().fg(Color::Cyan))
        .title(" Episode Detail ");

    let inner = block.inner(area);
    frame.render_widget(Clear, area);
    frame.render_widget(block, area);

    let ep = match state.episodes.get(state.selected_episode) {
        Some(e) => e,
        None => {
            let empty = Paragraph::new("No episode selected").alignment(Alignment::Center);
            frame.render_widget(empty, inner);
            return;
        }
    };

    let scroll = match state.mode {
        Mode::EpisodeDetail { scroll } => scroll,
        _ => 0,
    };

    let lines = build_detail_lines(ep, state);
    let visible_lines = if lines.len() > scroll {
        &lines[scroll..]
    } else {
        &[]
    };

    let paragraph = Paragraph::new(visible_lines.to_vec()).wrap(Wrap { trim: true });
    frame.render_widget(paragraph, inner);
}

fn build_detail_lines(ep: &EpisodeRow, state: &AppState) -> Vec<Line<'static>> {
    let mut lines = Vec::new();

    lines.push(Line::from(vec![Span::styled(
        ep.title.clone(),
        Style::default().add_modifier(Modifier::BOLD),
    )]));

    let mut meta_parts = Vec::new();
    if let Some(ref pt) = ep.podcast_title {
        meta_parts.push(pt.clone());
    }
    if let Some(dur) = ep.duration_secs {
        meta_parts.push(format::duration(dur));
    }
    if ep.file_size_bytes > 0 {
        meta_parts.push(format::bytes(ep.file_size_bytes as u64));
    }
    if ep.played {
        meta_parts.push("played".to_string());
    }
    if ep.starred {
        meta_parts.push("starred".to_string());
    }
    if ep.download_path.is_some() {
        meta_parts.push("downloaded".to_string());
    }
    if ep.chapters_count > 0 {
        meta_parts.push(format!("{} chapters", ep.chapters_count));
    }
    if ep.has_transcript {
        meta_parts.push("transcript".to_string());
    } else if !ep.transcript_status.is_empty() {
        meta_parts.push(format!("transcript {}", ep.transcript_status));
    } else if ep.transcript_url.is_some() {
        meta_parts.push("transcript source".to_string());
    }
    if ep.summary.is_some() {
        meta_parts.push("summary".to_string());
    }
    if !ep.ai_categories.is_empty() {
        meta_parts.push(ep.ai_categories.join(", "));
    }
    if !ep.ad_segments.is_empty() {
        meta_parts.push(format!("{} ad segments", ep.ad_segments.len()));
    }
    if !meta_parts.is_empty() {
        lines.push(Line::from(vec![Span::styled(
            meta_parts.join(" | "),
            Style::default().fg(Color::DarkGray),
        )]));
    }

    lines.push(Line::from(""));

    if let Some(ref np) = state.now_playing {
        if np.episode_id == ep.id {
            let status = if np.is_playing {
                "▶ playing"
            } else {
                "⏸ paused"
            };
            lines.push(Line::from(vec![Span::styled(
                status,
                Style::default().fg(Color::Green),
            )]));
            if np.duration_secs > 0.0 {
                lines.push(Line::from(vec![Span::styled(
                    format!(
                        "position: {} / {}",
                        format::duration(np.position_secs),
                        format::duration(np.duration_secs)
                    ),
                    Style::default().fg(Color::DarkGray),
                )]));
            }
            lines.push(Line::from(""));
        }
    }

    push_section(&mut lines, "Summary");
    if let Some(summary) = &ep.summary {
        push_paragraph(&mut lines, summary);
    } else {
        lines.push(dim_line("No summary generated yet."));
    }

    push_section(&mut lines, "Chapters");
    if ep.chapters.is_empty() {
        lines.push(dim_line("No chapters loaded."));
    } else {
        for chapter in ep.chapters.iter().take(16) {
            let mut meta = vec![format::duration(chapter.start_secs)];
            if let Some(end) = chapter.end_secs {
                meta.push(format!("to {}", format::duration(end)));
            }
            if chapter.is_ai_generated {
                meta.push("ai".to_string());
            }
            lines.push(Line::from(format!(
                "{}  {}",
                meta.join(" | "),
                chapter.title
            )));
        }
        if ep.chapters.len() > 16 {
            lines.push(dim_line(&format!(
                "{} more chapters",
                ep.chapters.len() - 16
            )));
        }
    }

    push_section(&mut lines, "Transcript");
    if let Some(message) = &ep.transcript_status_message {
        lines.push(Line::from(vec![
            Span::styled(
                format!("status: {}", ep.transcript_status),
                Style::default().fg(Color::Yellow),
            ),
            Span::styled(
                format!(" | {message}"),
                Style::default().fg(Color::DarkGray),
            ),
        ]));
    } else if !ep.transcript_status.is_empty() {
        lines.push(Line::from(vec![Span::styled(
            format!("status: {}", ep.transcript_status),
            Style::default().fg(Color::Yellow),
        )]));
    }
    if let Some(url) = &ep.transcript_url {
        lines.push(dim_line(&format!("source: {url}")));
    }
    if !ep.transcript_entries.is_empty() {
        for entry in ep.transcript_entries.iter().take(12) {
            let speaker = entry
                .speaker
                .as_deref()
                .filter(|value| !value.is_empty())
                .map(|value| format!("{value}: "))
                .unwrap_or_default();
            lines.push(Line::from(format!(
                "{}  {}{}",
                format::duration(entry.start_secs),
                speaker,
                entry.text
            )));
        }
        if ep.transcript_entries.len() > 12 {
            lines.push(dim_line(&format!(
                "{} more transcript rows",
                ep.transcript_entries.len() - 12
            )));
        }
    } else if let Some(transcript) = &ep.transcript {
        push_paragraph(&mut lines, transcript);
    } else if ep.transcript_url.is_none() && ep.transcript_status.is_empty() {
        lines.push(dim_line("No transcript projected."));
    }

    push_section(&mut lines, "Ad Segments");
    if ep.ad_segments.is_empty() {
        lines.push(dim_line("No ad-skip segments."));
    } else {
        for segment in &ep.ad_segments {
            lines.push(Line::from(format!(
                "{} to {}  {:?}",
                format::duration(segment.start_secs),
                format::duration(segment.end_secs),
                segment.kind
            )));
        }
    }

    push_section(&mut lines, "Comments");
    let comments_match = state.comments_episode_id.as_deref() == Some(ep.id.as_str());
    if comments_match && !state.comments.is_empty() {
        for comment in state.comments.iter().take(8) {
            let author = comment
                .author_name
                .as_deref()
                .unwrap_or(comment.author_npub.as_str());
            lines.push(Line::from(vec![Span::styled(
                author.to_string(),
                Style::default().add_modifier(Modifier::BOLD),
            )]));
            push_paragraph(&mut lines, &comment.content);
        }
        if state.comments.len() > 8 {
            lines.push(dim_line(&format!(
                "{} more comments",
                state.comments.len() - 8
            )));
        }
    } else if comments_match {
        lines.push(dim_line("No comments loaded."));
    } else {
        lines.push(dim_line("Fetch comments to load this episode's thread."));
    }

    push_section(&mut lines, "Description");
    if let Some(ref desc) = ep.description {
        push_paragraph(&mut lines, desc);
    } else {
        lines.push(dim_line("No description available."));
    }

    lines.push(Line::from(""));
    lines.push(Line::from(vec![Span::styled(
        "p play | d download | D delete | s/S star | a/A queue | c clip | t transcript | H chapters | u compile | m summary | f comments | C post | R reset | z/Z sleep | x cancel timer | Esc close",
        Style::default().fg(Color::DarkGray),
    )]));

    lines
}

fn push_section(lines: &mut Vec<Line<'static>>, title: &str) {
    lines.push(Line::from(""));
    lines.push(Line::from(vec![Span::styled(
        title.to_string(),
        Style::default()
            .fg(Color::Cyan)
            .add_modifier(Modifier::BOLD),
    )]));
}

fn push_paragraph(lines: &mut Vec<Line<'static>>, text: &str) {
    for paragraph in text.split("\n\n") {
        for line in paragraph.lines() {
            lines.push(Line::from(line.to_string()));
        }
        lines.push(Line::from(""));
    }
}

fn dim_line(text: &str) -> Line<'static> {
    Line::from(vec![Span::styled(
        text.to_string(),
        Style::default().fg(Color::DarkGray),
    )])
}
