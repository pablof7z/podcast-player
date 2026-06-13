use crate::app::AppState;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum AgentSection {
    Chat,
    Picks,
    Tasks,
    Notes,
    Memory,
}

impl AgentSection {
    pub fn all() -> &'static [Self] {
        &[
            Self::Chat,
            Self::Picks,
            Self::Tasks,
            Self::Notes,
            Self::Memory,
        ]
    }

    pub fn label(self) -> &'static str {
        match self {
            Self::Chat => "chat",
            Self::Picks => "picks",
            Self::Tasks => "tasks",
            Self::Notes => "notes",
            Self::Memory => "memory",
        }
    }

    fn next(self) -> Self {
        let sections = Self::all();
        let index = sections
            .iter()
            .position(|section| *section == self)
            .unwrap_or(0);
        sections[(index + 1) % sections.len()]
    }

    fn previous(self) -> Self {
        let sections = Self::all();
        let index = sections
            .iter()
            .position(|section| *section == self)
            .unwrap_or(0);
        sections[(index + sections.len() - 1) % sections.len()]
    }
}

impl AppState {
    pub fn next_agent_section(&mut self) {
        self.agent_section = self.agent_section.next();
    }

    pub fn previous_agent_section(&mut self) {
        self.agent_section = self.agent_section.previous();
    }

    pub fn selected_agent_pick_episode_id(&self) -> Option<String> {
        self.agent_picks
            .get(self.selected_agent_pick)
            .map(|pick| pick.episode_id.clone())
    }

    pub fn selected_agent_task_id(&self) -> Option<String> {
        self.agent_tasks
            .get(self.selected_agent_task)
            .map(|task| task.id.clone())
    }

    pub fn selected_agent_task_enabled(&self) -> Option<bool> {
        self.agent_tasks
            .get(self.selected_agent_task)
            .map(|task| task.is_enabled)
    }

    pub fn selected_memory_key(&self) -> Option<String> {
        self.memory_facts
            .get(self.selected_memory_fact)
            .map(|fact| fact.key.clone())
    }

    pub fn next_agent_row(&mut self) {
        match self.agent_section {
            AgentSection::Chat => {}
            AgentSection::Picks => {
                advance_index(&mut self.selected_agent_pick, self.agent_picks.len())
            }
            AgentSection::Tasks => {
                advance_index(&mut self.selected_agent_task, self.agent_tasks.len())
            }
            AgentSection::Notes => {
                advance_index(&mut self.selected_agent_note, self.nostr_conversations.len())
            }
            AgentSection::Memory => {
                advance_index(&mut self.selected_memory_fact, self.memory_facts.len())
            }
        }
    }

    pub fn previous_agent_row(&mut self) {
        match self.agent_section {
            AgentSection::Chat => {}
            AgentSection::Picks => retreat_index(&mut self.selected_agent_pick),
            AgentSection::Tasks => retreat_index(&mut self.selected_agent_task),
            AgentSection::Notes => retreat_index(&mut self.selected_agent_note),
            AgentSection::Memory => retreat_index(&mut self.selected_memory_fact),
        }
    }

    pub fn jump_agent_top(&mut self) {
        match self.agent_section {
            AgentSection::Chat => {}
            AgentSection::Picks => self.selected_agent_pick = 0,
            AgentSection::Tasks => self.selected_agent_task = 0,
            AgentSection::Notes => self.selected_agent_note = 0,
            AgentSection::Memory => self.selected_memory_fact = 0,
        }
    }

    pub fn jump_agent_bottom(&mut self) {
        match self.agent_section {
            AgentSection::Chat => {}
            AgentSection::Picks => {
                self.selected_agent_pick = self.agent_picks.len().saturating_sub(1)
            }
            AgentSection::Tasks => {
                self.selected_agent_task = self.agent_tasks.len().saturating_sub(1)
            }
            AgentSection::Notes => {
                self.selected_agent_note = self.nostr_conversations.len().saturating_sub(1)
            }
            AgentSection::Memory => {
                self.selected_memory_fact = self.memory_facts.len().saturating_sub(1)
            }
        }
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
