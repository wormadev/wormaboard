import Foundation
import WhisperKit

/// WormaDev Experiments › Whisper vs Apple (Arabic): OpenAI's Whisper large-v3 turbo through
/// WhisperKit, in WormaBoard's own process. Apple's only Arabic model (ar-SA) writes Gulf
/// forms as Saudi ones (شلونچ as شلونك); Whisper writes what it hears.
actor WhisperArabic {
    static let variant = "openai_whisper-large-v3-v20240930_turbo_632MB"
    private static let folderKey = "experiments.whisperArabic.modelFolder"

    private var pipe: WhisperKit?

    /// The downloaded model's folder, nil until a download finished.
    nonisolated static var downloadedFolder: URL? {
        guard let path = UserDefaults.standard.string(forKey: folderKey),
              FileManager.default.fileExists(atPath: path) else { return nil }
        return URL(fileURLWithPath: path)
    }

    private static var downloadBase: URL {
        URL.applicationSupportDirectory.appending(path: "whisper", directoryHint: .isDirectory)
    }

    func prepare(progress: @escaping @Sendable (Double) -> Void) async throws {
        guard pipe == nil else { return }
        let folder: URL
        if let downloaded = Self.downloadedFolder {
            folder = downloaded
        } else {
            folder = try await WhisperKit.download(
                variant: Self.variant,
                downloadBase: Self.downloadBase,
                progressCallback: { progress($0.fractionCompleted) }
            )
            UserDefaults.standard.set(folder.path, forKey: Self.folderKey)
        }
        pipe = try await WhisperKit(
            WhisperKitConfig(modelFolder: folder.path, verbose: false, logLevel: .error, prewarm: true, load: true, download: false)
        )
    }

    func transcribe(_ url: URL) async throws -> String {
        guard let pipe else { throw CocoaError(.featureUnsupported) }
        let options = DecodingOptions(task: .transcribe, language: "ar", detectLanguage: false, skipSpecialTokens: true, withoutTimestamps: true)
        let results = try await pipe.transcribe(audioPath: url.path, decodeOptions: options)
        return results.map(\.text).joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Deletes the download and forgets it.
    static func remove() {
        try? FileManager.default.removeItem(at: downloadBase)
        UserDefaults.standard.removeObject(forKey: folderKey)
    }
}
