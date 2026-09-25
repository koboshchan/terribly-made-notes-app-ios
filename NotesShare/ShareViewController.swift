import UIKit
import SwiftUI
import UniformTypeIdentifiers

@objc(ShareViewController)
public final class ShareViewController: UIViewController {

    override public func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        Task {
            let files = await extractSharedAudioFiles()
            await MainActor.run {
                self.presentUploadInterface(files: files)
            }
        }
    }

    private func presentUploadInterface(files: [SharedAudioFile]) {
        let uploadView = ShareUploadView(
            initialFiles: files,
            onComplete: { [weak self] in
                self?.extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
            },
            onCancel: { [weak self] in
                self?.extensionContext?.cancelRequest(withError: NSError(domain: "NotesShare", code: -1, userInfo: [NSLocalizedDescriptionKey: "User cancelled"]))
            }
        )

        let hostingController = UIHostingController(rootView: uploadView)
        addChild(hostingController)
        view.addSubview(hostingController.view)
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            hostingController.view.topAnchor.constraint(equalTo: view.topAnchor),
            hostingController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        hostingController.didMove(toParent: self)
    }

    private func extractSharedAudioFiles() async -> [SharedAudioFile] {
        guard let items = extensionContext?.inputItems as? [NSExtensionItem] else {
            return []
        }

        var files: [SharedAudioFile] = []
        let supportedTypes = [
            UTType.audio.identifier,
            "com.apple.m4a-audio",
            UTType.fileURL.identifier,
            "public.audio",
            "public.data"
        ]

        for item in items {
            guard let attachments = item.attachments else { continue }
            for provider in attachments {
                // Find matching type identifier
                guard let matchingType = supportedTypes.first(where: { provider.hasItemConformingToTypeIdentifier($0) }) else {
                    continue
                }

                if let localURL = await loadFile(from: provider, typeIdentifier: matchingType) {
                    let displayName = localURL.deletingPathExtension().lastPathComponent
                    let filename = "\(displayName).\(localURL.pathExtension.isEmpty ? "m4a" : localURL.pathExtension)"
                    files.append(SharedAudioFile(name: filename, url: localURL))
                }
            }
        }

        return files
    }

    private func loadFile(from provider: NSItemProvider, typeIdentifier: String) async -> URL? {
        await withCheckedContinuation { continuation in
            // First attempt loading file representation directly
            provider.loadFileRepresentation(forTypeIdentifier: typeIdentifier) { tempURL, _ in
                if let tempURL {
                    let destDir = FileManager.default.temporaryDirectory
                    let destURL = destDir.appendingPathComponent("\(UUID().uuidString)_\(tempURL.lastPathComponent)")
                    try? FileManager.default.removeItem(at: destURL)
                    do {
                        try FileManager.default.copyItem(at: tempURL, to: destURL)
                        continuation.resume(returning: destURL)
                        return
                    } catch {
                        // Fall back to item loading
                    }
                }

                // Fallback attempt: loadItem
                provider.loadItem(forTypeIdentifier: typeIdentifier, options: nil) { item, _ in
                    if let url = item as? URL {
                        let destDir = FileManager.default.temporaryDirectory
                        let destURL = destDir.appendingPathComponent("\(UUID().uuidString)_\(url.lastPathComponent)")
                        try? FileManager.default.removeItem(at: destURL)
                        do {
                            try FileManager.default.copyItem(at: url, to: destURL)
                            continuation.resume(returning: destURL)
                            return
                        } catch {
                            continuation.resume(returning: url)
                            return
                        }
                    } else if let data = item as? Data {
                        let destURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).m4a")
                        try? data.write(to: destURL)
                        continuation.resume(returning: destURL)
                        return
                    }
                    continuation.resume(returning: nil)
                }
            }
        }
    }
}
