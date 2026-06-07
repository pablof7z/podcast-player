use ratatui::style::{Color, Modifier, Style};
use ratatui::widgets::{Block, BorderType, Borders};

pub const BG: Color = Color::Rgb(10, 13, 18);
pub const SURFACE: Color = Color::Rgb(15, 20, 28);
pub const PANEL: Color = Color::Rgb(24, 31, 42);
pub const TEXT: Color = Color::Rgb(222, 232, 242);
pub const MUTED: Color = Color::Rgb(121, 137, 153);
pub const ACCENT: Color = Color::Rgb(93, 230, 190);
pub const ACCENT_ALT: Color = Color::Rgb(126, 169, 255);
pub const GOOD: Color = Color::Rgb(90, 214, 142);
pub const WARN: Color = Color::Rgb(245, 189, 83);
pub const DANGER: Color = Color::Rgb(248, 112, 132);
pub const TRACK: Color = Color::Rgb(36, 45, 58);

pub fn panel(title: impl Into<String>, focused: bool) -> Block<'static> {
    Block::default()
        .borders(Borders::ALL)
        .border_type(BorderType::Rounded)
        .border_style(Style::default().fg(border_color(focused)))
        .style(Style::default().bg(SURFACE))
        .title(format!(" {} ", title.into()))
}

pub fn border_color(focused: bool) -> Color {
    if focused {
        ACCENT
    } else {
        Color::Rgb(57, 68, 83)
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

pub fn spinner(tick: u64) -> &'static str {
    const FRAMES: [&str; 8] = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧"];
    FRAMES[tick as usize % FRAMES.len()]
}

pub fn pulse_color(tick: u64) -> Color {
    const COLORS: [Color; 4] = [ACCENT, ACCENT_ALT, ACCENT, GOOD];
    COLORS[tick as usize % COLORS.len()]
}

pub fn meter(tick: u64) -> &'static str {
    const FRAMES: [&str; 6] = ["▁▃▅", "▂▄▆", "▃▅▇", "▄▆█", "▃▅▇", "▂▄▆"];
    FRAMES[tick as usize % FRAMES.len()]
}
