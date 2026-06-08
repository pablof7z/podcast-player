use super::PodcastStore;

#[derive(Clone, Debug, Default, Eq, PartialEq)]
pub(crate) struct ProviderCredentialMetadata {
    source: String,
    byok_key_id: Option<String>,
    byok_key_label: Option<String>,
    connected_at: Option<i64>,
}

impl ProviderCredentialMetadata {
    pub(crate) fn new(
        source: String,
        byok_key_id: Option<String>,
        byok_key_label: Option<String>,
        connected_at: Option<i64>,
    ) -> Self {
        Self {
            source,
            byok_key_id,
            byok_key_label,
            connected_at,
        }
    }

    pub(crate) fn source(&self) -> &str {
        &self.source
    }

    pub(crate) fn byok_key_id(&self) -> Option<&str> {
        self.byok_key_id.as_deref()
    }

    pub(crate) fn byok_key_id_owned(&self) -> Option<String> {
        self.byok_key_id.clone()
    }

    pub(crate) fn byok_key_label(&self) -> Option<&str> {
        self.byok_key_label.as_deref()
    }

    pub(crate) fn byok_key_label_owned(&self) -> Option<String> {
        self.byok_key_label.clone()
    }

    pub(crate) fn connected_at(&self) -> Option<i64> {
        self.connected_at
    }

    pub(crate) fn set(
        &mut self,
        source: String,
        byok_key_id: Option<String>,
        byok_key_label: Option<String>,
        connected_at: Option<i64>,
    ) -> bool {
        if self.source == source
            && self.byok_key_id == byok_key_id
            && self.byok_key_label == byok_key_label
            && self.connected_at == connected_at
        {
            return false;
        }
        self.source = source;
        self.byok_key_id = byok_key_id;
        self.byok_key_label = byok_key_label;
        self.connected_at = connected_at;
        true
    }
}

impl PodcastStore {
    pub fn open_router_credential_source(&self) -> &str {
        self.open_router_credential.source()
    }

    pub fn open_router_byok_key_id(&self) -> Option<&str> {
        self.open_router_credential.byok_key_id()
    }

    pub fn open_router_byok_key_label(&self) -> Option<&str> {
        self.open_router_credential.byok_key_label()
    }

    pub fn open_router_connected_at(&self) -> Option<i64> {
        self.open_router_credential.connected_at()
    }

    pub fn set_open_router_credential(
        &mut self,
        source: String,
        key_id: Option<String>,
        key_label: Option<String>,
        connected_at: Option<i64>,
    ) {
        if self
            .open_router_credential
            .set(source, key_id, key_label, connected_at)
        {
            self.persist();
        }
    }

    pub fn ollama_credential_source(&self) -> &str {
        self.ollama_credential.source()
    }

    pub fn ollama_byok_key_id(&self) -> Option<&str> {
        self.ollama_credential.byok_key_id()
    }

    pub fn ollama_byok_key_label(&self) -> Option<&str> {
        self.ollama_credential.byok_key_label()
    }

    pub fn ollama_connected_at(&self) -> Option<i64> {
        self.ollama_credential.connected_at()
    }

    pub fn set_ollama_credential(
        &mut self,
        source: String,
        key_id: Option<String>,
        key_label: Option<String>,
        connected_at: Option<i64>,
    ) {
        if self
            .ollama_credential
            .set(source, key_id, key_label, connected_at)
        {
            self.persist();
        }
    }

    pub fn eleven_labs_credential_source(&self) -> &str {
        self.eleven_labs_credential.source()
    }

    pub fn eleven_labs_byok_key_id(&self) -> Option<&str> {
        self.eleven_labs_credential.byok_key_id()
    }

    pub fn eleven_labs_byok_key_label(&self) -> Option<&str> {
        self.eleven_labs_credential.byok_key_label()
    }

    pub fn eleven_labs_connected_at(&self) -> Option<i64> {
        self.eleven_labs_credential.connected_at()
    }

    pub fn set_eleven_labs_credential(
        &mut self,
        source: String,
        key_id: Option<String>,
        key_label: Option<String>,
        connected_at: Option<i64>,
    ) {
        if self
            .eleven_labs_credential
            .set(source, key_id, key_label, connected_at)
        {
            self.persist();
        }
    }

    pub fn assembly_ai_credential_source(&self) -> &str {
        self.assembly_ai_credential.source()
    }

    pub fn assembly_ai_byok_key_id(&self) -> Option<&str> {
        self.assembly_ai_credential.byok_key_id()
    }

    pub fn assembly_ai_byok_key_label(&self) -> Option<&str> {
        self.assembly_ai_credential.byok_key_label()
    }

    pub fn assembly_ai_connected_at(&self) -> Option<i64> {
        self.assembly_ai_credential.connected_at()
    }

    pub fn set_assembly_ai_credential(
        &mut self,
        source: String,
        key_id: Option<String>,
        key_label: Option<String>,
        connected_at: Option<i64>,
    ) {
        if self
            .assembly_ai_credential
            .set(source, key_id, key_label, connected_at)
        {
            self.persist();
        }
    }

    pub fn perplexity_credential_source(&self) -> &str {
        self.perplexity_credential.source()
    }

    pub fn perplexity_byok_key_id(&self) -> Option<&str> {
        self.perplexity_credential.byok_key_id()
    }

    pub fn perplexity_byok_key_label(&self) -> Option<&str> {
        self.perplexity_credential.byok_key_label()
    }

    pub fn perplexity_connected_at(&self) -> Option<i64> {
        self.perplexity_credential.connected_at()
    }

    pub fn set_perplexity_credential(
        &mut self,
        source: String,
        key_id: Option<String>,
        key_label: Option<String>,
        connected_at: Option<i64>,
    ) {
        if self
            .perplexity_credential
            .set(source, key_id, key_label, connected_at)
        {
            self.persist();
        }
    }
}
