import SwiftUI

struct SettingsView: View {
    @State private var exportFormat: ExportFormat = .json
    @State private var isExporting = false
    @State private var exportURL: URL?
    @State private var showShareSheet = false
    @State private var errorMessage: String?

    private let api = APIClient.shared

    enum ExportFormat: String, CaseIterable {
        case json = "JSON"
        case csv  = "CSV"
    }

    var body: some View {
        NavigationStack {
            List {
                accountSection
                exportSection
                aboutSection
            }
            .navigationTitle("Settings")
            .sheet(isPresented: $showShareSheet) {
                if let url = exportURL {
                    ShareSheet(url: url)
                }
            }
            .overlay(alignment: .bottom) {
                if let msg = errorMessage {
                    Text(msg)
                        .font(.caption)
                        .padding(10)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                        .padding()
                }
            }
        }
    }

    // MARK: - Sections

    private var accountSection: some View {
        Section("App") {
            LabeledContent("Version", value: appVersion)
            LabeledContent("Build",   value: buildNumber)
        }
    }

    private var exportSection: some View {
        Section {
            Picker("Format", selection: $exportFormat) {
                ForEach(ExportFormat.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)

            Button {
                Task { await exportCollection() }
            } label: {
                if isExporting {
                    ProgressView().frame(maxWidth: .infinity)
                } else {
                    Label("Export Collection", systemImage: "square.and.arrow.up")
                }
            }
            .disabled(isExporting)
        } header: {
            Text("Export")
        } footer: {
            Text("Exports all records to a file you can save or share.")
                .font(.caption)
        }
    }

    private var aboutSection: some View {
        Section("Data Sources") {
            Link(destination: URL(string: "https://musicbrainz.org")!) {
                Label("MusicBrainz", systemImage: "music.note")
            }
            Link(destination: URL(string: "https://coverartarchive.org")!) {
                Label("Cover Art Archive", systemImage: "photo")
            }
        }
    }

    // MARK: - Export

    private func exportCollection() async {
        isExporting = true
        errorMessage = nil

        do {
            let records = try await api.fetchRecords()
            let fileURL = try buildExportFile(records)
            exportURL = fileURL
            showShareSheet = true
        } catch {
            errorMessage = "Export failed: \(error.localizedDescription)"
        }

        isExporting = false
    }

    private func buildExportFile(_ records: [Record]) throws -> URL {
        let content: String
        let filename: String

        switch exportFormat {
        case .json:
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(records)
            content  = String(data: data, encoding: .utf8) ?? "[]"
            filename = "vinyl-collection.json"

        case .csv:
            let header = "Title,Artist,Year,Genre,Condition,MBID,Date Added"
            let rows = records.map { r -> String in
                [
                    r.title,
                    r.artist,
                    r.year.map(String.init) ?? "",
                    r.genre      ?? "",
                    r.condition?.rawValue ?? "",
                    r.mbid       ?? "",
                    r.dateAdded.formatted(.iso8601),
                ]
                .map { field in
                    // RFC 4180: wrap in quotes, escape internal quotes by doubling
                    "\"\(field.replacingOccurrences(of: "\"", with: "\"\""))\""
                }
                .joined(separator: ",")
            }
            content  = ([header] + rows).joined(separator: "\n")
            filename = "vinyl-collection.csv"
        }

        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        try content.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    // MARK: - Helpers

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }
    private var buildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
    }
}

// MARK: - ShareSheet

struct ShareSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }
    func updateUIViewController(_: UIActivityViewController, context _: Context) {}
}
