import SwiftUI
import UniformTypeIdentifiers

/// Labs › Manage autocorrect rules, opened from Privacy: the rules you imported and the
/// replacements you blocked, each removable, with Import and Export.
struct AutocorrectRulesView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var imported: [AutocorrectRule] = []
    @State private var blocked: [AutocorrectBlock] = []
    @State private var opening = false
    @State private var exporting = SettingsSnapshotFixture.autocorrectRulesScreen == .export
    @State private var importing: [AutocorrectRulesFile.Row]?
    @State private var failure: String?

    var body: some View {
        NavigationStack {
            SettingsPageScaffold(title: "Autocorrect rules") {
                Text("Rules apply on this iPhone, only in their language. Blocked replacements are never made in any language.")
                    .font(.system(size: 13))
                    .foregroundStyle(HexTheme.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 16)

                SettingsSectionHeader(title: "Imported rules")
                SettingsCard {
                    if imported.isEmpty { placeholder(String(localized: "No imported rules")) }
                    ForEach(Array(imported.enumerated()), id: \.element.key) { n, rule in
                        if n > 0 { SettingsDivider() }
                        AutocorrectPairRow(
                            typed: rule.typed, correction: rule.correction,
                            detail: KeyboardLanguage(rawValue: rule.language)?.displayName ?? rule.language
                        ) {
                            AutocorrectRules().remove(rule)
                            reload()
                        }
                    }
                }

                SettingsSectionHeader(title: "Blocked replacements")
                SettingsCard {
                    if blocked.isEmpty { placeholder(String(localized: "No blocked replacements")) }
                    ForEach(Array(blocked.enumerated()), id: \.element.key) { n, block in
                        if n > 0 { SettingsDivider() }
                        AutocorrectPairRow(typed: block.typed, correction: block.correction, detail: nil) {
                            AutocorrectRules().unblock(block)
                            reload()
                        }
                    }
                }

                SettingsCard {
                    Button {
                        failure = nil
                        opening = true
                    } label: {
                        SettingsLinkLabel(title: String(localized: "Import CSV or JSON"), icon: "square.and.arrow.down")
                    }
                    .buttonStyle(.plain)
                    SettingsDivider()
                    Button {
                        exporting = true
                    } label: {
                        SettingsLinkLabel(title: String(localized: "Export corrections"), icon: "square.and.arrow.up")
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 8)

                if let failure {
                    Text(failure)
                        .font(.system(size: 13))
                        .foregroundStyle(HexTheme.danger)
                        .padding(.horizontal, 16)
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .navigationDestination(isPresented: $exporting) {
                AutocorrectRulesExportView()
            }
            .navigationDestination(isPresented: Binding(get: { importing != nil }, set: { if !$0 { importing = nil } })) {
                AutocorrectRulesImportView(rows: importing ?? []) { reload() }
            }
            .fileImporter(isPresented: $opening, allowedContentTypes: [.json, .commaSeparatedText, .plainText]) { result in
                open(result)
            }
        }
        .preferredColorScheme(.dark)
        .presentationBackground(HexTheme.bgDeep)
        .onAppear {
            reload()
            importing = SettingsSnapshotFixture.autocorrectRulesImportRows
        }
    }

    private func reload() {
        imported = AutocorrectRules().imported
        blocked = AutocorrectRules().blocked
    }

    private func open(_ result: Result<URL, Error>) {
        guard case .success(let url) = result else { return }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        guard size <= AutocorrectRulesFile.maxBytes, let data = try? Data(contentsOf: url) else {
            failure = size > AutocorrectRulesFile.maxBytes
                ? String(localized: "The file is larger than 256 KB.")
                : String(localized: "WormaBoard couldn’t read the file.")
            return
        }
        switch AutocorrectRulesFile.parse(data) {
        case .success(let rows): importing = rows
        case .failure(let error): failure = error.reason
        }
    }

    private func placeholder(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 15))
            .foregroundStyle(HexTheme.textMuted)
            .frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
            .padding(.horizontal, 16)
    }
}

/// "typed → correction" with an optional detail and a remove button.
struct AutocorrectPairRow: View {
    let typed: String
    let correction: String
    let detail: String?
    let remove: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            SettingsRowLabel(title: "\(typed) → \(correction)", detail: detail)
            Spacer(minLength: 8)
            Button(action: remove) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(HexTheme.textMuted)
                    .frame(width: 26, height: 26)
                    .background(HexTheme.layer02, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove \(typed) → \(correction)")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(minHeight: 50)
    }
}
