use crossterm::event::{KeyCode, KeyEvent};

use crate::app::AppState;
use crate::runtime::AppRuntime;

pub(super) fn handle_downloads_keys(state: &mut AppState, runtime: &AppRuntime, key: KeyEvent) {
    match key.code {
        KeyCode::Char('j') | KeyCode::Down => state.next_download(),
        KeyCode::Char('k') | KeyCode::Up => state.previous_download(),
        KeyCode::Char('g') | KeyCode::Home => state.jump_download_top(),
        KeyCode::Char('G') | KeyCode::End => state.jump_download_bottom(),
        KeyCode::Enter => toggle_selected_download(state, runtime),
        KeyCode::Char('p') => pause_selected_download(state, runtime),
        KeyCode::Char('r') => resume_selected_download(state, runtime),
        KeyCode::Char('d') => cancel_selected_download(state, runtime),
        KeyCode::Char('D') => delete_selected_download_file(state, runtime),
        KeyCode::Char('x') => cancel_all_downloads(state, runtime),
        _ => {}
    }
}

fn toggle_selected_download(state: &mut AppState, runtime: &AppRuntime) {
    match state.selected_download_state() {
        Some("paused") => resume_selected_download(state, runtime),
        Some("active") => pause_selected_download(state, runtime),
        _ => {}
    }
}

fn pause_selected_download(state: &mut AppState, runtime: &AppRuntime) {
    let Some(episode_id) = state.selected_download_episode_id() else {
        return;
    };
    match runtime.pause_download(&episode_id) {
        Ok(_) => state.push_toast("download paused"),
        Err(e) => state.status = format!("pause download error: {e}"),
    }
}

fn resume_selected_download(state: &mut AppState, runtime: &AppRuntime) {
    let Some(episode_id) = state.selected_download_episode_id() else {
        return;
    };
    match runtime.resume_download(&episode_id) {
        Ok(_) => state.push_toast("download resumed"),
        Err(e) => state.status = format!("resume download error: {e}"),
    }
}

fn cancel_selected_download(state: &mut AppState, runtime: &AppRuntime) {
    let Some(episode_id) = state.selected_download_episode_id() else {
        return;
    };
    match runtime.cancel_download(&episode_id) {
        Ok(_) => state.push_toast("download cancelled"),
        Err(e) => state.status = format!("cancel download error: {e}"),
    }
}

fn delete_selected_download_file(state: &mut AppState, runtime: &AppRuntime) {
    let Some(episode_id) = state.selected_download_episode_id() else {
        return;
    };
    super::delete_download_for_episode_id(state, runtime, &episode_id);
}

fn cancel_all_downloads(state: &mut AppState, runtime: &AppRuntime) {
    match runtime.cancel_all_downloads() {
        Ok(_) => state.push_toast("all downloads cancelled"),
        Err(e) => state.status = format!("cancel downloads error: {e}"),
    }
}
