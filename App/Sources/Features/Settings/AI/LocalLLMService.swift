import Foundation
import LiteRTLM
import os.log

actor LocalLLMService {
    private var engine: Engine?

    private var cacheDir: URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return caches.appendingPathComponent("LiteRTCache", isDirectory: true)
    }

    init() {
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
    }

    func load(spec: LocalModelSpec, downloadManager: LocalModelDownloadManager) async throws {
        guard let fileURL = downloadManager.modelFileURL(for: spec.id) as URL? else {
            throw LocalLLMError.modelNotFound
        }

        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw LocalLLMError.modelFileNotFound
        }

        let config = try EngineConfig(
            modelPath: fileURL.path,
            backend: .gpu,
            cacheDir: cacheDir.path
        )
        let newEngine = Engine(engineConfig: config)
        try newEngine.initialize()
        engine = newEngine
        os_log("Local LLM engine initialized with model: %{public}@", log: .default, type: .info, fileURL.path)
    }

    func unload() async {
        engine = nil
    }

    func infer(promptJSON: String) async -> String {
        guard let engine = engine else {
            return #"{"error":"Local model not loaded"}"#
        }

        // Extract the prompt text from the JSON payload sent by the Rust kernel.
        // Expected shape: {"prompt": "..."} or {"messages": [...]}
        var promptText = promptJSON
        if let data = promptJSON.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let p = obj["prompt"] as? String {
                promptText = p
            } else if let messages = obj["messages"] as? [[String: Any]],
                      let last = messages.last,
                      let content = last["content"] as? String {
                promptText = content
            }
        }

        do {
            let conversation = try engine.createConversation()
            let userMessage = Message(contents: [.text(promptText)], role: .user)
            let response = try await conversation.sendMessage(userMessage)

            // Extract text from the response message
            let responseText = response.contents.compactMap { content -> String? in
                if case .text(let t) = content { return t }
                return nil
            }.joined()

            guard let jsonData = try? JSONSerialization.data(
                withJSONObject: ["text": responseText]),
                  let jsonStr = String(data: jsonData, encoding: .utf8) else {
                return #"{"text":""}"#
            }
            return jsonStr
        } catch {
            os_log("Local LLM inference error: %{public}@", log: .default, type: .error,
                   error.localizedDescription)
            let msg = error.localizedDescription.replacingOccurrences(of: "\"", with: "'")
            return "{\"error\":\"\(msg)\"}"
        }
    }

    func registerWithKernel(_ kernel: KernelModel) async {
        guard let handle = kernel.podcastHandlePointer else {
            os_log("Cannot register local LLM: no kernel handle", log: .default, type: .error)
            return
        }

        let ctx = Unmanaged.passUnretained(self).toOpaque()
        nmp_app_register_local_llm(handle, ctx, localLLMCallback)
        os_log("Local LLM service registered with kernel", log: .default, type: .debug)
    }

    func clearFromKernel(_ kernel: KernelModel) {
        guard let handle = kernel.podcastHandlePointer else { return }
        nmp_app_clear_local_llm(handle)
        os_log("Local LLM service cleared from kernel", log: .default, type: .debug)
    }
}

// MARK: - C Callback Glue

private func localLLMCallback(
    _ context: UnsafeMutableRawPointer?,
    _ promptJSON: UnsafePointer<CChar>?
) -> UnsafeMutablePointer<CChar>? {
    guard let context = context else { return nil }
    guard let promptJSON = promptJSON else { return nil }

    let service = Unmanaged<LocalLLMService>.fromOpaque(context).takeUnretainedValue()
    let promptString = String(cString: promptJSON)

    // The FFI call runs on a Rust background thread (not the cooperative pool),
    // so blocking with a semaphore here is safe.
    let semaphore = DispatchSemaphore(value: 0)
    var result: String = #"{"error":"Inference failed"}"#

    let task = Task {
        result = await service.infer(promptJSON: promptString)
        semaphore.signal()
    }

    semaphore.wait()
    task.cancel()

    guard let resultCString = result.cString(using: .utf8) else {
        return nil
    }

    return strdup(resultCString)
}

// MARK: - Error Types

enum LocalLLMError: Error {
    case modelNotFound
    case modelFileNotFound
    case engineInitializationFailed
}
