use crossterm::event::{KeyCode, KeyEvent};

use crate::app::{AppState, Mode, SettingsSection};
use crate::runtime::AppRuntime;
use crate::settings_catalog::SETTINGS_ITEMS;
use crate::settings_state::next_relay_role;

pub(super) fn handle_settings_keys(state: &mut AppState, runtime: &AppRuntime, key: KeyEvent) {
    match key.code {
        KeyCode::Char('h') | KeyCode::Left => state.previous_settings_section(),
        KeyCode::Char('l') | KeyCode::Right => state.next_settings_section(),
        _ => match state.settings_section {
            SettingsSection::General => handle_general_settings_keys(state, runtime, key),
            SettingsSection::Relays => handle_relay_settings_keys(state, runtime, key),
        },
    }
}

fn handle_general_settings_keys(state: &mut AppState, runtime: &AppRuntime, key: KeyEvent) {
    match key.code {
        KeyCode::Char('j') | KeyCode::Down => state.next_setting(SETTINGS_ITEMS.len()),
        KeyCode::Char('k') | KeyCode::Up => state.previous_setting(),
        KeyCode::Char('g') | KeyCode::Home => state.selected_setting = 0,
        KeyCode::Char('G') | KeyCode::End => {
            state.selected_setting = SETTINGS_ITEMS.len().saturating_sub(1);
        }
        KeyCode::Enter | KeyCode::Char(' ') => {
            if let Some(item) = SETTINGS_ITEMS.get(state.selected_setting) {
                match item.activate(state, runtime) {
                    Ok(_) => state.push_toast("setting updated"),
                    Err(e) => state.status = format!("settings error: {e}"),
                }
            }
        }
        _ => {}
    }
}

fn handle_relay_settings_keys(state: &mut AppState, runtime: &AppRuntime, key: KeyEvent) {
    match key.code {
        KeyCode::Char('j') | KeyCode::Down => state.next_relay(),
        KeyCode::Char('k') | KeyCode::Up => state.previous_relay(),
        KeyCode::Char('g') | KeyCode::Home => state.jump_relay_top(),
        KeyCode::Char('G') | KeyCode::End => state.jump_relay_bottom(),
        KeyCode::Char('n') | KeyCode::Char('a') => begin_relay_input(state),
        KeyCode::Char('d') => remove_selected_relay(state, runtime),
        KeyCode::Char('r') | KeyCode::Enter | KeyCode::Char(' ') => {
            cycle_selected_relay_role(state, runtime)
        }
        _ => {}
    }
}

fn begin_relay_input(state: &mut AppState) {
    state.mode = Mode::RelayInput;
    state.relay_input.clear();
    state.status = "relay format: wss://relay.example [role]".to_string();
}

fn remove_selected_relay(state: &mut AppState, runtime: &AppRuntime) {
    let Some(url) = state.selected_relay_url() else {
        return;
    };
    match runtime.remove_relay(&url) {
        Ok(_) => state.push_toast("relay removed"),
        Err(e) => state.status = format!("relay remove error: {e}"),
    }
}

fn cycle_selected_relay_role(state: &mut AppState, runtime: &AppRuntime) {
    let Some(url) = state.selected_relay_url() else {
        return;
    };
    let role = state
        .selected_relay_role()
        .map(|role| next_relay_role(&role).to_string())
        .unwrap_or_else(|| "both".to_string());
    match runtime.set_relay_role(&url, &role) {
        Ok(_) => state.push_toast("relay role updated"),
        Err(e) => state.status = format!("relay role error: {e}"),
    }
}
