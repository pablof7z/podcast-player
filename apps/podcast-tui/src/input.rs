#[path = "input_tabs.rs"]
mod tabs;

use crossterm::event::{KeyCode, KeyEvent, KeyModifiers};

use crate::app::{AppState, Mode, Tab};
use crate::runtime::AppRuntime;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum InputFlow {
    Continue,
    Quit,
}

pub fn handle_key(state: &mut AppState, runtime: &AppRuntime, key: KeyEvent) -> InputFlow {
    if key.code == KeyCode::Char('c') && key.modifiers.contains(KeyModifiers::CONTROL) {
        return InputFlow::Quit;
    }

    if handle_mode_key(state, runtime, key) {
        return InputFlow::Continue;
    }

    if key.code == KeyCode::Char('q') {
        return InputFlow::Quit;
    }

    if key.code == KeyCode::Char('?') {
        state.toggle_help();
        return InputFlow::Continue;
    }

    if key.code == KeyCode::Esc && state.close_help() {
        return InputFlow::Continue;
    }

    match key.code {
        KeyCode::Tab => state.next_tab(),
        KeyCode::BackTab => state.previous_tab(),
        KeyCode::Char('n') => {
            state.mode = Mode::SubscribeInput;
            state.subscribe_input.clear();
            state.status = "enter feed URL to subscribe".to_string();
            return InputFlow::Continue;
        }
        KeyCode::Char('/') => {
            state.mode = Mode::SearchInput;
            state.search_input.clear();
            state.status = "enter search query".to_string();
            return InputFlow::Continue;
        }
        _ => {}
    }

    match state.tab {
        Tab::Library => tabs::handle_library_keys(state, runtime, key),
        Tab::Queue => tabs::handle_queue_keys(state, runtime, key),
        Tab::Inbox => tabs::handle_inbox_keys(state, runtime, key),
        Tab::Search => tabs::handle_search_keys(state, runtime, key),
        Tab::Bookmarks => tabs::handle_bookmark_keys(state, runtime, key),
        Tab::Clips => tabs::handle_clips_keys(state, runtime, key),
        Tab::Agent => tabs::handle_agent_keys(state, runtime, key),
        Tab::Wiki => tabs::handle_wiki_keys(state, runtime, key),
        Tab::Social => tabs::handle_social_keys(state, runtime, key),
        Tab::Settings => tabs::handle_settings_keys(state, runtime, key),
    }

    InputFlow::Continue
}

fn handle_mode_key(state: &mut AppState, runtime: &AppRuntime, key: KeyEvent) -> bool {
    match state.mode {
        Mode::SearchInput => handle_search_input(state, runtime, key),
        Mode::SubscribeInput => handle_subscribe_input(state, runtime, key),
        Mode::AgentInput => handle_agent_input(state, runtime, key),
        Mode::EpisodeDetail { .. } => handle_episode_detail_key(state, runtime, key),
        Mode::Normal => false,
    }
}

fn handle_search_input(state: &mut AppState, runtime: &AppRuntime, key: KeyEvent) -> bool {
    match key.code {
        KeyCode::Esc => state.mode = Mode::Normal,
        KeyCode::Enter => {
            let query = state.search_input.trim().to_string();
            state.mode = Mode::Normal;
            state.tab = Tab::Search;
            if !query.is_empty() {
                match runtime.search_itunes(&query) {
                    Ok(_) => state.status = format!("searching iTunes for: {query}"),
                    Err(e) => state.status = format!("search error: {e}"),
                }
            }
        }
        KeyCode::Backspace => {
            state.search_input.pop();
        }
        KeyCode::Char(c) => state.search_input.push(c),
        _ => {}
    }
    true
}

