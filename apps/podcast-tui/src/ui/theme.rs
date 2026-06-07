use ratatui::style::{Color, Modifier, Style};
use ratatui::text::{Line, Span};
use ratatui::widgets::{Block, BorderType, Borders, Padding};

pub const BG: Color = Color::Rgb(10, 13, 18);
pub const SURFACE: Color = Color::Rgb(15, 20, 28);
pub const SURFACE_LIFTED: Color = Color::Rgb(20, 27, 37);
pub const PANEL: Color = Color::Rgb(24, 31, 42);
pub const TEXT: Color = Color::Rgb(222, 232, 242);
pub const MUTED: Color = Color::Rgb(121, 137, 153);
pub const ACCENT: Color = Color::Rgb(93, 230, 190);
pub const ACCENT_ALT: Color = Color::Rgb(126, 169, 255);
pub const GOOD: Color = Color::Rgb(90, 214, 142);
pub const WARN: Color = Color::Rgb(245, 189, 83);
pub const DANGER: Color = Color::Rgb(248, 112, 132);
pub const TRACK: Color = Color::Rgb(36, 45, 58);
pub const BORDER_IDLE: Color = Color::Rgb(58, 70, 86);

pub fn panel(title: impl Into<String>, focused: bool) -> Block<'static> {
    let title = title.into();
    let title_style = if focused {
        Style::default().fg(ACCENT).add_modifier(Modifier::BOLD)
    } else {
        Style::default().fg(TEXT)
    };

    Block::default()
        .borders(Borders::ALL)
        .border_type(BorderType::Rounded)
        .border_style(Style::default().fg(border_color(focused)))
        .style(Style::default().bg(if focused { SURFACE_LIFTED } else { SURFACE }))
        .title(Line::from(vec![
            Span::raw(" "),
            Span::styled(title, title_style),
            Span::raw(" "),
        ]))
        .padding(Padding::horizontal(1))
}

pub fn panel_with_footer(
    title: impl Into<String>,
    footer: impl Into<String>,
    focused: bool,
) -> Block<'static> {
    panel(title, focused).title_bottom(Line::from(vec![
        Span::raw(" "),
        Span::styled(footer.into(), muted()),
        Span::raw(" "),
    ]))
}

pub fn border_color(focused: bool) -> Color {
    if focused {
        ACCENT
    } else {
        BORDER_IDLE
    }
}

pub fn selected() -> Style {
    Style::default()
        .fg(Color::Black)
        .bg(ACCENT)
        .add_modifier(Modifier::BOLD)
}

pub fn selected_alt() -> Style {
    Style::default()
        .fg(TEXT)
        .bg(PANEL)
        .add_modifier(Modifier::BOLD)
}

pub fn text() -> Style {
    Style::default().fg(TEXT)
}

pub fn muted() -> Style {
    Style::default().fg(MUTED)
}

pub fn accent() -> Style {
    Style::default().fg(ACCENT).add_modifier(Modifier::BOLD)
}

pub fn warn() -> Style {
    Style::default().fg(WARN).add_modifier(Modifier::BOLD)
}

pub fn danger() -> Style {
    Style::default().fg(DANGER).add_modifier(Modifier::BOLD)
}

pub fn spinner(tick: u64) -> &'static str {
    const FRAMES: [&str; 8] = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧"];
    FRAMES[tick as usize % FRAMES.len()]
}

pub fn pulse_color(tick: u64) -> Color {
    const COLORS: [Color; 6] = [ACCENT, GOOD, ACCENT, ACCENT_ALT, ACCENT, WARN];
    COLORS[tick as usize % COLORS.len()]
}

pub fn meter(tick: u64) -> &'static str {
    const FRAMES: [&str; 8] = ["▁▂▃", "▂▃▄", "▃▄▅", "▄▅▆", "▅▆▇", "▆▇█", "▅▆▇", "▃▄▅"];
    FRAMES[tick as usize % FRAMES.len()]
}

pub fn selected_prefix(selected: bool, tick: u64) -> Span<'static> {
    if selected {
        Span::styled("▌ ", Style::default().fg(pulse_color(tick)))
    } else {
        Span::styled("  ", Style::default().fg(TRACK))
    }
}

pub fn separator() -> Span<'static> {
    Span::styled("  │  ", Style::default().fg(TRACK).bg(BG))
}

pub fn badge(label: impl Into<String>, color: Color) -> Span<'static> {
    Span::styled(
        format!(" {} ", label.into()),
        Style::default()
            .fg(Color::Black)
            .bg(color)
            .add_modifier(Modifier::BOLD),
    )
}

pub fn quiet_badge(label: impl Into<String>) -> Span<'static> {
    Span::styled(
        format!(" {} ", label.into()),
        Style::default().fg(TEXT).bg(PANEL),
    )
}

pub fn wave(tick: u64, width: usize) -> String {
    const LEVELS: [char; 8] = ['▁', '▂', '▃', '▄', '▅', '▆', '▇', '█'];
    (0..width)
        .map(|index| {
            let phase = (index * 2 + tick as usize) % (LEVELS.len() * 2);
            let mirrored = if phase >= LEVELS.len() {
                (LEVELS.len() * 2) - phase - 1
            } else {
                phase
            };
            LEVELS[mirrored]
        })
        .collect()
}

pub fn waveform_samples(tick: u64, count: usize) -> Vec<u64> {
    (0..count)
        .map(|index| {
            let phase = (index as u64 + tick) % 12;
            let mirrored = if phase > 6 { 12 - phase } else { phase };
            2 + mirrored
        })
        .collect()
}

pub fn progress_bar(progress: f32, width: usize, tick: u64, active: bool) -> String {
    let clamped = progress.clamp(0.0, 1.0);
    let filled = (clamped * width as f32).round() as usize;
    let filled = filled.min(width);
    let mut cells = vec!['░'; width];

    for cell in cells.iter_mut().take(filled) {
        *cell = '█';
    }

    if active && filled < width {
        let head = ((tick as usize) + filled).min(width - 1);
        cells[head] = '▓';
        if head + 1 < width {
            cells[head + 1] = '▒';
        }
    }

    cells.into_iter().collect()
}
