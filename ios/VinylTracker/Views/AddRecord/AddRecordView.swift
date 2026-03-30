import SwiftUI
import UIKit

// MARK: - ViewModel

@MainActor
final class AddRecordViewModel: ObservableObject {

    // Form fields — user can edit any of these at any point
    @Published var title     = ""
    @Published var artist    = ""
    @Published var year      = ""
    @Published var genre     = ""
    @Published var notes     = ""
    @Published var condition: RecordCondition?

    // Enrichment state
    @Published var mbid:        String?
    @Published var coverArtUrl: String?

    // Captured photo (stays on-device until after record is saved)
    @Published var capturedImage: UIImage?

    // Status
    @Published var phase: Phase = .idle
    @Published var ocrLines: [String] = []
    @Published var errorMessage: String?
    @Published var savedRecord: Record?

    enum Phase: Equatable {
        case idle
        case runningOCR
        case lookingUp
        case saving
    }

    private let ocrService = VisionOCRService()
    private let parser     = RecordTextParser()
    private let api        = APIClient.shared

    var canSave: Bool {
        phase == .idle &&
        !title.trimmingCharacters(in: .whitespaces).isEmpty &&
        !artist.trimmingCharacters(in: .whitespaces).isEmpty
    }

    // MARK: - Full OCR → Lookup pipeline

    /// Called as soon as a photo is captured. Runs entirely on-device first,
    /// then fires a lookup request with the extracted text.
    func handleCapturedImage(_ image: UIImage) async {
        phase = .runningOCR
        errorMessage = nil

        do {
            // ── Step 1: On-device OCR (no network) ──────────────────────────
            let ocrResult = try await ocrService.recognizeText(in: image)
            ocrLines = ocrResult.rawLines

            // ── Step 2: Text parsing / heuristics ───────────────────────────
            let parsed = parser.parse(ocrResult)

            // Pre-fill only empty fields — don't overwrite manual user input
            if artist.isEmpty, let a = parsed.artist { artist = a }
            if title.isEmpty,  let t = parsed.title  { title  = t }
            if year.isEmpty,   let y = parsed.year   { year   = String(y) }

            phase = .idle  // OCR done; form is live for editing

            // ── Step 3: MusicBrainz lookup with extracted text ────────────────
            // Only fire if we have something useful
            if !artist.isEmpty || !title.isEmpty {
                await performLookup()
            }
        } catch {
            errorMessage = "OCR failed: \(error.localizedDescription)"
            phase = .idle
        }
    }

    func performLookup() async {
        guard phase == .idle else { return }
        phase = .lookingUp
        errorMessage = nil

        do {
            let result = try await api.lookup(
                artist: artist.isEmpty ? nil : artist,
                title:  title.isEmpty  ? nil : title
            )
            applyLookupResult(result)
        } catch APIError.networkError {
            // Offline or server unreachable — non-fatal, user fills in manually
            errorMessage = "Metadata lookup unavailable — fill in manually."
        } catch {
            errorMessage = "Lookup: \(error.localizedDescription)"
        }

        phase = .idle
    }

    /// Merge server result into form, respecting existing manual edits.
    private func applyLookupResult(_ result: LookupResult) {
        // Only fill a field if the user hasn't already typed something different
        if let t = result.title,  title.isEmpty  { title  = t }
        if let a = result.artist, artist.isEmpty  { artist = a }
        if let y = result.year,   year.isEmpty   { year   = String(y) }
        if let g = result.genre,  genre.isEmpty  { genre  = g }
        mbid        = result.mbid
        coverArtUrl = result.coverArtUrl
    }

    // MARK: - Save

    func save() async {
        phase = .saving
        errorMessage = nil

        let payload = RecordPayload(
            title:     title.trimmingCharacters(in: .whitespaces),
            artist:    artist.trimmingCharacters(in: .whitespaces),
            year:      Int(year),
            genre:     genre.isEmpty     ? nil : genre,
            notes:     notes.isEmpty     ? nil : notes,
            condition: condition?.rawValue,
            mbid:      mbid
        )

        do {
            let record = try await api.createRecord(payload)

            // Upload the captured photo as a separate request (raw image never
            // left the device until this point — only text strings were sent earlier)
            if let image = capturedImage,
               let jpeg = image.jpegData(compressionQuality: 0.82) {
                _ = try? await api.uploadImage(
                    recordId:  record.id.uuidString,
                    imageData: jpeg,
                    imageType: "cover",
                    isPrimary: true
                )
            }

            savedRecord = record
            resetForm()
        } catch {
            errorMessage = "Save failed: \(error.localizedDescription)"
        }

        phase = .idle
    }

    func resetForm() {
        title = ""; artist = ""; year = ""; genre = ""; notes = ""
        condition = nil; mbid = nil; coverArtUrl = nil
        capturedImage = nil; ocrLines = []; errorMessage = nil
    }
}

// MARK: - View

struct AddRecordView: View {
    @StateObject private var vm = AddRecordViewModel()
    @State private var showCamera       = false
    @State private var showPhotoLibrary = false
    @State private var showSuccess      = false