fn handle_subscribe_input(state: &mut AppState, runtime: &AppRuntime, key: KeyEvent) -> bool {
    match key.code {
        KeyCode::Esc => state.mode = Mode::Normal,
        KeyCode::Enter => {
            let url = state.subscribe_input.trim().to_string();
            state.mode = Mode::Normal;
            if !url.is_empty() {
                match runtime.subscribe(&url) {
                    Ok(_) => state.status = format!("subscribing to: {url}"),
                    Err(e) => state.status = format!("subscribe error: {e}"),
                }
            }
        }
        KeyCode::Backspace => {
            state.subscribe_input.pop();
        }
        KeyCode::Char(c) => state.subscribe_input.push(c),
        _ => {}
    }
    true
}

fn handle_agent_input(state: &mut AppState, runtime: &AppRuntime, key: KeyEvent) -> bool {
    match key.code {
        KeyCode::Esc => state.mode = Mode::Normal,
        KeyCode::Enter => {
            let message = state.agent_input.trim().to_string();
            state.agent_input.clear();
            state.mode = Mode::Normal;
            state.tab = Tab::Agent;
            if !message.is_empty() {
                match runtime.send_agent_message(&message) {
                    Ok(_) => state.status = "sent agent message".to_string(),
                    Err(e) => state.status = format!("agent send error: {e}"),
                }
            }
        }
        KeyCode::Backspace => {
            state.agent_input.pop();
        }
        KeyCode::Char(c) => state.agent_input.push(c),
        _ => {}
    }
    true
}

fn handle_episode_detail_key(state: &mut AppState, runtime: &AppRuntime, key: KeyEvent) -> bool {
    match key.code {
        KeyCode::Esc | KeyCode::Char('q') | KeyCode::Char('h') => state.close_episode_detail(),
        KeyCode::Char('j') | KeyCode::Down => state.episode_detail_scroll_down(),
        KeyCode::Char('k') | KeyCode::Up => state.episode_detail_scroll_up(),
        KeyCode::Char('g') | KeyCode::Home => state.episode_detail_scroll_top(),
        KeyCode::Char('p') => play_selected_episode(state, runtime),
        KeyCode::Char('d') => download_selected_episode(state, runtime),
        KeyCode::Char('s') => star_selected_episode(state, runtime),
        KeyCode::Char('S') => unstar_selected_episode(state, runtime),
        KeyCode::Char('a') => queue_selected_episode(state, runtime, false),
        KeyCode::Char('A') => queue_selected_episode(state, runtime, true),
        KeyCode::Char('c') => clip_selected_episode(state, runtime),
        _ => {}
    }
    true
}

fn play_selected_episode(state: &mut AppState, runtime: &AppRuntime) {
    if let Some(id) = state.selected_episode_id() {
        let _ = runtime.play_episode(&id, 0.0);
        state.status = format!("playing {id}");
    }
}

fn download_selected_episode(state: &mut AppState, runtime: &AppRuntime) {
    if let Some(id) = state.selected_episode_id() {
        let _ = runtime.download_episode(&id);
        state.push_toast("download queued");
    }
}

fn star_selected_episode(state: &mut AppState, runtime: &AppRuntime) {
    if let Some(id) = state.selected_episode_id() {
        let _ = runtime.star(&id);
        state.push_toast("starred");
    }
}

fn unstar_selected_episode(state: &mut AppState, runtime: &AppRuntime) {
    if let Some(id) = state.selected_episode_id() {
        let _ = runtime.unstar(&id);
        state.push_toast("unstarred");
    }
}

fn queue_selected_episode(state: &mut AppState, runtime: &AppRuntime, next: bool) {
    if let Some(id) = state.selected_episode_id() {
        let result = if next {
            runtime.add_next_to_queue(&id)
        } else {
            runtime.add_to_queue(&id)
        };
        if result.is_ok() {
            state.push_toast(if next { "added next" } else { "added to queue" });
        }
    }
}

fn clip_selected_episode(state: &mut AppState, runtime: &AppRuntime) {
    if let Some((id, position)) = state.selected_episode_clip_target() {
        match runtime.auto_snip(&id, position) {
            Ok(_) => state.push_toast("clip saved"),
            Err(e) => state.status = format!("clip error: {e}"),
        }
    }
}
