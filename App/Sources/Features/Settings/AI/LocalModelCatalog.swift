import Foundation

struct LocalModelSpec: Identifiable, Hashable, Sendable {
    let id: String
    let displayName: String
    let description: String
    let sizeBytes: Int64
    let downloadURL: URL
    let minDeviceRAMGB: Int
}

enum LocalModelCatalog {
    static let all: [LocalModelSpec] = [
        LocalModelSpec(
            id: "gemma4-e2b",
            displayName: "Gemma 4 E2B",
            description: "Lightweight efficient LLM for on-device inference",
            sizeBytes: 2_590_000_000,
            downloadURL: URL(string: "https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm/resolve/3f25054/gemma-4-E2B-it.litertlm")!,
            minDeviceRAMGB: 4
        ),
        LocalModelSpec(
            id: "gemma4-e4b",
            displayName: "Gemma 4 E4B",
            description: "Larger efficient LLM variant for improved quality",
            sizeBytes: 3_800_000_000,
            downloadURL: URL(string: "https://huggingface.co/litert-community/gemma-4-E4B-it-litert-lm/resolve/f7ad3343bd6ebc9607f4dc3bc4f2398bd5749bc5/gemma-4-E4B-it.litertlm")!,
            minDeviceRAMGB: 6
        ),
    ]

    /// Resolves the catalog model a finished/in-flight download task belongs to.
    /// This is the canonical task→model match used by every
    /// `URLSessionDownloadDelegate` callback. It must compare the full download
    /// URL: the remote filename (`gemma-4-E2B-it`) equals neither the model id
    /// (`gemma4-e2b`) nor the on-disk filename, so a basename comparison can
    /// never match and silently drops the finished download.
    static func modelID(forDownloadURL url: URL) -> String? {
        all.first(where: { $0.downloadURL == url })?.id
    }
}
