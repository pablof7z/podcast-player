import Foundation
import os.log

enum LocalModelState: Equatable, Sendable {
    case notDownloaded
    case downloading(progress: Double)
    case downloaded
    case active
}

@MainActor
@Observable
final class LocalModelDownloadManager: NSObject, URLSessionDownloadDelegate {
    private(set) var states: [String: LocalModelState] = [:]
    private var session: URLSession?
    private var activeDownloads: [String: URL] = [:]
    private let fileManager = FileManager.default
    private let modelsDirectoryURL: URL

    override init() {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        modelsDirectoryURL = appSupport.appendingPathComponent("LocalModels", isDirectory: true)
        super.init()

        do {
            try fileManager.createDirectory(at: modelsDirectoryURL, withIntermediateDirectories: true)
        } catch {
            os_log("Failed to create LocalModels directory: %{public}@", log: .default, type: .error, error.localizedDescription)
        }

        let config = URLSessionConfiguration.background(withIdentifier: "com.podcastr.local-model-downloads")
        config.sessionSendsLaunchEvents = true
        self.session = URLSession(configuration: config, delegate: self, delegateQueue: OperationQueue.main)

        recomputeStatesFromDisk(activeModelID: nil)
    }

    func recomputeStatesFromDisk(activeModelID: String?) {
        var newStates: [String: LocalModelState] = [:]

        for spec in LocalModelCatalog.all {
            let fileURL = modelFileURL(for: spec.id)
            let fileExists = fileManager.fileExists(atPath: fileURL.path)

            if activeModelID == spec.id && fileExists {
                newStates[spec.id] = .active
            } else if fileExists {
                newStates[spec.id] = .downloaded
            } else {
                newStates[spec.id] = .notDownloaded
            }
        }

        states = newStates
    }

    func modelFileURL(for modelID: String) -> URL {
        modelsDirectoryURL.appendingPathComponent("\(modelID).litertlm")
    }

    func download(spec: LocalModelSpec) {
        guard let session = session else { return }

        states[spec.id] = .downloading(progress: 0.0)

        var request = URLRequest(url: spec.downloadURL)
        request.timeoutInterval = 3600 // 1 hour timeout

        let downloadTask = session.downloadTask(with: request)
        activeDownloads[spec.id] = modelFileURL(for: spec.id)
        downloadTask.resume()
    }

    func cancel(_ modelID: String) {
        guard let session = session else { return }
        if let spec = LocalModelCatalog.all.first(where: { $0.id == modelID }) {
            session.getTasksWithCompletionHandler { dataTasks, uploadTasks, downloadTasks in
                downloadTasks.forEach { task in
                    if let url = task.originalRequest?.url, url == spec.downloadURL {
                        task.cancel()
                    }
                }
            }
        }
        states[modelID] = .notDownloaded
        activeDownloads.removeValue(forKey: modelID)
    }

    func delete(_ modelID: String) {
        let fileURL = modelFileURL(for: modelID)
        try? fileManager.removeItem(at: fileURL)
        states[modelID] = .notDownloaded
        activeDownloads.removeValue(forKey: modelID)
    }

    func state(for modelID: String) -> LocalModelState {
        return states[modelID] ?? .notDownloaded
    }

    // MARK: - URLSessionDownloadDelegate

    nonisolated func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo temporaryURL: URL
    ) {
        guard let originalURL = downloadTask.originalRequest?.url else { return }

        MainActor.assumeIsolated {
            let modelID = activeDownloads.first(where: { $0.value.lastPathComponent.dropLast(9) == URL(fileURLWithPath: originalURL.lastPathComponent).lastPathComponent.dropLast(9) })?.key
            guard let modelID = modelID else { return }

            let destinationURL = activeDownloads[modelID] ?? modelFileURL(for: modelID)

            do {
                try fileManager.removeItem(at: destinationURL)
            } catch {
                // File might not exist yet
            }

            do {
                try fileManager.moveItem(at: temporaryURL, to: destinationURL)
                states[modelID] = .downloaded
                activeDownloads.removeValue(forKey: modelID)
            } catch {
                os_log("Failed to move downloaded model: %{public}@", log: .default, type: .error, error.localizedDescription)
                states[modelID] = .notDownloaded
            }
        }
    }

    nonisolated func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard let originalURL = downloadTask.originalRequest?.url,
              let modelID = LocalModelCatalog.all.first(where: { $0.downloadURL == originalURL })?.id else { return }

        let progress = totalBytesExpectedToWrite > 0 ? Double(totalBytesWritten) / Double(totalBytesExpectedToWrite) : 0.0
        MainActor.assumeIsolated {
            states[modelID] = .downloading(progress: progress)
        }
    }

    nonisolated func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        guard let originalURL = task.originalRequest?.url,
              let modelID = LocalModelCatalog.all.first(where: { $0.downloadURL == originalURL })?.id else { return }

        MainActor.assumeIsolated {
            if let error = error {
                os_log("Download failed for model %{public}@: %{public}@", log: .default, type: .error, modelID, error.localizedDescription)
                states[modelID] = .notDownloaded
            }
            activeDownloads.removeValue(forKey: modelID)
        }
    }
}
