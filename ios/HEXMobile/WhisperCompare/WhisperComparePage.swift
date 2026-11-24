import AVFoundation
import SwiftUI

/// WormaDev Experiments › Whisper vs Apple (Arabic): one recording, read by Whisper and by
/// Apple's Arabic model, side by side. Dictation itself stays on its usual engine.
@MainActor
@Observable
final class WhisperCompareModel {
    enum Phase: Equatable {
        case needsModel
        case preparing(Double?)
        case ready
        case recording
        case transcribing
        case failed(String)
    }

    struct Result: Identifiable {
        let id = UUID()
        let whisper: String
        let apple: String
    }

    var phase: Phase = WhisperArabic.downloadedFolder == nil ? .needsModel : .preparing(nil)
    var results: [Result] = []

    private let whisper = WhisperArabic()
    private var recorder: AVAudioRecorder?
    private let clip = URL.temporaryDirectory.appending(path: "whisper-compare.wav")

    func prepare() {
        phase = .preparing(WhisperArabic.downloadedFolder == nil ? 0 : nil)
        Task {
            do {
                try await whisper.prepare { fraction in
                    Task { @MainActor in self.phase = .preparing(fraction) }
                }
                phase = .ready
            } catch {
                phase = .failed(error.localizedDescription)
            }
        }
    }

    func toggleRecording() {
        if phase == .recording { finish() } else { record() }
    }

    func removeModel() {
        WhisperArabic.remove()
        phase = .needsModel
    }

    private func record() {
        do {
            let session = AVAudioSession.sharedInstance()
            if session.category != .playAndRecord {
                try session.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker])
            }
            try session.setActive(true)
            let settings: [String: Any] = [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: 16_000,
                AVNumberOfChannelsKey: 1,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false,
            ]
            let recorder = try AVAudioRecorder(url: clip, settings: settings)
            guard recorder.record() else { throw CocoaError(.fileWriteUnknown) }
            self.recorder = recorder
            phase = .recording
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    private func finish() {
        recorder?.stop()
        recorder = nil
        phase = .transcribing
        Task {
            async let heard = whisper.transcribe(clip)
            async let apple = Self.apple(clip)
            let whisperText = (try? await heard) ?? "—"
            results.insert(Result(whisper: whisperText.isEmpty ? "—" : whisperText, apple: await apple), at: 0)
            phase = .ready
        }
    }

    private static func apple(_ url: URL) async -> String {
        guard #available(iOS 26.0, *) else { return String(localized: "Needs iOS 26") }
        let transcriber = AppleSpeechTranscriber(
            language: SpeechLanguage(locale: Locale(identifier: "ar-SA"), module: .dictation)
        )
        do {
            try await transcriber.prepare { _ in }
            return try await transcriber.transcribe(url)
        } catch {
            return error.localizedDescription
        }
    }
}

struct WhisperComparePage: View {
    @State private var model = WhisperCompareModel()

    var body: some View {
        SettingsPageScaffold(title: "Whisper vs Apple") {
            SettingsCard {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Say something in Arabic. Whisper and Apple's Arabic model each write what they heard.")
                        .font(.system(size: 13))
                        .foregroundStyle(HexTheme.textMuted)
                    control
                }
                .padding(16)
            }
            ForEach(model.results) { result in
                SettingsCard {
                    VStack(alignment: .leading, spacing: 10) {
                        line("Whisper", result.whisper)
                        line("Apple", result.apple)
                    }
                    .padding(16)
                }
            }
            if model.phase != .needsModel, WhisperArabic.downloadedFolder != nil {
                Button("Delete Whisper model", role: .destructive) { model.removeModel() }
                    .font(.system(size: 13))
                    .padding(.top, 8)
            }
        }
        .onAppear {
            if case .preparing = model.phase { model.prepare() }
        }
    }

    @ViewBuilder
    private var control: some View {
        switch model.phase {
        case .needsModel:
            action(String(localized: "Download Whisper (632 MB)")) { model.prepare() }
        case let .preparing(fraction):
            if let fraction, fraction < 1 {
                ProgressView(value: fraction) { Text("Downloading Whisper") }
            } else {
                ProgressView { Text("Loading Whisper. The first time takes a minute or two.") }
            }
        case .ready, .recording:
            action(model.phase == .recording ? String(localized: "Stop") : String(localized: "Record")) {
                model.toggleRecording()
            }
        case .transcribing:
            ProgressView { Text("Transcribing") }
        case let .failed(message):
            Text(message).font(.system(size: 13)).foregroundStyle(HexTheme.danger)
            action(String(localized: "Try again")) { model.prepare() }
        }
    }

    private func action(_ title: String, _ run: @escaping () -> Void) -> some View {
        Button(action: run) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(HexTheme.textContrast)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(model.phase == .recording ? HexTheme.danger : HexTheme.bgContrast, in: .rect(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    private func line(_ engine: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(engine).font(.system(size: 12, weight: .medium)).foregroundStyle(HexTheme.textMuted)
            Text(text)
                .font(.system(size: 17))
                .foregroundStyle(HexTheme.textBase)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }
}

/// The row in WormaDev Experiments that opens the page.
struct WhisperCompareRow: View {
    @State private var showsPage = false

    var body: some View {
        Button { showsPage = true } label: {
            HStack(spacing: 12) {
                SettingsRowLabel(
                    title: String(localized: "Whisper vs Apple (Arabic)"),
                    detail: String(localized: "Record once and compare what each model writes. Dictation isn't changed.")
                )
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(HexTheme.textMuted)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(minHeight: 50)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .navigationDestination(isPresented: $showsPage) { WhisperComparePage() }
    }
}
