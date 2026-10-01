import Foundation

public struct UploadServerError: LocalizedError, Sendable {
    public let statusCode: Int
    public let message: String
    public var errorDescription: String? { message }
}

/// Runs uploads from staged files on a background URLSession so they continue
/// when the app or share extension is suspended. Progress and results are
/// written to UploadStore; callers may also await the result.
public final class BackgroundUploader: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    public static let appSessionID = "com.kobosh.notes.upload.app"
    public static let shareSessionID = "com.kobosh.notes.upload.share"

    private static let lock = NSLock()
    nonisolated(unsafe) private static var instances: [String: BackgroundUploader] = [:]

    /// One uploader per session identifier (a background session identifier
    /// must only be instantiated once per process).
    public static func shared(identifier: String) -> BackgroundUploader {
        lock.lock(); defer { lock.unlock() }
        if let existing = instances[identifier] { return existing }
        let uploader = BackgroundUploader(identifier: identifier)
        instances[identifier] = uploader
        return uploader
    }

    public let identifier: String
    private let stateLock = NSLock()
    private var responseData: [Int: Data] = [:]
    private var waiters: [String: CheckedContinuation<String, Error>] = [:]
    private var eventsCompletion: (() -> Void)?
    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.background(withIdentifier: identifier)
        config.sharedContainerIdentifier = UploadStore.appGroup
        config.sessionSendsLaunchEvents = true
        config.isDiscretionary = false
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()

    private init(identifier: String) {
        self.identifier = identifier
        super.init()
    }

    /// Ensures the session exists so pending delegate events get delivered.
    public func reconnect(eventsCompletion: (() -> Void)? = nil) {
        stateLock.lock(); self.eventsCompletion = eventsCompletion; stateLock.unlock()
        _ = session
    }

    // MARK: - Staging

    /// Streams the audio into a multipart body inside the app group container
    /// and records it as pending.
    public static func stage(audioFile: URL, displayName: String, fields: [String: String]) throws -> UploadRecord {
        let id = UUID().uuidString
        let boundary = "Boundary-\(id)"
        let bodyName = "\(id).multipart"
        let store = UploadStore.shared
        let didAccess = audioFile.startAccessingSecurityScopedResource()
        defer { if didAccess { audioFile.stopAccessingSecurityScopedResource() } }
        let size = try MultipartFileBuilder.build(
            audioFile: audioFile,
            fileName: displayName,
            fields: fields,
            boundary: boundary,
            destination: store.directory.appendingPathComponent(bodyName)
        )
        let record = UploadRecord(
            id: id, displayName: displayName, bodyPath: bodyName, boundary: boundary,
            fields: fields, status: .pending, noteId: nil, bytesSent: 0, totalBytes: size,
            error: nil, attempts: 0, createdAt: Date()
        )
        store.upsert(record)
        return record
    }

    // MARK: - Start

    /// Starts (or restarts) an upload and returns immediately.
    public func start(recordId: String, token: String, baseURL: URL) {
        guard let record = UploadStore.shared.record(id: recordId) else { return }
        // Don't create a second task for an upload already in flight.
        session.getAllTasks { [self] tasks in
            if tasks.contains(where: { $0.taskDescription == recordId && $0.state == .running }) { return }
            var request = URLRequest(url: baseURL.appendingPathComponent("/api/upload"))
            request.httpMethod = "POST"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("multipart/form-data; boundary=\(record.boundary)", forHTTPHeaderField: "Content-Type")
            request.setValue(record.id, forHTTPHeaderField: "Idempotency-Key")
            let task = session.uploadTask(with: request, fromFile: UploadStore.shared.bodyURL(for: record))
            task.taskDescription = record.id
            UploadStore.shared.update(id: record.id) {
                $0.status = .uploading
                $0.attempts += 1
                $0.error = nil
                $0.bytesSent = 0
            }
            task.resume()
        }
    }

    /// Starts an upload and waits for the server's note id.
    public func upload(recordId: String, token: String, baseURL: URL) async throws -> String {
        try await withCheckedThrowingContinuation { cont in
            stateLock.lock(); waiters[recordId] = cont; stateLock.unlock()
            start(recordId: recordId, token: token, baseURL: baseURL)
        }
    }

    // MARK: - URLSessionDataDelegate

    public func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64,
                           totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        guard let id = task.taskDescription else { return }
        UploadStore.shared.update(id: id) {
            $0.bytesSent = totalBytesSent
            if totalBytesExpectedToSend > 0 { $0.totalBytes = totalBytesExpectedToSend }
        }
    }

    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        stateLock.lock()
        responseData[dataTask.taskIdentifier, default: Data()].append(data)
        stateLock.unlock()
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let id = task.taskDescription else { return }
        stateLock.lock()
        let data = responseData.removeValue(forKey: task.taskIdentifier) ?? Data()
        let waiter = waiters.removeValue(forKey: id)
        stateLock.unlock()

        let status = (task.response as? HTTPURLResponse)?.statusCode ?? 0
        struct OK: Decodable { let noteId: String }
        struct Err: Decodable { let error: String? }

        if error == nil, (200..<300).contains(status), let ok = try? JSONDecoder().decode(OK.self, from: data) {
            UploadStore.shared.update(id: id) {
                $0.status = .completed
                $0.noteId = ok.noteId
                $0.bytesSent = $0.totalBytes
            }
            if let r = UploadStore.shared.record(id: id) {
                try? FileManager.default.removeItem(at: UploadStore.shared.bodyURL(for: r))
            }
            waiter?.resume(returning: ok.noteId)
            return
        }

        let failure: Error
        if let error {
            failure = error
            UploadStore.shared.update(id: id) { $0.status = .failed; $0.error = error.localizedDescription }
        } else if status == 401 {
            failure = UploadServerError(statusCode: 401, message: "Session expired. Open Notes to continue this upload.")
            UploadStore.shared.update(id: id) { $0.status = .needsAuth; $0.error = failure.localizedDescription }
        } else {
            let msg = (try? JSONDecoder().decode(Err.self, from: data))?.error ?? "Upload failed (HTTP \(status))"
            failure = UploadServerError(statusCode: status, message: msg)
            UploadStore.shared.update(id: id) { $0.status = .failed; $0.error = msg }
        }
        waiter?.resume(throwing: failure)
    }

    public func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        stateLock.lock(); let done = eventsCompletion; eventsCompletion = nil; stateLock.unlock()
        DispatchQueue.main.async { done?() }
    }
}
