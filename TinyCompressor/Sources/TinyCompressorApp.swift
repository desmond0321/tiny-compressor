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

    var body: some View {
        NavigationSplitView {
            List(selection: $model.selectedInput) {
                Section("Drop Queue") {
                    if model.inputs.isEmpty {
                        Text("No files or folders yet")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(model.inputs) { input in
                            Label(input.url.lastPathComponent, systemImage: input.url.hasDirectoryPath ? "folder.fill" : "photo")
                                .tag(input.id)
                        }
                        .onDelete(perform: model.removeInputs)
                    }
                }
            }
            .navigationTitle("Tiny Compressor")
            .toolbar {
                ToolbarItemGroup {
                    Button(action: model.chooseInputs) {
                        Label("Add", systemImage: "plus")
                    }
                    .disabled(model.isRunning)

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
            Section("Destination") {
                Picker("Save compressed images", selection: $model.replaceOriginals) {
                    Text("In a separate output folder").tag(false)
                    Text("Replace the original files").tag(true)
                }
                .pickerStyle(.radioGroup)
                .disabled(model.isRunning)

                if model.replaceOriginals {
                    Toggle("Keep .bak backups before replacing", isOn: $model.keepBackups)
                        .disabled(model.isRunning)
                } else {
                    HStack {
                        Text("Output folder")
                        TextField("Choose a folder", text: $model.outputFolderPath)
                        Button("Choose", action: model.chooseOutputFolder)
                            .disabled(model.isRunning)
                    }
                }
            }

            Section("Performance") {
                Stepper("Concurrent images: \(model.parallelJobs)", value: $model.parallelJobs, in: 1...model.maximumParallelJobs)
                    .disabled(model.isRunning)
                Text("Default: 4. Higher values finish batches faster but use more CPU and memory. This Mac allows up to \(model.maximumParallelJobs) concurrent images.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("PNG Quality") {
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
                Text("Lower values make smaller files but can show more color reduction. Default: 40-80, matching the shell script.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Stepper("PNG effort: \(model.pngSpeed == 1 ? "Best compression" : "Speed \(model.pngSpeed)")", value: $model.pngSpeed, in: 1...11)
                    .disabled(model.isRunning)
                Toggle("Use Zopfli final pass when installed", isOn: $model.useZopfli)
                    .disabled(model.isRunning)
            }

            Section("JPEG Quality") {
                HStack {
                    Text("Quality")
                    Slider(value: $model.jpegQuality, in: 1...100, step: 1)
                    Text("\(Int(model.jpegQuality))")
                        .monospacedDigit()
                        .frame(width: 28, alignment: .trailing)
                }
                Text("Default: 78, using MozJPEG when installed.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
    }

    private var results: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(model.toolStatus)
                        .font(.caption)
                        .foregroundStyle(model.hasRequiredTools ? Color.secondary : Color.orange)
                    if !model.hasRequiredTools {
                        Text("Install with: brew install pngquant oxipng zopfli mozjpeg jpegoptim")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button(model.isRunning ? "Compressing..." : "Compress Images") {
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

struct CompressionSettings {
    let replaceOriginals: Bool
    let keepBackups: Bool
    let outputFolder: URL?
    let pngQualityMinimum: Int
    let pngQualityMaximum: Int
    let pngSpeed: Int
    let jpegQuality: Int
    let useZopfli: Bool
    let parallelJobs: Int
}

@MainActor
final class CompressorModel: ObservableObject {
    private enum PreferenceKey {
        static let replaceOriginals = "replaceOriginals"
        static let keepBackups = "keepBackups"
        static let outputFolderPath = "outputFolderPath"
        static let pngQualityMinimum = "pngQualityMinimum"
        static let pngQualityMaximum = "pngQualityMaximum"
        static let pngSpeed = "pngSpeed"
        static let jpegQuality = "jpegQuality"
        static let useZopfli = "useZopfli"
        static let parallelJobs = "parallelJobs"
    }

    private let preferences: UserDefaults
    let maximumParallelJobs: Int
    @Published var inputs: [InputItem] = []
    @Published var selectedInput: UUID?
    @Published var replaceOriginals: Bool { didSet { preferences.set(replaceOriginals, forKey: PreferenceKey.replaceOriginals) } }
    @Published var keepBackups: Bool { didSet { preferences.set(keepBackups, forKey: PreferenceKey.keepBackups) } }
    @Published var outputFolderPath: String { didSet { preferences.set(outputFolderPath, forKey: PreferenceKey.outputFolderPath) } }
    @Published var pngQualityMinimum: Double { didSet { preferences.set(pngQualityMinimum, forKey: PreferenceKey.pngQualityMinimum) } }
    @Published var pngQualityMaximum: Double { didSet { preferences.set(pngQualityMaximum, forKey: PreferenceKey.pngQualityMaximum) } }
    @Published var pngSpeed: Int { didSet { preferences.set(pngSpeed, forKey: PreferenceKey.pngSpeed) } }
    @Published var jpegQuality: Double { didSet { preferences.set(jpegQuality, forKey: PreferenceKey.jpegQuality) } }
    @Published var useZopfli: Bool { didSet { preferences.set(useZopfli, forKey: PreferenceKey.useZopfli) } }
    @Published var parallelJobs: Int { didSet { preferences.set(parallelJobs, forKey: PreferenceKey.parallelJobs) } }
    @Published var isRunning = false
    @Published var progress = 0.0
    @Published var completedImages = 0
    @Published var totalImages = 0
    @Published var currentStatus = "Waiting to start..."
    @Published var logText = ""
    @Published var toolStatus = "Checking compression tools..."
    @Published var hasRequiredTools = false
    @Published var showReplaceConfirmation = false
    @Published var showError = false
    @Published var errorMessage = ""

    init() {
        preferences = .standard
        maximumParallelJobs = max(1, min(ProcessInfo.processInfo.activeProcessorCount, 12))
        replaceOriginals = preferences.object(forKey: PreferenceKey.replaceOriginals) as? Bool ?? false
        keepBackups = preferences.object(forKey: PreferenceKey.keepBackups) as? Bool ?? false
        outputFolderPath = preferences.string(forKey: PreferenceKey.outputFolderPath) ?? ""
        pngQualityMinimum = preferences.object(forKey: PreferenceKey.pngQualityMinimum) as? Double ?? 40
        pngQualityMaximum = preferences.object(forKey: PreferenceKey.pngQualityMaximum) as? Double ?? 80
        pngSpeed = preferences.object(forKey: PreferenceKey.pngSpeed) as? Int ?? 1
        jpegQuality = preferences.object(forKey: PreferenceKey.jpegQuality) as? Double ?? 78
        useZopfli = preferences.object(forKey: PreferenceKey.useZopfli) as? Bool ?? true
        parallelJobs = min(max(1, preferences.object(forKey: PreferenceKey.parallelJobs) as? Int ?? 4), maximumParallelJobs)
    }

    func refreshToolStatus() {
        let tools = ToolLocator.availableTools()
        hasRequiredTools = tools.pngquant != nil
        if hasRequiredTools {
            let extras = [tools.zopflipng != nil ? "Zopfli" : nil, tools.oxipng != nil ? "OxiPNG" : nil, tools.cjpeg != nil ? "MozJPEG" : nil, tools.jpegoptim != nil ? "jpegoptim" : nil].compactMap { $0 }
            toolStatus = extras.isEmpty ? "pngquant found. Install Zopfli or OxiPNG for smaller PNGs." : "Ready: pngquant + \(extras.joined(separator: ", "))"
        } else {
            toolStatus = "pngquant is required but was not found."
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
        inputs.remove(atOffsets: offsets)
    }

    func clearInputs() {
        inputs.removeAll()
        selectedInput = nil
    }

    func startCompression(confirmed: Bool = false) {
        refreshToolStatus()
        guard hasRequiredTools else {
            presentError("Install pngquant first: brew install pngquant")
            return
        }
        guard pngQualityMinimum <= pngQualityMaximum else {
            presentError("PNG minimum quality cannot be higher than maximum quality.")
            return
        }
        if replaceOriginals && !confirmed {
            showReplaceConfirmation = true
            return
        }

        let outputURL = outputFolderPath.isEmpty ? nil : URL(fileURLWithPath: outputFolderPath, isDirectory: true)
        if !replaceOriginals && outputURL == nil {
            presentError("Choose an output folder, or select Replace the original files.")
            return
        }
        if let outputURL {
            do {
                try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)
            } catch {
                presentError("Could not create the output folder: \(error.localizedDescription)")
                return
            }
        }

        let settings = CompressionSettings(
            replaceOriginals: replaceOriginals,
            keepBackups: keepBackups,
            outputFolder: outputURL,
            pngQualityMinimum: Int(pngQualityMinimum),
            pngQualityMaximum: Int(pngQualityMaximum),
            pngSpeed: pngSpeed,
            jpegQuality: Int(jpegQuality),
            useZopfli: useZopfli,
            parallelJobs: parallelJobs
        )
        let selectedURLs = inputs.map(\.url)
        isRunning = true
        progress = 0
        completedImages = 0
        totalImages = 0
        currentStatus = "Scanning inputs..."
        logText = "Scanning inputs...\n"

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let outcome = CompressionEngine.run(inputs: selectedURLs, settings: settings) { completed, total, message in
                DispatchQueue.main.async {
                    let newProgress = total == 0 ? 0 : Double(completed) / Double(total)
                    self?.progress = max(self?.progress ?? 0, newProgress)
                    self?.completedImages = max(self?.completedImages ?? 0, completed)
                    self?.totalImages = max(self?.totalImages ?? 0, total)
                    self?.currentStatus = message
                    self?.logText.append(message + "\n")
                }
            }
            DispatchQueue.main.async {
                self?.isRunning = false
                self?.progress = 1
                self?.currentStatus = outcome.summary
                self?.logText.append("\n\(outcome.summary)\n")
            }
        }
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
}

struct CompressionOutcome {
    let summary: String
}

private final class RunState: @unchecked Sendable {
    private let lock = NSLock()
    private var saved = 0
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
        case .unchanged: unchanged += 1
        case .failed: failed += 1
        }
        let snapshot = (completed, active)
        lock.unlock()
        return snapshot
    }

    func totals() -> (saved: Int, unchanged: Int, failed: Int, originalBytes: Int64, finalBytes: Int64) {
        lock.lock()
        let snapshot = (saved, unchanged, failed, originalBytes, finalBytes)
        lock.unlock()
        return snapshot
    }
}

enum CompressionEngine {
    static func run(inputs: [URL], settings: CompressionSettings, progress: @escaping (Int, Int, String) -> Void) -> CompressionOutcome {
        let files = ImageCollector.collect(from: inputs)
        guard !files.isEmpty else { return CompressionOutcome(summary: "No PNG, JPG, or JPEG files were found.") }

        let maximumJobs = max(1, min(settings.parallelJobs, min(ProcessInfo.processInfo.activeProcessorCount, 12)))
        progress(0, files.count, "Found \(files.count) image(s). Preparing \(maximumJobs) concurrent worker(s)...")

        let state = RunState()
        let queue = OperationQueue()
        queue.name = "com.desmondyong.tinycompressor.workers"
        queue.maxConcurrentOperationCount = maximumJobs

        for (index, job) in files.enumerated() {
            queue.addOperation {
                let started = state.started()
                progress(started.completed, files.count, "Compressing \(index + 1) of \(files.count): \(job.source.lastPathComponent) (\(started.active)/\(maximumJobs) active)")
                let result = compress(job: job, settings: settings)
                let finished = state.finished(result)
                progress(finished.completed, files.count, result.message)
            }
        }
        queue.waitUntilAllOperationsAreFinished()

        let totals = state.totals()
        let bytesSaved = max(0, totals.originalBytes - totals.finalBytes)
        let percent = totals.originalBytes == 0 ? 0 : (Double(bytesSaved) / Double(totals.originalBytes)) * 100
        return CompressionOutcome(summary: "Finished: \(files.count) image(s), \(totals.saved) reduced, \(totals.unchanged) unchanged, \(totals.failed) failed. Saved \(ByteCountFormatter.string(fromByteCount: bytesSaved, countStyle: .file)) (\(String(format: "%.1f", percent))%).")
    }

    private static func compress(job: ImageJob, settings: CompressionSettings) -> FileResult {
        guard let before = fileSize(job.source) else { return .failed(job.source, "Could not read \(job.source.path)") }
        let tools = ToolLocator.availableTools()
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("TinyCompressor-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: temporary) }

        do { try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true) }
        catch { return .failed(job.source, "Could not create temporary workspace for \(job.source.lastPathComponent)") }

        let candidate = temporary.appendingPathComponent(job.source.deletingPathExtension().lastPathComponent + ".candidate." + job.source.pathExtension.lowercased())
        let success: Bool
        switch job.kind {
        case .png:
            success = compressPNG(source: job.source, candidate: candidate, tools: tools, settings: settings)
        case .jpeg:
            success = compressJPEG(source: job.source, candidate: candidate, tools: tools, settings: settings)
        }
        guard success, let after = fileSize(candidate), after < before else {
            return .unchanged(job.source, before, "Kept \(job.source.lastPathComponent) (no smaller result)")
        }

        do {
            let destination: URL
            if settings.replaceOriginals {
                destination = job.source
                if settings.keepBackups {
                    let backup = job.source.appendingPathExtension("bak")
                    try? FileManager.default.removeItem(at: backup)
                    try FileManager.default.copyItem(at: job.source, to: backup)
                }
            } else if let output = settings.outputFolder {
                destination = output.appendingPathComponent(job.relativePath)
                try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            } else {
                return .failed(job.source, "No output folder for \(job.source.lastPathComponent)")
            }

            if settings.replaceOriginals {
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
}

enum ToolLocator {
    static func availableTools() -> CompressionTools {
        CompressionTools(
            pngquant: find("pngquant"),
            zopflipng: find("zopflipng"),
            oxipng: find("oxipng"),
            cjpeg: findMozJPEG(),
            jpegoptim: find("jpegoptim")
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

enum ResultKind { case saved, unchanged, failed }

struct FileResult {
    let kind: ResultKind
    let before: Int64
    let after: Int64
    let message: String

    static func saved(_ source: URL, _ before: Int64, _ after: Int64, _ message: String) -> FileResult {
        FileResult(kind: .saved, before: before, after: after, message: message)
    }
    static func unchanged(_ source: URL, _ before: Int64, _ message: String) -> FileResult {
        FileResult(kind: .unchanged, before: before, after: before, message: message)
    }
    static func failed(_ source: URL, _ message: String) -> FileResult {
        FileResult(kind: .failed, before: 0, after: 0, message: message)
    }
}