    var body: some View {
        NavigationStack {
            Form {
                photoSection
                metadataSection
                conditionSection
                notesSection
                if vm.coverArtUrl != nil { coverPreviewSection }
                if vm.mbid != nil        { mbidSection }
                if vm.errorMessage != nil { errorSection }
                saveSection
            }
            .navigationTitle("Add Record")
            .sheet(isPresented: $showCamera) {
                CameraPickerView(capturedImage: $vm.capturedImage, sourceType: .camera)
                    .ignoresSafeArea()
            }
            .sheet(isPresented: $showPhotoLibrary) {
                CameraPickerView(capturedImage: $vm.capturedImage, sourceType: .photoLibrary)
                    .ignoresSafeArea()
            }
            .onChange(of: vm.capturedImage) { _, image in
                if let image { Task { await vm.handleCapturedImage(image) } }
            }
            .onChange(of: vm.savedRecord) { _, record in
                if record != nil { showSuccess = true }
            }
            .alert("Record Added!", isPresented: $showSuccess) {
                Button("OK") {}
            } message: {
                Text("\"\(vm.savedRecord?.title ?? "Record")\" has been added to your collection.")
            }
        }
    }

    // MARK: - Form sections

    private var photoSection: some View {
        Section {
            if let image = vm.capturedImage {
                capturedImageRow(image)
            } else {
                cameraButtons
            }
        } header: {
            Text("Record Photo")
        } footer: {
            Text("Point at the cover or label. Text is extracted on-device — only extracted strings are sent to the server.")
                .font(.caption)
        }
    }

    private func capturedImageRow(_ image: UIImage) -> some View {
        HStack(spacing: 12) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 72, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 6) {
                statusLabel
                Button("Retake / Remove") {
                    vm.capturedImage = nil
                    vm.ocrLines      = []
                    vm.errorMessage  = nil
                }
                .font(.caption)
                .foregroundStyle(.red)
            }
        }
    }

    @ViewBuilder
    private var statusLabel: some View {
        switch vm.phase {
        case .runningOCR:
            Label("Scanning text…", systemImage: "text.viewfinder")
                .font(.caption).foregroundStyle(.secondary)
        case .lookingUp:
            Label("Fetching metadata…", systemImage: "magnifyingglass")
                .font(.caption).foregroundStyle(.secondary)
        default:
            if !vm.ocrLines.isEmpty {
                Label("Ready", systemImage: "checkmark.circle.fill")
                    .font(.caption).foregroundStyle(.green)
            }
        }
    }

    private var cameraButtons: some View {
        HStack(spacing: 12) {
            Button { showCamera = true } label: {
                Label("Camera", systemImage: "camera.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(vm.phase != .idle)

            Button { showPhotoLibrary = true } label: {
                Label("Library", systemImage: "photo.on.rectangle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(vm.phase != .idle)
        }
        .padding(.vertical, 4)
    }

    private var metadataSection: some View {
        Section("Metadata") {
            HStack {
                TextField("Title *", text: $vm.title)
                if vm.phase == .lookingUp {
                    ProgressView().scaleEffect(0.7)
                }
            }
            TextField("Artist *", text: $vm.artist)
            TextField("Year (e.g. 1977)", text: $vm.year)
                .keyboardType(.numberPad)
            TextField("Genre", text: $vm.genre)
        }
    }

    private var conditionSection: some View {
        Section("Condition") {
            Picker("Condition", selection: $vm.condition) {
                Text("Not set").tag(Optional<RecordCondition>.none)
                ForEach(RecordCondition.allCases) { c in
                    Text(c.displayName).tag(Optional(c))
                }
            }
        }
    }

    private var notesSection: some View {
        Section("Notes") {
            TextEditor(text: $vm.notes)
                .frame(minHeight: 80)
        }
    }

    private var coverPreviewSection: some View {
        Section("Cover Art from MusicBrainz") {
            if let urlStr = vm.coverArtUrl, let url = URL(string: urlStr) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let img):
                        img.resizable().aspectRatio(1, contentMode: .fit)
                    case .failure:
                        Label("Cover art unavailable", systemImage: "photo.slash")
                            .foregroundStyle(.secondary)
                    default:
                        ProgressView().frame(maxWidth: .infinity)
                    }
                }
                .frame(maxHeight: 220)
            }
        }
    }

    private var mbidSection: some View {
        Section("MusicBrainz") {
            if let mbid = vm.mbid {
                LabeledContent("MBID", value: mbid)
                    .font(.caption)
            }
        }
    }

    private var errorSection: some View {
        Section {
            Label(vm.errorMessage ?? "", systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(.orange)
        }
    }

    private var saveSection: some View {
        Section {
            Button {
                Task { await vm.save() }
            } label: {
                if vm.phase == .saving {
                    ProgressView().frame(maxWidth: .infinity)
                } else {
                    Text("Add to Collection")
                        .frame(maxWidth: .infinity)
                        .bold()
                }
            }
            .disabled(!vm.canSave)
        }
    }
}
