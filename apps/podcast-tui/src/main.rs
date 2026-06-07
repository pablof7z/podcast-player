use std::sync::mpsc;
use std::thread;

use clap::Parser;
use color_eyre::eyre::{eyre, Result};
use crossterm::event::{self, Event};
use crossterm::execute;
use crossterm::terminal::{
    disable_raw_mode, enable_raw_mode, EnterAlternateScreen, LeaveAlternateScreen,
};
use ratatui::backend::CrosstermBackend;
use ratatui::Terminal;

use podcast_tui::app::AppState;
use podcast_tui::bridge::NmpEvent;
use podcast_tui::input::{self, InputFlow};
use podcast_tui::runtime::AppRuntime;
use podcast_tui::ui;

#[derive(Debug, Parser)]
#[command(name = "podcast-tui", about = "Terminal player for the Podcast app")]
struct Args {
    #[arg(long)]
    data_dir: Option<String>,
}

enum UiEvent {
    Terminal(Event),
    Nmp(NmpEvent),
    Tick,
}

fn main() -> Result<()> {
    color_eyre::install()?;
    let args = Args::parse();
    run(args)
}

fn run(args: Args) -> Result<()> {
    let _terminal = TerminalGuard::enter()?;
    let stdout = std::io::stdout();
    let backend = CrosstermBackend::new(stdout);
    let mut terminal = Terminal::new(backend)?;

    let (runtime, nmp_rx) = AppRuntime::new(&args.data_dir).map_err(|e| eyre!(e))?;

    let (ui_tx, ui_rx) = mpsc::channel();
    spawn_terminal_reader(ui_tx.clone());
    spawn_nmp_forwarder(nmp_rx, ui_tx.clone());
    spawn_tick_timer(ui_tx);

    let mut state = AppState::default();
    let mut last_podcast_rev = runtime.podcast_snapshot_rev();

    draw(&mut terminal, &state)?;

    while let Ok(event) = ui_rx.recv() {
        match event {
            UiEvent::Terminal(Event::Key(key)) => {
                if input::handle_key(&mut state, &runtime, key) == InputFlow::Quit {
                    break;
                }
            }
            UiEvent::Terminal(_) => {}
            UiEvent::Nmp(_event) => {
                if let Some(update) = runtime.podcast_update() {
                    state.apply_podcast_update(update);
                    last_podcast_rev = runtime.podcast_snapshot_rev();
                }
            }
            UiEvent::Tick => {
                state.tick_toasts();
                state.tick_motion();
                runtime.poll_audio_position();
                let rev = runtime.podcast_snapshot_rev();
                if rev != last_podcast_rev {
                    if let Some(update) = runtime.podcast_update() {
                        state.apply_podcast_update(update);
                        last_podcast_rev = rev;
                    }
                }
            }
        }
        draw(&mut terminal, &state)?;
    }

    Ok(())
}

fn draw(
    terminal: &mut Terminal<CrosstermBackend<std::io::Stdout>>,
    state: &AppState,
) -> Result<()> {
    terminal.draw(|frame| ui::layout::render(frame, state))?;
    Ok(())
}

fn spawn_terminal_reader(tx: mpsc::Sender<UiEvent>) {
    thread::spawn(move || {
        while let Ok(event) = event::read() {
            if tx.send(UiEvent::Terminal(event)).is_err() {
                break;
            }
        }
    });
}

fn spawn_nmp_forwarder(rx: mpsc::Receiver<NmpEvent>, tx: mpsc::Sender<UiEvent>) {
    thread::spawn(move || {
        while let Ok(event) = rx.recv() {
            if tx.send(UiEvent::Nmp(event)).is_err() {
                break;
            }
        }
    });
}

fn spawn_tick_timer(tx: mpsc::Sender<UiEvent>) {
    thread::spawn(move || {
        let duration = std::time::Duration::from_millis(250);
        loop {
            thread::sleep(duration);
            if tx.send(UiEvent::Tick).is_err() {
                break;
            }
        }
    });
}

struct TerminalGuard;

impl TerminalGuard {
    fn enter() -> Result<Self> {
        enable_raw_mode()?;
        execute!(std::io::stdout(), EnterAlternateScreen)?;
        Ok(Self)
    }
}

impl Drop for TerminalGuard {
    fn drop(&mut self) {
        let _ = disable_raw_mode();
        let _ = execute!(std::io::stdout(), LeaveAlternateScreen);
    }
}
