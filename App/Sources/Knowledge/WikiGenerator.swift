import Foundation

// MARK: - Wiki generator

/// Orchestrates the compile pipeline that turns a topic + RAG hits into
/// a verified, citation-grounded `WikiPage`.
///
/// Pipeline:
///   1. Gather candidate sources via `RAGSearchProtocol`.
///   2. Compose the appropriate prompt (topic / person / show / audit).
///   3. Call `WikiOpenRouterClient.compile` (live or stubbed).
///   4. Parse the JSON response into a draft page.
///   5. Run `WikiVerifier` to drop unverified claims.
///   6. Persist via `WikiStorage` (optional — caller decides).
///
/// `WikiGenerator` is `Sendable` and stateless; instances are cheap.
struct WikiGenerator: Sendable {

    let rag: any RAGSearchProtocol
    let client: WikiOpenRouterClient
    let storage: WikiStorage
    let model: String

    init(
        rag: any RAGSearchProtocol,
        client: WikiOpenRouterClient,
        storage: WikiStorage,
        model: String = "openai/gpt-4o-mini"
    ) {
        self.rag = rag
        self.client = client
        self.storage = storage
        self.model = model
    }

    // MARK: - Public

    /// Compiles a topic page about `topic` in the given `scope` and
    /// returns the verified result. Does **not** persist — callers
    /// invoke `persist` once they decide to keep it.
    func compileTopic(
        topic: String,
        scope: WikiScope,
        sourceLimit: Int = 12
    ) async throws -> WikiVerifyResult {
        let chunks = try await rag.search(
            query: topic,
            scope: scope,
            limit: sourceLimit
        )
        let prompt = WikiPrompts.topic(topic: topic, scope: scope, chunks: chunks)
        return try await compile(
            slug: WikiPage.normalize(slug: topic),
            kind: .topic,
            scope: scope,
            userPrompt: prompt
        )
    }

    /// Compiles a person page. See `compileTopic` for behaviour.
    func compilePerson(
        name: String,
        scope: WikiScope,
        sourceLimit: Int = 12
    ) async throws -> WikiVerifyResult {
        let chunks = try await rag.search(
            query: name,
            scope: scope,
            limit: sourceLimit
        )
        let prompt = WikiPrompts.person(name: name, scope: scope, chunks: chunks)
        return try await compile(
            slug: WikiPage.normalize(slug: name),
            kind: .person,
            scope: scope,
            userPrompt: prompt
        )
    }

    /// Compiles a show summary page. See `compileTopic` for behaviour.
    func compileShow(
        showName: String,
        scope: WikiScope,
        sourceLimit: Int = 24
    ) async throws -> WikiVerifyResult {
        let chunks = try await rag.search(
            query: showName,
            scope: scope,
            limit: sourceLimit
        )
        let prompt = WikiPrompts.show(showName: showName, scope: scope, chunks: chunks)
        return try await compile(
            slug: WikiPage.normalize(slug: showName),
            kind: .show,
            scope: scope,
            userPrompt: prompt
        )
    }

    /// Audits an existing page against fresh evidence and returns a
    /// re-verified replacement. The caller is responsible for the
    /// atomic swap on disk.
    func audit(prior: WikiPage, sourceLimit: Int = 16) async throws -> WikiVerifyResult {
        let chunks = try await rag.search(
            query: prior.title,
            scope: prior.scope,
            limit: sourceLimit
        )
        let prompt = WikiPrompts.audit(prior: prior, chunks: chunks)
        return try await compile(
            slug: prior.slug,
            kind: prior.kind,
            scope: prior.scope,
            userPrompt: prompt,
            compileRevision: prior.compileRevision + 1
        )
    }

    /// Persists `page` via the configured `WikiStorage`. Bumps the
    /// page's `compileRevision` only if the caller hasn't already.
    func persist(_ page: WikiPage) throws {
        try storage.write(page)
    }

    // MARK: - Private

    private func compile(
        slug: String,
        kind: WikiPageKind,
        scope: WikiScope,
        userPrompt: String,
        compileRevision: Int = 1
    ) async throws -> WikiVerifyResult {
        let json = try await client.compile(
            systemPrompt: WikiPrompts.system,
            userPrompt: userPrompt
        )
        var draft = try WikiResponseParser.parse(
            json: json,
            slug: slug,
            scope: scope,
            kind: kind,
            model: model
        )
        draft.compileRevision = compileRevision

        let verifier = WikiVerifier(rag: rag)
        return try await verifier.verify(draft)
    }
}
