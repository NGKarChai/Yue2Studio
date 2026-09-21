import Foundation

public struct DownloadProgress: Identifiable, Sendable {
    public let id: String
    public let modelName: String
    public var currentFileName: String
    public var currentFileIndex: Int
    public var totalFiles: Int
    public var bytesDownloaded: Int64
    public var totalBytes: Int64
    public var progressFraction: Double
    public var speedString: String
    public var status: String

    public var progressPercentString: String {
        return String(format: "%.1f%%", progressFraction * 100.0)
    }
}

public struct StageManifest: Sendable {
    public let repoId: String
    public let files: [String]
    public let totalEstimatedSize: String
}

@Observable
public final class ModelDownloadManager: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    public private(set) var activeDownloads: [String: DownloadProgress] = [:]
    public var onStageCompleted: (@Sendable (String) -> Void)?
    public var onProgressUpdated: (@Sendable () -> Void)?

    private var session: URLSession!
    private var activeTasks: [Int: (modelId: String, fileIndex: Int, destURL: URL, startTime: Date)] = [:]
    private var pendingQueues: [String: (modelName: String, repoId: String, destDir: URL, files: [String], currentIndex: Int)] = [:]

    public static let stageManifests: [String: StageManifest] = [
        "yue2-3b": StageManifest(
            repoId: "vanch007/mlx-Yue2-3B",
            files: [
                "config.json",
                "qwen.tiktoken",
                "ar-8bit.safetensors",
                "nar-bf16.safetensors"
            ],
            totalEstimatedSize: "~5.2 GB"
        ),
        "yue2-vae": StageManifest(
            repoId: "m-a-p/YuE2-Vae",
            files: [
                "config.json",
                "model.safetensors"
            ],
            totalEstimatedSize: "~506 MB"
        )
    ]

    public override init() {
        super.init()
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForResource = 86400
        self.session = URLSession(configuration: config, delegate: self, delegateQueue: OperationQueue.main)
    }

    /// Download all actual weight and config files for a pipeline stage
    public func downloadStage(
        id: String,
        name: String,
        to destinationDirectory: URL
    ) {
        guard let manifest = Self.stageManifests[id] else {
            print("[ModelDownloadManager] No manifest found for stage \(id)")
            return
        }

        if !FileManager.default.fileExists(atPath: destinationDirectory.path) {
            try? FileManager.default.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)
        }

        pendingQueues[id] = (
            modelName: name,
            repoId: manifest.repoId,
            destDir: destinationDirectory,
            files: manifest.files,
            currentIndex: 0
        )

        activeDownloads[id] = DownloadProgress(
            id: id,
            modelName: name,
            currentFileName: manifest.files.first ?? "",
            currentFileIndex: 1,
            totalFiles: manifest.files.count,
            bytesDownloaded: 0,
            totalBytes: 0,
            progressFraction: 0.0,
            speedString: "",
            status: "Initiating download (1/\(manifest.files.count))..."
        )
        onProgressUpdated?()

        downloadNextFile(for: id)
    }

    private func downloadNextFile(for id: String) {
        guard let queue = pendingQueues[id] else { return }

        if queue.currentIndex >= queue.files.count {
            pendingQueues.removeValue(forKey: id)
            activeDownloads[id] = DownloadProgress(
                id: id,
                modelName: queue.modelName,
                currentFileName: "Complete",
                currentFileIndex: queue.files.count,
                totalFiles: queue.files.count,
                bytesDownloaded: 1,
                totalBytes: 1,
                progressFraction: 1.0,
                speedString: "",
                status: "Weights Installed"
            )
            onProgressUpdated?()
            onStageCompleted?(id)
            return
        }

        let relPath = queue.files[queue.currentIndex]
        let dest = queue.destDir.appendingPathComponent(relPath)

        let encodedRelPath = relPath.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? relPath
        guard let url = URL(string: "https://huggingface.co/\(queue.repoId)/resolve/main/\(encodedRelPath)") else {
            return
        }

        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Yue2Studio/1.0", forHTTPHeaderField: "User-Agent")

        let task = session.downloadTask(with: request)
        activeTasks[task.taskIdentifier] = (
            modelId: id,
            fileIndex: queue.currentIndex,
            destURL: dest,
            startTime: Date()
        )

        let filename = (relPath as NSString).lastPathComponent
        activeDownloads[id]?.currentFileName = filename
        activeDownloads[id]?.currentFileIndex = queue.currentIndex + 1
        activeDownloads[id]?.status = "Downloading \(filename) (\(queue.currentIndex + 1)/\(queue.files.count))..."

        onProgressUpdated?()
        task.resume()
    }

    public func cancelDownload(id: String) {
        pendingQueues.removeValue(forKey: id)
        activeDownloads.removeValue(forKey: id)

        let taskIdsToCancel = activeTasks.filter { $0.value.modelId == id }.map { $0.key }
        session.getAllTasks { allTasks in
            for t in allTasks where taskIdsToCancel.contains(t.taskIdentifier) {
                t.cancel()
            }
        }
        for tid in taskIdsToCancel {
            activeTasks.removeValue(forKey: tid)
        }
        onProgressUpdated?()
    }

    // MARK: - URLSessionDownloadDelegate

    public func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard let entry = activeTasks[downloadTask.taskIdentifier],
              var current = activeDownloads[entry.modelId] else { return }

        let elapsed = Date().timeIntervalSince(entry.startTime)
        let speedBps = elapsed > 0 ? Double(totalBytesWritten) / elapsed : 0.0
        let speedMBps = speedBps / 1_048_576.0

        let fraction = totalBytesExpectedToWrite > 0 ? Double(totalBytesWritten) / Double(totalBytesExpectedToWrite) : 0.0
        let overallFraction = (Double(entry.fileIndex) + fraction) / Double(max(current.totalFiles, 1))

        current.bytesDownloaded = totalBytesWritten
        current.totalBytes = totalBytesExpectedToWrite
        current.progressFraction = overallFraction
        current.speedString = String(format: "%.1f MB/s", speedMBps)

        let writtenMB = Double(totalBytesWritten) / 1_048_576.0
        let expectedMB = Double(totalBytesExpectedToWrite) / 1_048_576.0
        current.status = String(
            format: "File %d/%d: %.1f/%.1f MB (%.1f MB/s)",
            entry.fileIndex + 1,
            current.totalFiles,
            writtenMB,
            expectedMB,
            speedMBps
        )

        activeDownloads[entry.modelId] = current
        onProgressUpdated?()
    }

    public func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        guard let entry = activeTasks[downloadTask.taskIdentifier] else { return }
        activeTasks.removeValue(forKey: downloadTask.taskIdentifier)

        if let httpResponse = downloadTask.response as? HTTPURLResponse {
            if httpResponse.statusCode < 200 || httpResponse.statusCode >= 300 {
                print("[ModelDownloadManager] HTTP error \(httpResponse.statusCode) downloading \(entry.destURL.lastPathComponent)")
                activeDownloads[entry.modelId]?.status = "Download error: HTTP \(httpResponse.statusCode)"
                pendingQueues.removeValue(forKey: entry.modelId)
                onProgressUpdated?()
                return
            }
        }

        do {
            let parentDir = entry.destURL.deletingLastPathComponent()
            if !FileManager.default.fileExists(atPath: parentDir.path) {
                try FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)
            }
            if FileManager.default.fileExists(atPath: entry.destURL.path) {
                try FileManager.default.removeItem(at: entry.destURL)
            }
            try FileManager.default.moveItem(at: location, to: entry.destURL)
            print("[ModelDownloadManager] Saved file to \(entry.destURL.path)")
        } catch {
            print("[ModelDownloadManager] File move error: \(error)")
        }

        if var queue = pendingQueues[entry.modelId] {
            queue.currentIndex += 1
            pendingQueues[entry.modelId] = queue
            downloadNextFile(for: entry.modelId)
        }
        onProgressUpdated?()
    }

    public func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        guard let entry = activeTasks[task.taskIdentifier] else { return }
        activeTasks.removeValue(forKey: task.taskIdentifier)
        if let error = error {
            let nsErr = error as NSError
            if nsErr.code != NSURLErrorCancelled {
                activeDownloads[entry.modelId]?.status = "Download failed: \(error.localizedDescription)"
                pendingQueues.removeValue(forKey: entry.modelId)
                onProgressUpdated?()
            }
        }
    }
}
