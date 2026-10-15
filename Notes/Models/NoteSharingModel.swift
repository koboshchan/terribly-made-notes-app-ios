import Foundation
import Observation

@MainActor
@Observable
final class NoteSharingModel {
    private(set) var info: NoteShareInfo?
    private(set) var isWorking = false
    private(set) var hasLoaded = false
    private(set) var errorMessage: String?
    var statusMessage: String?

    private let fetch: () async throws -> NoteShareInfo
    private let create: () async throws -> NoteShareInfo
    private let remove: () async throws -> Void

    init(fetch: @escaping () async throws -> NoteShareInfo,
         create: @escaping () async throws -> NoteShareInfo,
         remove: @escaping () async throws -> Void) {
        self.fetch = fetch
        self.create = create
        self.remove = remove
    }

    convenience init(noteId: String) {
        self.init(fetch: { try await APIClient.fetchShare(id: noteId) },
                  create: { try await APIClient.createShare(id: noteId) },
                  remove: { try await APIClient.deleteShare(id: noteId) })
    }

    func load() async {
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        info = nil
        hasLoaded = false
        errorMessage = nil
        statusMessage = nil
        do {
            info = try await fetch()
            hasLoaded = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func enable() async {
        guard hasLoaded, !isWorking, info?.activeURL == nil else { return }
        await mutate {
            let created = try await self.create()
            guard created.activeURL != nil else { throw APIError.invalidResponse }
            self.info = created
            self.statusMessage = "Public link created."
        }
    }

    func disable() async {
        guard hasLoaded, !isWorking, info?.activeURL != nil else { return }
        await mutate {
            try await self.remove()
            self.info = nil
            self.statusMessage = "Public link disabled. Your note is still here."
        }
    }

    private func mutate(_ action: () async throws -> Void) async {
        isWorking = true
        defer { isWorking = false }
        errorMessage = nil
        statusMessage = nil
        do { try await action() }
        catch {
            // A lost response can hide a successful write. Never keep offering a stale link.
            info = nil
            hasLoaded = false
            errorMessage = error.localizedDescription
        }
    }
}
