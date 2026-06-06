use crate::app::AppState;

impl AppState {
    pub fn selected_download_episode_id(&self) -> Option<String> {
        self.downloads
            .get(self.selected_download)
            .map(|download| download.episode_id.clone())
    }

    pub fn selected_download_state(&self) -> Option<&str> {
        self.downloads
            .get(self.selected_download)
            .map(|download| download.state.as_str())
    }

    pub fn next_download(&mut self) {
        advance_index(&mut self.selected_download, self.downloads.len());
    }

    pub fn previous_download(&mut self) {
        retreat_index(&mut self.selected_download);
    }

    pub fn jump_download_top(&mut self) {
        self.selected_download = 0;
    }

    pub fn jump_download_bottom(&mut self) {
        self.selected_download = self.downloads.len().saturating_sub(1);
    }
}

fn advance_index(index: &mut usize, len: usize) {
    if len > 0 {
        *index = (*index + 1).min(len - 1);
    }
}

fn retreat_index(index: &mut usize) {
    *index = index.saturating_sub(1);
}
