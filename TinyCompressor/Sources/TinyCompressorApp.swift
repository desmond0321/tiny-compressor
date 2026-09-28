import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers

@main
struct TinyCompressorApp: App {
    @StateObject private var model = CompressorModel()

    var body: some Scene {
        WindowGroup("Tiny Compressor") {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 980, minHeight: 680)
        }
        .windowResizability(.contentSize)
    }
}

struct ContentView: View {
    @EnvironmentObject private var model: CompressorModel
    @State private var dropTargeted = false
    @State private var queueDropTargeted = false
    @State private var showAdvancedWebPQuality = false
    @State private var showAdvancedPNGSettings = false
    @State private var showAdvancedJPEGSettings = false

    var body: some View {
        NavigationSplitView {
            List(selection: $model.selectedInput) {
                Section("Drop Queue") {
                    if model.inputs.isEmpty {
                        Text("No files or folders yet")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(model.inputs) { input in
                            HStack(spacing: 8) {
                                Label(input.url.lastPathComponent, systemImage: input.url.hasDirectoryPath ? "folder.fill" : "photo")
                                Spacer(minLength: 0)
                                if let progress = model.queueProgress(for: input) {
                                    Text(progress)
                                        .font(.caption2.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                }
                                if model.isQueueItemComplete(input) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                        .accessibilityLabel("Completed")
                                }
                            }
                            .tag(input.id)
                            .contextMenu {
                                Button("Remove from Queue", role: .destructive) {
                                    model.removeInput(input)
                                }
                                .disabled(model.isRunning)
                            }
                        }
                        .onDelete(perform: model.removeInputs)
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Label("Drop files or folders into this queue", systemImage: "arrow.down.to.line.compact")
                    .font(.caption)
                    .foregroundStyle(queueDropTargeted ? .white : .secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .background(queueDropTargeted ? Color.accentColor : Color(nsColor: .controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .padding(8)
            }
            .onDrop(of: [.fileURL], isTargeted: $queueDropTargeted, perform: model.acceptDrop)
            .navigationTitle("Tiny Compressor")
            .toolbar {
                ToolbarItemGroup {
                    Button(action: model.chooseInputs) {
                        Label("Add", systemImage: "plus")
                    }
                    .disabled(model.isRunning)

                    Button(action: model.previewSelectedInput) {
                        Label("Preview", systemImage: "eye")
                    }
                    .keyboardShortcut(.space, modifiers: [])
                    .disabled(!model.canPreviewSelectedInput)

                    Button(role: .destructive, action: model.removeSelectedInput) {
                        Label("Remove", systemImage: "minus.circle")
                    }
                    .keyboardShortcut(.delete, modifiers: [])
                    .disabled(!model.canRemoveSelectedInput || model.isRunning)

                    Button(action: model.clearInputs) {
                        Label("Clear", systemImage: "trash")
                    }
                    .disabled(model.inputs.isEmpty || model.isRunning)
                }
            }
        } detail: {
            VStack(spacing: 0) {
                dropZone
                Divider()
                settings
                Divider()
                results
            }
            .navigationTitle("Image Compression")
        }
        .alert("Replace original files?", isPresented: $model.showReplaceConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Replace Files", role: .destructive) { model.startCompression(confirmed: true) }
        } message: {
            Text("Only smaller results replace originals. This cannot be undone unless backups are enabled.")
        }
        .alert("Cannot start compression", isPresented: $model.showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.errorMessage)
        }
        .sheet(item: $model.previewItem) { previewItem in
            ImagePreviewSheet(item: previewItem)
        }
    }

    private var dropZone: some View {
        VStack(spacing: 16) {
            Image(systemName: "arrow.down.doc.fill")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(dropTargeted ? Color.white : Color.accentColor)
            Text("Drop image files or folders here")
                .font(.title3.weight(.semibold))
                .foregroundStyle(dropTargeted ? .white : .primary)
            Text("PNG, JPG, and JPEG. Folders are scanned recursively.")
                .foregroundStyle(dropTargeted ? .white.opacity(0.85) : .secondary)
            if !model.inputs.isEmpty {
                HStack(spacing: 12) {
                    Label("\(model.inputs.count) item\(model.inputs.count == 1 ? "" : "s") in queue", systemImage: "tray.full")
                        .font(.caption)
                        .foregroundStyle(dropTargeted ? .white.opacity(0.9) : .secondary)
                    Button("Clear Drop Queue", role: .destructive, action: model.clearInputs)
                        .controlSize(.small)
                        .disabled(model.isRunning)
                }
            }
            Button("Choose Files or Folders", action: model.chooseInputs)
                .buttonStyle(.borderedProminent)
                .disabled(model.isRunning)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 210)
        .background(dropTargeted ? Color.accentColor : Color(nsColor: .controlBackgroundColor))
        .onDrop(of: [.fileURL], isTargeted: $dropTargeted, perform: model.acceptDrop)
    }

    private var settings: some View {
        Form {
            Section("1. Choose what to create") {
                Picker("Output format", selection: $model.convertToWebP) {
                    Text("Optimize PNG and JPEG").tag(false)
                    Text("Convert to WebP").tag(true)
                }
                .pickerStyle(.radioGroup)
                .disabled(model.isRunning)

                if model.convertToWebP {
                    HStack(spacing: 8) {
                        Text("WebP quality")
                        Spacer()
                        webPQualityPreset(title: "Smaller", quality: 60)
                        webPQualityPreset(title: "Balanced", quality: 75)
                        webPQualityPreset(title: "Higher", quality: 85)
                    }
                    DisclosureGroup("Custom WebP quality", isExpanded: $showAdvancedWebPQuality) {
                        HStack {
                            Slider(value: $model.webPQuality, in: 1...100, step: 1)
                            Text("\(Int(model.webPQuality))")
                                .monospacedDigit()
                                .frame(width: 28, alignment: .trailing)
                        }
                    }
                    Text("Balanced is the default. WebP conversion encodes directly from the original image.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("2. Choose where to save") {
                Picker("Save compressed images", selection: $model.destinationMode) {
                    Text("Beside the original files").tag(DestinationMode.besideOriginal)
                    Text("In a separate output folder").tag(DestinationMode.outputFolder)
                    if !model.convertToWebP {
                        Text("Replace the original files").tag(DestinationMode.replaceOriginals)
                    }
                }
                .pickerStyle(.radioGroup)
                .disabled(model.isRunning)

                if model.destinationMode == .replaceOriginals {
                    Toggle("Keep .bak backups before replacing", isOn: $model.keepBackups)
                        .disabled(model.isRunning)
                } else if model.destinationMode == .outputFolder {
                    HStack {
                        Text("Output folder")
                        TextField("Choose a folder", text: $model.outputFolderPath)
                        Button("Choose", action: model.chooseOutputFolder)
                            .disabled(model.isRunning)
                    }
                    if !model.outputFolderPath.isEmpty {
                        Label(model.outputFolderPath, systemImage: "folder.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                } else {
                    Text(model.convertToWebP ? "Creates a .webp file next to each original. Originals are kept." : "Creates a -compressed file next to each original. Originals are kept.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Performance") {
                Stepper("Concurrent images: \(model.parallelJobs)", value: $model.parallelJobs, in: 1...model.maximumParallelJobs)
                    .disabled(model.isRunning)
                Text("Default: 4. Higher values finish batches faster but use more CPU and memory. This Mac allows up to \(model.maximumParallelJobs) concurrent images.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !model.convertToWebP {
                Section("Advanced Compression") {
                    DisclosureGroup("PNG quality and effort", isExpanded: $showAdvancedPNGSettings) {
                        HStack {
                            Text("Quality range")
                            Slider(value: $model.pngQualityMinimum, in: 0...100, step: 1)
                            Text("\(Int(model.pngQualityMinimum))")
                                .monospacedDigit()
                                .frame(width: 28, alignment: .trailing)
                            Text("to")
                            Slider(value: $model.pngQualityMaximum, in: 0...100, step: 1)
                            Text("\(Int(model.pngQualityMaximum))")
                                .monospacedDigit()
                                .frame(width: 28, alignment: .trailing)
                        }
                        Stepper("PNG effort: \(model.pngSpeed == 1 ? "Best compression" : "Speed \(model.pngSpeed)")", value: $model.pngSpeed, in: 1...11)
                        Toggle("Use Zopfli final pass when installed", isOn: $model.useZopfli)
                    }
                    DisclosureGroup("JPEG quality", isExpanded: $showAdvancedJPEGSettings) {
                        HStack {
                            Slider(value: $model.jpegQuality, in: 1...100, step: 1)
                            Text("\(Int(model.jpegQuality))")
                                .monospacedDigit()
                                .frame(width: 28, alignment: .trailing)
                        }
                    }
                    Text("Defaults: PNG 40-80 with best compression, JPEG 78.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
    }

    private func webPQualityPreset(title: String, quality: Double) -> some View {
        Button(title) { model.webPQuality = quality }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .tint(model.webPQuality == quality ? .accentColor : .secondary)
            .disabled(model.isRunning)
    }

    private var results: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(model.toolStatus)
                        .font(.caption)
                        .foregroundStyle(model.hasRequiredTools ? Color.secondary : Color.orange)
                    if !model.hasRequiredTools {
                        Text("Install with: brew install pngquant oxipng zopfli mozjpeg jpegoptim webp")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button("Clear Drop Queue", role: .destructive, action: model.clearInputs)
                    .disabled(model.inputs.isEmpty || model.isRunning)
                Button(model.isRunning ? model.runningActionTitle : model.primaryActionTitle) {
                    model.startCompression()
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.inputs.isEmpty || model.isRunning)
            }

            if model.isRunning {
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        ProgressView()
                            .controlSize(.small)
                        Text(model.currentStatus)
                            .font(.caption)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    ProgressView(value: model.progress)
                    if model.totalImages > 0 {
                        Text("\(model.completedImages) of \(model.totalImages) images complete")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if model.hasCompletedRun {
                HStack {
                    Label(model.currentStatus, systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    Spacer()
                    Button("Reveal Destination", action: model.revealLastDestination)
                        .disabled(model.lastDestinationPath.isEmpty)
                }
            }

            ScrollView {
                Text(model.logText.isEmpty ? "Results will appear here." : model.logText)
                    .font(.system(.caption, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(10)
            }
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .frame(minHeight: 125, maxHeight: 180)
        }
        .padding(18)
        .onAppear(perform: model.refreshToolStatus)
    }
}

struct InputItem: Identifiable, Hashable {
    let id = UUID()
    let url: URL
}

struct ImagePreviewItem: Identifiable {
    let id = UUID()
    let url: URL
}

struct ImagePreviewSheet: View {
    let item: ImagePreviewItem
    @EnvironmentObject private var model: CompressorModel
    @Environment(\.dismiss) private var dismiss
    @State private var image: NSImage?

    var body: some View {
        VStack(spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.url.lastPathComponent)
                        .font(.headline)
                    Text(item.url.deletingLastPathComponent().path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
                Button(action: model.previewPreviousInput) {
                    Image(systemName: "chevron.up")
                }
                .keyboardShortcut(.upArrow, modifiers: [])
                .disabled(!model.canPreviewPreviousInput)
                Button(action: model.previewNextInput) {
                    Image(systemName: "chevron.down")
                }
                .keyboardShortcut(.downArrow, modifiers: [])
                .disabled(!model.canPreviewNextInput)
                Button(role: .destructive, action: model.removePreviewedInput) {
                    Image(systemName: "trash")
                }
                .keyboardShortcut(.delete, modifiers: [])
                Button("Reveal") {
                    NSWorkspace.shared.activateFileViewerSelecting([item.url])
                }
                Button("Done", action: dismiss.callAsFunction)
                    .keyboardShortcut(.space, modifiers: [])
                    .keyboardShortcut(.cancelAction)
            }

            Group {
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                } else {
                    ContentUnavailableView("Unable to preview image", systemImage: "photo")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .windowBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .padding(18)
        .frame(minWidth: 620, minHeight: 480)
        .onAppear { image = NSImage(contentsOf: item.url) }
        .onChange(of: item.url) { image = NSImage(contentsOf: item.url) }
    }
}

struct CompressionSettings {
    let destinationMode: DestinationMode
    let keepBackups: Bool
    let outputFolder: URL?
    let convertToWebP: Bool
    let webPQuality: Int
    let pngQualityMinimum: Int
    let pngQualityMaximum: Int
    let pngSpeed: Int
    let jpegQuality: Int
    let useZopfli: Bool
    let parallelJobs: Int
}

enum DestinationMode: String {
    case besideOriginal
    case outputFolder
    case replaceOriginals
}

@MainActor
final class CompressorModel: ObservableObject {
    private enum PreferenceKey {
        static let replaceOriginals = "replaceOriginals"
        static let destinationMode = "destinationMode"
        static let keepBackups = "keepBackups"
        static let backupDefaultV2Applied = "backupDefaultV2Applied"
        static let outputFolderPath = "outputFolderPath"
        static let pngQualityMinimum = "pngQualityMinimum"
        static let pngQualityMaximum = "pngQualityMaximum"
        static let pngSpeed = "pngSpeed"
        static let jpegQuality = "jpegQuality"
        static let useZopfli = "useZopfli"
        static let parallelJobs = "parallelJobs"
        static let convertToWebP = "convertToWebP"
        static let webPQuality = "webPQuality"
    }

    private let preferences: UserDefaults
    let maximumParallelJobs: Int
    @Published var inputs: [InputItem] = []
    @Published var selectedInput: UUID?
    @Published var previewItem: ImagePreviewItem?
    @Published var destinationMode: DestinationMode { didSet { preferences.set(destinationMode.rawValue, forKey: PreferenceKey.destinationMode) } }
    @Published var keepBackups: Bool { didSet { preferences.set(keepBackups, forKey: PreferenceKey.keepBackups) } }
    @Published var outputFolderPath: String { didSet { preferences.set(outputFolderPath, forKey: PreferenceKey.outputFolderPath) } }
    @Published var pngQualityMinimum: Double { didSet { preferences.set(pngQualityMinimum, forKey: PreferenceKey.pngQualityMinimum) } }
    @Published var pngQualityMaximum: Double { didSet { preferences.set(pngQualityMaximum, forKey: PreferenceKey.pngQualityMaximum) } }
    @Published var pngSpeed: Int { didSet { preferences.set(pngSpeed, forKey: PreferenceKey.pngSpeed) } }
    @Published var jpegQuality: Double { didSet { preferences.set(jpegQuality, forKey: PreferenceKey.jpegQuality) } }
    @Published var useZopfli: Bool { didSet { preferences.set(useZopfli, forKey: PreferenceKey.useZopfli) } }
    @Published var parallelJobs: Int { didSet { preferences.set(parallelJobs, forKey: PreferenceKey.parallelJobs) } }
    @Published var convertToWebP: Bool {
        didSet {
            preferences.set(convertToWebP, forKey: PreferenceKey.convertToWebP)
            if convertToWebP, destinationMode == .replaceOriginals { destinationMode = .besideOriginal }
        }
    }
    @Published var webPQuality: Double { didSet { preferences.set(webPQuality, forKey: PreferenceKey.webPQuality) } }
    @Published var isRunning = false
    @Published var progress = 0.0
    @Published var completedImages = 0
    @Published var totalImages = 0
    @Published var currentStatus = "Waiting to start..."
    @Published var logText = ""
    @Published var toolStatus = "Checking compression tools..."
    @Published var hasRequiredTools = false
    @Published var hasCompletedRun = false
    @Published var lastDestinationPath = ""
    @Published var showReplaceConfirmation = false
    @Published var showError = false
    @Published var errorMessage = ""
    @Published private var queuedImagePaths = Set<String>()
    @Published private var completedImagePaths = Set<String>()

    var primaryActionTitle: String {
        convertToWebP ? "Convert to WebP" : "Compress Images"
    }

    var runningActionTitle: String {
        convertToWebP ? "Converting..." : "Compressing..."
    }

    init() {
        preferences = .standard
        maximumParallelJobs = max(1, min(ProcessInfo.processInfo.activeProcessorCount, 12))
        if let savedMode = preferences.string(forKey: PreferenceKey.destinationMode), let mode = DestinationMode(rawValue: savedMode) {
            destinationMode = mode
        } else {
            destinationMode = (preferences.object(forKey: PreferenceKey.replaceOriginals) as? Bool ?? false) ? .replaceOriginals : .outputFolder
        }
        if preferences.bool(forKey: PreferenceKey.backupDefaultV2Applied) {
            keepBackups = preferences.object(forKey: PreferenceKey.keepBackups) as? Bool ?? false
        } else {
            keepBackups = false
            preferences.set(false, forKey: PreferenceKey.keepBackups)
            preferences.set(true, forKey: PreferenceKey.backupDefaultV2Applied)
        }
        outputFolderPath = preferences.string(forKey: PreferenceKey.outputFolderPath) ?? ""
        pngQualityMinimum = preferences.object(forKey: PreferenceKey.pngQualityMinimum) as? Double ?? 40
        pngQualityMaximum = preferences.object(forKey: PreferenceKey.pngQualityMaximum) as? Double ?? 80
        pngSpeed = preferences.object(forKey: PreferenceKey.pngSpeed) as? Int ?? 1
        jpegQuality = preferences.object(forKey: PreferenceKey.jpegQuality) as? Double ?? 78
        useZopfli = preferences.object(forKey: PreferenceKey.useZopfli) as? Bool ?? true
        parallelJobs = min(max(1, preferences.object(forKey: PreferenceKey.parallelJobs) as? Int ?? 4), maximumParallelJobs)
        convertToWebP = preferences.object(forKey: PreferenceKey.convertToWebP) as? Bool ?? false
        webPQuality = preferences.object(forKey: PreferenceKey.webPQuality) as? Double ?? 75
        if convertToWebP, destinationMode == .replaceOriginals { destinationMode = .besideOriginal }
    }

    func refreshToolStatus() {
        let tools = ToolLocator.availableTools()
        hasRequiredTools = tools.pngquant != nil || tools.cwebp != nil
        if hasRequiredTools {
            let available = [tools.pngquant != nil ? "pngquant" : nil, tools.zopflipng != nil ? "Zopfli" : nil, tools.oxipng != nil ? "OxiPNG" : nil, tools.cjpeg != nil ? "MozJPEG" : nil, tools.jpegoptim != nil ? "jpegoptim" : nil, tools.cwebp != nil ? "WebP" : nil].compactMap { $0 }
            toolStatus = "Ready: \(available.joined(separator: ", "))"
        } else {
            toolStatus = "No compression tools were found."
        }
    }

    func chooseInputs() {
        let panel = NSOpenPanel()
        panel.title = "Choose Image Files or Folders"
        panel.prompt = "Add"
        panel.allowsMultipleSelection = true
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.begin { response in
            guard response == .OK else { return }
            self.addInputs(panel.urls)
        }
    }

    func chooseOutputFolder() {
        let panel = NSOpenPanel()
        panel.title = "Choose Output Folder"
        panel.prompt = "Choose"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            self.outputFolderPath = url.path
        }
    }

    func acceptDrop(_ providers: [NSItemProvider]) -> Bool {
        var accepted = false
        for provider in providers {
            _ = provider.loadObject(ofClass: URL.self) { [weak self] url, _ in
                guard let url else { return }
                DispatchQueue.main.async { self?.addInputs([url]) }
            }
            accepted = true
        }
        return accepted
    }

    func removeInputs(at offsets: IndexSet) {
        guard !isRunning else { return }
        inputs.remove(atOffsets: offsets)
        clearSelectionIfNeeded()
    }

    var canRemoveSelectedInput: Bool {
        selectedInput != nil
    }

    func removeSelectedInput() {
        guard !isRunning, let selectedInput, let input = inputs.first(where: { $0.id == selectedInput }) else { return }
        removeInput(input)
    }

    func removeInput(_ input: InputItem) {
        guard !isRunning else { return }
        inputs.removeAll { $0.id == input.id }
        clearSelectionIfNeeded()
    }

    func removePreviewedInput() {
        guard let previewURL = previewItem?.url.standardizedFileURL,
              let input = inputs.first(where: { $0.url.standardizedFileURL == previewURL }) else { return }
        removeInput(input)
        previewItem = nil
    }

    func clearInputs() {
        inputs.removeAll()
        selectedInput = nil
        previewItem = nil
        queuedImagePaths.removeAll()
        completedImagePaths.removeAll()
    }

    var canPreviewSelectedInput: Bool {
        guard let selectedInput, let input = inputs.first(where: { $0.id == selectedInput }) else { return false }
        return !input.url.hasDirectoryPath
    }

    func previewSelectedInput() {
        guard let selectedInput, let input = inputs.first(where: { $0.id == selectedInput }), !input.url.hasDirectoryPath else { return }
        previewItem = ImagePreviewItem(url: input.url)
    }

    var canPreviewPreviousInput: Bool {
        previewNavigationIndex.map { $0 > 0 } ?? false
    }

    var canPreviewNextInput: Bool {
        guard let previewNavigationIndex else { return false }
        return previewNavigationIndex < previewableInputs.count - 1
    }

    func previewPreviousInput() {
        movePreview(by: -1)
    }

    func previewNextInput() {
        movePreview(by: 1)
    }

    func isQueueItemComplete(_ input: InputItem) -> Bool {
        let imagePaths = imagePaths(for: input)
        return !imagePaths.isEmpty && imagePaths.allSatisfy(completedImagePaths.contains)
    }

    func queueProgress(for input: InputItem) -> String? {
        let imagePaths = imagePaths(for: input)
        guard input.url.hasDirectoryPath, !imagePaths.isEmpty else { return nil }
        let completed = imagePaths.count(where: completedImagePaths.contains)
        return completed == imagePaths.count ? nil : "\(completed)/\(imagePaths.count)"
    }

    func startCompression(confirmed: Bool = false) {
        refreshToolStatus()
        let tools = ToolLocator.availableTools()
        if convertToWebP && tools.cwebp == nil {
            presentError("WebP conversion requires cwebp: brew install webp")
            return
        }
        if !convertToWebP && tools.pngquant == nil {
            presentError("Install pngquant first: brew install pngquant")
            return
        }
        guard pngQualityMinimum <= pngQualityMaximum else {
            presentError("PNG minimum quality cannot be higher than maximum quality.")
            return
        }
        let destinationMode = convertToWebP && self.destinationMode == .replaceOriginals ? .besideOriginal : self.destinationMode
        if destinationMode == .replaceOriginals && !confirmed {
            showReplaceConfirmation = true
            return
        }

        let outputURL = outputFolderPath.isEmpty ? nil : URL(fileURLWithPath: outputFolderPath, isDirectory: true)
        if destinationMode == .outputFolder && outputURL == nil {
            presentError("Choose an output folder, or select Save beside the original files.")
            return
        }
        if destinationMode == .outputFolder, let outputURL {
            do {
                try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)
            } catch {
                presentError("Could not create the output folder: \(error.localizedDescription)")
                return
            }
        }

        let settings = CompressionSettings(
            destinationMode: destinationMode,
            keepBackups: keepBackups,
            outputFolder: outputURL,
            convertToWebP: convertToWebP,
            webPQuality: Int(webPQuality),
            pngQualityMinimum: Int(pngQualityMinimum),
            pngQualityMaximum: Int(pngQualityMaximum),
            pngSpeed: pngSpeed,
            jpegQuality: Int(jpegQuality),
            useZopfli: useZopfli,
            parallelJobs: parallelJobs
        )
        let selectedURLs = inputs.map(\.url)
        let destinationPath: String
        if destinationMode == .outputFolder {
            destinationPath = outputURL?.path ?? ""
        } else if let firstInput = selectedURLs.first {
            destinationPath = (firstInput.hasDirectoryPath ? firstInput : firstInput.deletingLastPathComponent()).path
        } else {
            destinationPath = ""
        }
        isRunning = true
        hasCompletedRun = false
        lastDestinationPath = ""
        queuedImagePaths.removeAll()
        completedImagePaths.removeAll()
        progress = 0
        completedImages = 0
        totalImages = 0
        currentStatus = "Scanning inputs..."
        logText = "Scanning inputs...\n"

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let outcome = CompressionEngine.run(inputs: selectedURLs, settings: settings) { update in
                DispatchQueue.main.async {
                    let newProgress = update.total == 0 ? 0 : Double(update.completed) / Double(update.total)
                    self?.progress = max(self?.progress ?? 0, newProgress)
                    self?.completedImages = max(self?.completedImages ?? 0, update.completed)
                    self?.totalImages = max(self?.totalImages ?? 0, update.total)
                    self?.currentStatus = update.message
                    self?.logText.append(update.message + "\n")
                    if !update.discoveredImagePaths.isEmpty {
                        self?.queuedImagePaths = Set(update.discoveredImagePaths)
                    }
                    if let completedImagePath = update.completedImagePath {
                        self?.completedImagePaths.insert(completedImagePath)
                    }
                }
            }
            DispatchQueue.main.async {
                self?.isRunning = false
                self?.progress = 1
                self?.currentStatus = outcome.summary
                self?.logText.append("\n\(outcome.summary)\n")
                self?.lastDestinationPath = destinationPath
                self?.hasCompletedRun = true
            }
        }
    }

    func revealLastDestination() {
        guard !lastDestinationPath.isEmpty else { return }
        NSWorkspace.shared.open(URL(fileURLWithPath: lastDestinationPath, isDirectory: true))
    }

    private func addInputs(_ urls: [URL]) {
        let newItems = urls.filter { url in !inputs.contains(where: { $0.url.standardizedFileURL == url.standardizedFileURL }) }.map(InputItem.init)
        inputs.append(contentsOf: newItems)
        if outputFolderPath.isEmpty, let first = newItems.first?.url {
            let parent = first.hasDirectoryPath ? first : first.deletingLastPathComponent()
            outputFolderPath = parent.appendingPathComponent("optimized", isDirectory: true).path
        }
    }

    private func presentError(_ message: String) {
        errorMessage = message
        showError = true
    }

    private func imagePaths(for input: InputItem) -> [String] {
        let inputPath = input.url.standardizedFileURL.path
        if input.url.hasDirectoryPath {
            let prefix = inputPath.hasSuffix("/") ? inputPath : inputPath + "/"
            return queuedImagePaths.filter { $0.hasPrefix(prefix) }
        }
        return queuedImagePaths.contains(inputPath) ? [inputPath] : []
    }

    private func clearSelectionIfNeeded() {
        guard let selectedInput, !inputs.contains(where: { $0.id == selectedInput }) else { return }
        self.selectedInput = nil
        previewItem = nil
    }

    private var previewableInputs: [InputItem] {
        inputs.filter { !$0.url.hasDirectoryPath }
    }

    private var previewNavigationIndex: Int? {
        guard let previewURL = previewItem?.url.standardizedFileURL else { return nil }
        return previewableInputs.firstIndex { $0.url.standardizedFileURL == previewURL }
    }

    private func movePreview(by offset: Int) {
        guard let index = previewNavigationIndex else { return }
        let nextIndex = index + offset
        guard previewableInputs.indices.contains(nextIndex) else { return }
        let nextInput = previewableInputs[nextIndex]
        selectedInput = nextInput.id
        previewItem = ImagePreviewItem(url: nextInput.url)
    }
}

struct CompressionOutcome {
    let summary: String
}

struct CompressionProgress {
    let completed: Int
    let total: Int
    let message: String
    let discoveredImagePaths: [String]
    let completedImagePath: String?
}

private final class RunState: @unchecked Sendable {
    private let lock = NSLock()
    private var saved = 0
    private var converted = 0
    private var unchanged = 0
    private var failed = 0
    private var completed = 0
    private var active = 0
    private var originalBytes: Int64 = 0
    private var finalBytes: Int64 = 0

    func started() -> (completed: Int, active: Int) {
        lock.lock()
        active += 1
        let snapshot = (completed, active)
        lock.unlock()
        return snapshot
    }

    func finished(_ result: FileResult) -> (completed: Int, active: Int) {
        lock.lock()
        originalBytes += result.before
        finalBytes += result.after
        completed += 1
        active -= 1
        switch result.kind {
        case .saved: saved += 1
        case .converted: converted += 1
        case .unchanged: unchanged += 1
        case .failed: failed += 1
        }
        let snapshot = (completed, active)
        lock.unlock()
        return snapshot
    }

    func totals() -> (saved: Int, converted: Int, unchanged: Int, failed: Int, originalBytes: Int64, finalBytes: Int64) {
        lock.lock()
        let snapshot = (saved, converted, unchanged, failed, originalBytes, finalBytes)
        lock.unlock()
        return snapshot
    }
}

enum CompressionEngine {
    static func run(inputs: [URL], settings: CompressionSettings, progress: @escaping (CompressionProgress) -> Void) -> CompressionOutcome {
        let files = ImageCollector.collect(from: inputs)
        guard !files.isEmpty else { return CompressionOutcome(summary: "No PNG, JPG, or JPEG files were found.") }

        let maximumJobs = max(1, min(settings.parallelJobs, min(ProcessInfo.processInfo.activeProcessorCount, 12)))
        progress(CompressionProgress(
            completed: 0,
            total: files.count,
            message: "Found \(files.count) image(s). Preparing \(maximumJobs) concurrent worker(s)...",
            discoveredImagePaths: files.map { $0.source.standardizedFileURL.path },
            completedImagePath: nil
        ))
        let operationName = settings.convertToWebP ? "Converting to WebP" : "Compressing"

        let state = RunState()
        let queue = OperationQueue()
        queue.name = "com.desmondyong.tinycompressor.workers"
        queue.maxConcurrentOperationCount = maximumJobs

        for (index, job) in files.enumerated() {
            queue.addOperation {
                let started = state.started()
                progress(CompressionProgress(
                    completed: started.completed,
                    total: files.count,
                    message: "\(operationName) \(index + 1) of \(files.count): \(job.source.lastPathComponent) (\(started.active)/\(maximumJobs) active)",
                    discoveredImagePaths: [],
                    completedImagePath: nil
                ))
                let result = compress(job: job, settings: settings)
                let finished = state.finished(result)
                progress(CompressionProgress(
                    completed: finished.completed,
                    total: files.count,
                    message: result.message,
                    discoveredImagePaths: [],
                    completedImagePath: job.source.standardizedFileURL.path
                ))
            }
        }
        queue.waitUntilAllOperationsAreFinished()

        let totals = state.totals()
        let byteDifference = totals.originalBytes - totals.finalBytes
        let percent = totals.originalBytes == 0 ? 0 : (Double(abs(byteDifference)) / Double(totals.originalBytes)) * 100
        let sizeSummary: String
        if byteDifference >= 0 {
            sizeSummary = "Saved \(ByteCountFormatter.string(fromByteCount: byteDifference, countStyle: .file)) (\(String(format: "%.1f", percent))%)."
        } else {
            sizeSummary = "Output is \(ByteCountFormatter.string(fromByteCount: -byteDifference, countStyle: .file)) larger (\(String(format: "%.1f", percent))%)."
        }
        return CompressionOutcome(summary: "Finished: \(files.count) image(s), \(totals.saved) reduced, \(totals.converted) converted to WebP, \(totals.unchanged) unchanged, \(totals.failed) failed. \(sizeSummary)")
    }

    private static func compress(job: ImageJob, settings: CompressionSettings) -> FileResult {
        guard let before = fileSize(job.source) else { return .failed(job.source, "Could not read \(job.source.path)") }
        let tools = ToolLocator.availableTools()
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("TinyCompressor-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: temporary) }

        do { try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true) }
        catch { return .failed(job.source, "Could not create temporary workspace for \(job.source.lastPathComponent)") }

        let candidateExtension = settings.convertToWebP ? "webp" : job.source.pathExtension.lowercased()
        let candidate = temporary.appendingPathComponent(job.source.deletingPathExtension().lastPathComponent + ".candidate." + candidateExtension)
        let success: Bool
        if settings.convertToWebP {
            success = convertToWebP(source: job.source, candidate: candidate, tools: tools, settings: settings)
        } else {
            switch job.kind {
            case .png:
                success = compressPNG(source: job.source, candidate: candidate, tools: tools, settings: settings)
            case .jpeg:
                success = compressJPEG(source: job.source, candidate: candidate, tools: tools, settings: settings)
            }
        }
        guard success, let after = fileSize(candidate), after > 0 else {
            return .failed(job.source, "Could not create output for \(job.source.lastPathComponent)")
        }
        guard settings.convertToWebP || after < before else {
            return .unchanged(job.source, before, "Kept \(job.source.lastPathComponent) (no smaller result)")
        }

        do {
            let destination: URL
            if settings.destinationMode == .replaceOriginals {
                destination = job.source
                if settings.keepBackups {
                    let backup = job.source.appendingPathExtension("bak")
                    try? FileManager.default.removeItem(at: backup)
                    try FileManager.default.copyItem(at: job.source, to: backup)
                }
            } else if settings.destinationMode == .besideOriginal {
                destination = job.source.deletingLastPathComponent().appendingPathComponent(besideOriginalName(for: job, settings: settings))
            } else if let output = settings.outputFolder {
                destination = output.appendingPathComponent(settings.convertToWebP ? webPRelativePath(for: job.relativePath) : job.relativePath)
                try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            } else {
                return .failed(job.source, "No output folder for \(job.source.lastPathComponent)")
            }

            if settings.destinationMode == .replaceOriginals {
                let replacement = destination.deletingLastPathComponent()
                    .appendingPathComponent(".\(destination.lastPathComponent).tinycompressor-\(UUID().uuidString)")
                try FileManager.default.copyItem(at: candidate, to: replacement)
                _ = try FileManager.default.replaceItemAt(destination, withItemAt: replacement)
            } else {
                guard destination.standardizedFileURL != job.source.standardizedFileURL else {
                    return .failed(job.source, "Output folder would overwrite \(job.source.lastPathComponent). Choose another folder or use Replace mode.")
                }
                try? FileManager.default.removeItem(at: destination)
                try FileManager.default.copyItem(at: candidate, to: destination)
            }
            if settings.convertToWebP {
                return .converted(job.source, before, after, "Converted \(job.source.lastPathComponent) to WebP: \(format(before)) -> \(format(after))")
            }
            return .saved(job.source, before, after, "Compressed \(job.source.lastPathComponent): \(format(before)) -> \(format(after))")
        } catch {
            return .failed(job.source, "Failed to save \(job.source.lastPathComponent): \(error.localizedDescription)")
        }
    }

    private static func compressPNG(source: URL, candidate: URL, tools: CompressionTools, settings: CompressionSettings) -> Bool {
        guard let pngquant = tools.pngquant else { return false }
        let quantized = ProcessRunner.run(pngquant, ["--quality=\(settings.pngQualityMinimum)-\(settings.pngQualityMaximum)", "--speed", "\(settings.pngSpeed)", "--strip", "--force", "--floyd=1", "--output", candidate.path, source.path])
        guard quantized && FileManager.default.fileExists(atPath: candidate.path) else { return false }

        if settings.useZopfli, let zopfli = tools.zopflipng {
            let polished = candidate.deletingLastPathComponent().appendingPathComponent("polished.png")
            if ProcessRunner.run(zopfli, ["-y", "-m", "--iterations=15", candidate.path, polished.path]),
               let polishedSize = fileSize(polished), let candidateSize = fileSize(candidate), polishedSize < candidateSize {
                try? FileManager.default.removeItem(at: candidate)
                try? FileManager.default.moveItem(at: polished, to: candidate)
            }
        } else if let oxipng = tools.oxipng {
            _ = ProcessRunner.run(oxipng, ["-q", "-o", "4", "--strip", "safe", candidate.path])
        }
        return true
    }

    private static func compressJPEG(source: URL, candidate: URL, tools: CompressionTools, settings: CompressionSettings) -> Bool {
        if let cjpeg = tools.cjpeg,
           ProcessRunner.run(cjpeg, ["-quality", "\(settings.jpegQuality)", "-optimize", "-progressive", "-outfile", candidate.path, source.path]) {
            return true
        }
        if let jpegoptim = tools.jpegoptim {
            do { try FileManager.default.copyItem(at: source, to: candidate) } catch { return false }
            return ProcessRunner.run(jpegoptim, ["--strip-all", "--all-progressive", "--max=\(settings.jpegQuality)", "--quiet", candidate.path])
        }
        return false
    }

    private static func convertToWebP(source: URL, candidate: URL, tools: CompressionTools, settings: CompressionSettings) -> Bool {
        guard let cwebp = tools.cwebp else { return false }
        return ProcessRunner.run(cwebp, ["-quiet", "-q", "\(settings.webPQuality)", "-m", "6", "-metadata", "none", source.path, "-o", candidate.path])
    }

    private static func webPRelativePath(for relativePath: String) -> String {
        (relativePath as NSString).deletingPathExtension + ".webp"
    }

    private static func besideOriginalName(for job: ImageJob, settings: CompressionSettings) -> String {
        let basename = (job.source.lastPathComponent as NSString).deletingPathExtension
        if settings.convertToWebP {
            return basename + ".webp"
        }
        return basename + "-compressed." + job.source.pathExtension.lowercased()
    }

    private static func fileSize(_ url: URL) -> Int64? {
        (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize.map(Int64.init)
    }

    private static func format(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

enum ImageKind { case png, jpeg }

struct ImageJob {
    let source: URL
    let relativePath: String
    let kind: ImageKind
}

enum ImageCollector {
    static func collect(from inputs: [URL]) -> [ImageJob] {
        var jobs: [ImageJob] = []
        var seen = Set<URL>()
        for input in inputs {
            let rootName = input.deletingPathExtension().lastPathComponent
            let sourceURLs: [URL]
            if input.hasDirectoryPath {
                sourceURLs = (FileManager.default.enumerator(at: input, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles, .skipsPackageDescendants])?.allObjects as? [URL]) ?? []
            } else {
                sourceURLs = [input]
            }
            for source in sourceURLs where !seen.contains(source.standardizedFileURL) {
                guard let kind = imageKind(for: source) else { continue }
                seen.insert(source.standardizedFileURL)
                let relative: String
                if input.hasDirectoryPath {
                    let suffix = source.path.dropFirst(input.path.count).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                    relative = rootName + "/" + suffix
                } else {
                    relative = source.lastPathComponent
                }
                jobs.append(ImageJob(source: source, relativePath: relative, kind: kind))
            }
        }
        return jobs.sorted { $0.source.path.localizedStandardCompare($1.source.path) == .orderedAscending }
    }

    private static func imageKind(for url: URL) -> ImageKind? {
        switch url.pathExtension.lowercased() {
        case "png": return .png
        case "jpg", "jpeg": return .jpeg
        default: return nil
        }
    }
}

struct CompressionTools {
    let pngquant: String?
    let zopflipng: String?
    let oxipng: String?
    let cjpeg: String?
    let jpegoptim: String?
    let cwebp: String?
}

enum ToolLocator {
    static func availableTools() -> CompressionTools {
        CompressionTools(
            pngquant: find("pngquant"),
            zopflipng: find("zopflipng"),
            oxipng: find("oxipng"),
            cjpeg: findMozJPEG(),
            jpegoptim: find("jpegoptim"),
            cwebp: find("cwebp")
        )
    }

    private static func find(_ tool: String) -> String? {
        if let bundled = bundledTool(named: tool) { return bundled }
        let paths = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin"] + (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map(String.init)
        for directory in paths {
            let candidate = URL(fileURLWithPath: directory).appendingPathComponent(tool).path
            if FileManager.default.isExecutableFile(atPath: candidate) { return candidate }
        }
        return nil
    }

    private static func findMozJPEG() -> String? {
        if let bundled = bundledTool(named: "cjpeg") { return bundled }
        for candidate in ["/opt/homebrew/opt/mozjpeg/bin/cjpeg", "/usr/local/opt/mozjpeg/bin/cjpeg"] {
            if FileManager.default.isExecutableFile(atPath: candidate) { return candidate }
        }
        return find("cjpeg")
    }

    private static func bundledTool(named tool: String) -> String? {
        guard let resourceURL = Bundle.main.resourceURL else { return nil }
        let candidate = resourceURL.appendingPathComponent("Tools/\(tool)").path
        return FileManager.default.isExecutableFile(atPath: candidate) ? candidate : nil
    }
}

enum ProcessRunner {
    static func run(_ executable: String, _ arguments: [String]) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }
}

enum ResultKind { case saved, converted, unchanged, failed }

struct FileResult {
    let kind: ResultKind
    let before: Int64
    let after: Int64
    let message: String

    static func saved(_ source: URL, _ before: Int64, _ after: Int64, _ message: String) -> FileResult {
        FileResult(kind: .saved, before: before, after: after, message: message)
    }
    static func converted(_ source: URL, _ before: Int64, _ after: Int64, _ message: String) -> FileResult {
        FileResult(kind: .converted, before: before, after: after, message: message)
    }
    static func unchanged(_ source: URL, _ before: Int64, _ message: String) -> FileResult {
        FileResult(kind: .unchanged, before: before, after: before, message: message)
    }
    static func failed(_ source: URL, _ message: String) -> FileResult {
        FileResult(kind: .failed, before: 0, after: 0, message: message)
    }
}
