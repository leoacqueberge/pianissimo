//
//  ContentView.swift
//  Pianissimo
//

import SwiftUI
import UniformTypeIdentifiers
import AVFoundation

struct ContentView: View {
    @EnvironmentObject private var appModel: AppModel
    @EnvironmentObject private var recentFiles: RecentFilesStore
    @Environment(\.openWindow) private var openWindow
    @Environment(\.colorScheme) private var colorScheme

    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    @State private var selectedFileURL: URL? = nil
    @State private var isTargeted = false

    @State private var appMode: AppMode = .mixedTrack
    @State private var isProcessing = false
    @State private var processingPhase: ProcessingPhase = .idle
    @State private var lastWorkingPhase: ProcessingPhase = .preparing
    @State private var currentStepMessage = "Drop an audio file to get started."

    @State private var fileDuration: Double? = nil
    @State private var useSegment = false
    @State private var segmentStart: Double = 0
    @State private var segmentEnd: Double = 60
    @State private var waveformSamples: [Float] = []

    @State private var consoleOutput: String = ""
    @State private var showLogs = false

    @State private var pipelineRunner = PipelineRunner()

    private var theme: HomeTheme { HomeTheme(isDark: colorScheme == .dark) }

    private var showsPipeline: Bool {
        isProcessing
            || processingPhase == .failed
            || processingPhase == .done
            || processingPhase == .saving
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .bottom) {
                ScrollView {
                    VStack(spacing: 14) {
                        if showsPipeline {
                            pipelineContent
                        } else {
                            idleContent
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 12)
                }
                .scrollContentBackground(.hidden)

                if showLogs {
                    LogsOverlay(text: $consoleOutput, isPresented: $showLogs)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 8)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(.easeInOut(duration: 0.25), value: showLogs)

            if isProcessing {
                processingBar
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
            }

            HStack {
                Spacer(minLength: 0)
                PrivacyChip()
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)
            .padding(.top, 4)
            .padding(.bottom, 16)
        }
        .frame(minWidth: 440, minHeight: 560)
        .background(theme.background)
        .containerBackground(theme.background, for: .window)
        .environment(\.homeTheme, theme)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                SettingsLink {
                    Label("Settings", systemImage: "gearshape")
                }
                .help("Settings")
            }
        }
        .onAppear {
            recentFiles.refresh()
        }
        .sheet(isPresented: onboardingBinding) {
            OnboardingView(isPresented: onboardingBinding)
                .environment(\.homeTheme, theme)
        }
        .onChange(of: selectedFileURL) { _, newURL in
            if let url = newURL {
                loadAudioDuration(from: url)
                loadWaveform(from: url)
                recentFiles.addAudio(url)
            } else {
                resetFileState()
            }
        }
        .onChange(of: useSegment) { _, enabled in
            guard enabled, let duration = fileDuration else { return }
            clampSegment(to: duration)
        }
    }

    private var onboardingBinding: Binding<Bool> {
        Binding(
            get: { !hasCompletedOnboarding },
            set: { if !$0 { hasCompletedOnboarding = true } }
        )
    }

    // MARK: - Layout

    private var idleContent: some View {
        VStack(spacing: 14) {
            ModeCardPicker(
                selection: $appMode,
                disabled: isProcessing,
                onOpenPlayer: openPlayerWindow
            )

            AudioDropzone(
                selectedFileURL: selectedFileURL,
                fileDuration: fileDuration,
                isTargeted: isTargeted,
                isProcessing: isProcessing,
                useSegment: useSegment,
                segmentStart: segmentStart,
                segmentEnd: segmentEnd,
                onTap: openFileSelector
            )
            .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
                handleFileDrop(providers)
            }

            if selectedFileURL != nil, !isProcessing, let duration = fileDuration {
                AudioSegmentEditor(
                    duration: duration,
                    useSegment: $useSegment,
                    start: $segmentStart,
                    end: $segmentEnd,
                    waveform: waveformSamples,
                    estimatedMinutes: estimatedMinutes
                )
            }

            if selectedFileURL != nil {
                startButton
            }
        }
    }

    private var pipelineContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let selectedFileURL {
                Text(selectedFileURL.lastPathComponent)
                    .font(.caption)
                    .foregroundStyle(theme.subtleText)
                    .lineLimit(1)
            }

            PipelineTimeline(
                mode: appMode,
                phase: processingPhase,
                failedAt: lastWorkingPhase,
                currentMessage: currentStepMessage
            )

            if !isProcessing {
                if processingPhase == .failed {
                    Button {
                        startProcessing()
                    } label: {
                        Text("Try again")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(theme.accent)
                    .controlSize(.large)
                    .disabled(selectedFileURL == nil)

                    Button("Choose another file") {
                        returnToIdle(clearFile: true)
                    }
                    .buttonStyle(.borderless)
                    .frame(maxWidth: .infinity)
                    .foregroundStyle(theme.subtleText)
                } else if processingPhase == .done {
                    Button("Start over") {
                        returnToIdle(clearFile: true)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var startButton: some View {
        VStack(spacing: 8) {
            Button {
                startProcessing()
            } label: {
                Text("Start")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(theme.accent)
            .controlSize(.large)
            .disabled(useSegment && (fileDuration == nil || segmentEnd - segmentStart < SegmentLimits.minDuration))

            Text("About \(estimatedMinutes) min")
                .font(.caption)
                .foregroundStyle(theme.subtleText)
        }
    }

    private var processingBar: some View {
        HStack(spacing: 12) {
            ProgressView()
                .controlSize(.small)
            VStack(alignment: .leading, spacing: 2) {
                Text(currentStepMessage)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(theme.text)
                if let duration = fileDuration {
                    Text("Estimated time: ~\(estimatedMinutes) min · \(PianissimoFormatters.formatTime(processingDuration(duration))) of audio")
                        .font(.caption)
                        .foregroundStyle(theme.subtleText)
                }
            }
            Spacer()
            Button(showLogs ? "Hide logs" : "Show logs") {
                withAnimation { showLogs.toggle() }
            }
            .buttonStyle(.borderless)
            .font(.caption)
            Button("Cancel") {
                pipelineRunner.cancel()
                currentStepMessage = "Cancelling…"
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .tint(.red)
        }
        .background(theme.background)
    }

    private func returnToIdle(clearFile: Bool) {
        processingPhase = .idle
        showLogs = false
        currentStepMessage = "Drop an audio file to get started."
        if clearFile {
            selectedFileURL = nil
            resetFileState()
        }
    }

    private var estimatedMinutes: Int {
        PianissimoFormatters.estimatedMinutes(
            duration: fileDuration ?? 0,
            useSegment: useSegment,
            segmentStart: segmentStart,
            segmentEnd: segmentEnd,
            isolatesPiano: appMode.isolatesPiano
        )
    }

    private func processingDuration(_ total: Double) -> Double {
        useSegment ? max(0, segmentEnd - segmentStart) : total
    }

    private func clampSegment(to duration: Double) {
        let minLen = SegmentLimits.minDuration
        segmentStart = min(max(0, segmentStart), max(0, duration - minLen))
        segmentEnd = min(max(segmentStart + minLen, segmentEnd), duration)
        if segmentEnd - segmentStart < minLen {
            segmentEnd = min(duration, segmentStart + minLen)
        }
    }

    private func resetFileState() {
        fileDuration = nil
        useSegment = false
        segmentStart = 0
        segmentEnd = 60
        waveformSamples = []
    }

    private func loadWaveform(from url: URL) {
        Task {
            let samples = await WaveformSampler.loadSamples(from: url)
            await MainActor.run {
                waveformSamples = samples
            }
        }
    }

    private func loadAudioDuration(from url: URL) {
        let asset = AVURLAsset(url: url)
        Task {
            do {
                let time = try await asset.load(.duration)
                let seconds = CMTimeGetSeconds(time)
                await MainActor.run {
                    if seconds.isFinite, seconds > 0 {
                        fileDuration = seconds
                        segmentStart = 0
                        segmentEnd = min(60, seconds)
                        clampSegment(to: seconds)
                        processingPhase = .idle
                        currentStepMessage = "Ready — set the portion, then start"
                    } else {
                        fileDuration = nil
                    }
                }
            } catch {
                await MainActor.run {
                    fileDuration = nil
                    appendLog("Could not read file duration.")
                }
            }
        }
    }

    func openPlayer(with url: URL?) {
        if let url { recentFiles.addMIDI(url) }
        appModel.playerURL = url
        openWindow(id: AppModel.playerWindowID, value: MIDIPlayerWindow.main)
    }

    func openPlayerWindow() {
        openWindow(id: AppModel.playerWindowID, value: MIDIPlayerWindow.main)
    }

    /// Drop : un .mid/.midi ouvre le lecteur ; sinon le fichier est pris comme audio source.
    func handleFileDrop(_ providers: [NSItemProvider]) -> Bool {
        guard !isProcessing else { return false }
        guard let provider = providers.first else { return false }
        _ = provider.loadObject(ofClass: URL.self) { url, _ in
            guard let fileURL = url else { return }
            DispatchQueue.main.async {
                self.ingestDroppedFile(fileURL)
            }
        }
        return true
    }

    func ingestDroppedFile(_ fileURL: URL) {
        if Self.isMIDIFile(fileURL) {
            appendLog("MIDI dropped — opening player: \(fileURL.path)")
            openPlayer(with: fileURL)
            return
        }

        selectedFileURL = fileURL
        appendLog("File selected: \(fileURL.path)")
    }

    static func isMIDIFile(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        if ext == "mid" || ext == "midi" { return true }
        if let type = UTType(filenameExtension: ext), type.conforms(to: .midi) {
            return true
        }
        return false
    }

    func openFileSelector() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.audio, .movie]

        if panel.runModal() == .OK, let url = panel.url {
            selectedFileURL = url
            appendLog("File selected: \(url.path)")
        }
    }

    func appendLog(_ text: String) {
        DispatchQueue.main.async {
            consoleOutput += "[\(timestamp())] \(text)\n"
        }
    }

    private func appendEngineOutput(_ output: String) {
        consoleOutput += output
        for line in output.split(whereSeparator: { $0 == "\n" || $0 == "\r" }) {
            if let range = line.range(of: "STEP:") {
                let message = String(line[range.upperBound...])
                currentStepMessage = message
                updatePhase(from: message)
            }
        }
    }

    private func timestamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f.string(from: Date())
    }

    private func updatePhase(from message: String) {
        let lower = message.lowercased()
        if lower.contains("step 1") || lower.contains("separat") || lower.contains("isol") {
            processingPhase = .separating
        } else if lower.contains("step 2") || lower.contains("transcr") {
            processingPhase = .transcribing
        } else if lower.contains("prepar") {
            processingPhase = .preparing
        }
    }

    // MARK: - Processing

    func startProcessing() {
        guard appMode != .playerOnly else { return }
        guard let fileURL = selectedFileURL else { return }
        guard !isProcessing else { return }
        if useSegment {
            guard let duration = fileDuration else { return }
            let segmentLength = segmentEnd - segmentStart
            guard segmentLength >= SegmentLimits.minDuration else {
                appendLog("Segment too short — select at least \(Int(SegmentLimits.minDuration)) seconds.")
                currentStepMessage = "Segment too short (min \(Int(SegmentLimits.minDuration)) s)."
                return
            }
            guard segmentStart >= 0, segmentEnd <= duration, segmentStart < segmentEnd else {
                appendLog("Invalid segment range.")
                currentStepMessage = "Invalid segment range."
                return
            }
        }
        guard let resourceURL = Bundle.main.resourceURL else {
            appendLog("Application resources not found.")
            return
        }

        let engineDir = resourceURL.appendingPathComponent("engine")
        let pythonURL = engineDir.appendingPathComponent("runtime/python/bin/python3.11")
        let scriptURL = engineDir.appendingPathComponent("engine.py")

        guard FileManager.default.fileExists(atPath: pythonURL.path),
              FileManager.default.fileExists(atPath: scriptURL.path) else {
            appendLog("Embedded engine not found in the application.")
            appendLog("Expected Python at: \(pythonURL.path)")
            return
        }

        NotificationManager.requestAuthorization()

        isProcessing = true
        consoleOutput = ""
        showLogs = false
        processingPhase = .preparing
        lastWorkingPhase = .preparing
        currentStepMessage = "Preparing…"

        let mode = appMode.engineMode
        let outputDir = PianissimoPaths.outputDirectory()
        let baseName = fileURL.deletingPathExtension().lastPathComponent
        let tempMidiURL = outputDir.appendingPathComponent("\(baseName)_Piano.mid")
        let expectsStem = appMode.isolatesPiano
        let request = PipelineRequest(
            pythonURL: pythonURL,
            scriptURL: scriptURL,
            inputURL: fileURL,
            outputDir: outputDir,
            outputMIDI: mode == "separate" ? nil : tempMidiURL,
            resourcesURL: engineDir,
            mode: mode,
            start: useSegment ? segmentStart : nil,
            end: useSegment ? segmentEnd : nil
        )

        let runner = pipelineRunner
        runner.onOutput = { output in
            DispatchQueue.main.async {
                self.appendEngineOutput(output)
            }
        }

        DispatchQueue.global(qos: .userInitiated).async {
            let outcome = runner.run(request)
            DispatchQueue.main.async {
                self.finishProcessing(
                    outcome,
                    mode: mode,
                    outputDir: outputDir,
                    tempMidiURL: tempMidiURL,
                    baseName: baseName,
                    expectsStem: expectsStem
                )
            }
        }
    }

    private func finishProcessing(
        _ outcome: PipelineOutcome,
        mode: String,
        outputDir: URL,
        tempMidiURL: URL,
        baseName: String,
        expectsStem: Bool
    ) {
        isProcessing = false
        cleanupTrimFolder(in: outputDir)

        switch outcome {
        case .cancelled:
            processingPhase = .idle
            currentStepMessage = "Cancelled. Your file is still ready to run."
            appendLog("Processing cancelled.")
            showLogs = false
        case .failure:
            lastWorkingPhase = processingPhase == .idle ? .preparing : processingPhase
            processingPhase = .failed
            currentStepMessage = "Processing failed (see console)."
            appendLog("An error occurred. Check the logs.")
            NotificationManager.notify(title: "Pianissimo", body: "Processing failed")
            showLogs = true
        case .success:
            showLogs = false
            NSSound.beep()
            if mode == "separate" {
                processingPhase = .done
                currentStepMessage = "Separation complete."
                appendLog("Stems available at: \(outputDir.path)")
                NotificationManager.notify(title: "Pianissimo", body: "Stem separation complete")
                NSWorkspace.shared.activateFileViewerSelecting([outputDir])
            } else {
                processingPhase = .saving
                currentStepMessage = "Saving MIDI…"
                appendLog("Processing completed successfully.")
                NotificationManager.notify(title: "Pianissimo", body: "MIDI transcription complete")
                let companion = expectsStem ? Self.findPianoStem(outputDir: outputDir, baseName: baseName) : nil
                promptSaveMIDI(
                    producedAt: tempMidiURL,
                    suggestedName: "\(baseName)_Piano.mid",
                    companionAudio: companion
                )
            }
        }
    }

    static func findPianoStem(outputDir: URL, baseName: String) -> URL? {
        let candidates = [
            outputDir.appendingPathComponent("htdemucs_6s/\(baseName)/piano.mp3"),
            outputDir.appendingPathComponent("htdemucs/\(baseName)/piano.mp3"),
            outputDir.appendingPathComponent("htdemucs/\(baseName)/other.mp3")
        ]
        return candidates.first { FileManager.default.fileExists(atPath: $0.path) }
    }

    private func cleanupTrimFolder(in outputDir: URL) {
        let trim = outputDir.appendingPathComponent("_trim", isDirectory: true)
        try? FileManager.default.removeItem(at: trim)
    }

    func promptSaveMIDI(producedAt sourceURL: URL, suggestedName: String, companionAudio: URL? = nil) {
        guard FileManager.default.fileExists(atPath: sourceURL.path) else {
            lastWorkingPhase = .saving
            processingPhase = .failed
            currentStepMessage = "MIDI not found after transcription."
            appendLog("MIDI file not found at expected location: \(sourceURL.path)")
            return
        }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.midi]
        panel.nameFieldStringValue = suggestedName
        panel.directoryURL = PianissimoPaths.musicDirectory
        panel.canCreateDirectories = true
        panel.title = "Save MIDI score"
        panel.message = companionAudio == nil
            ? "Choose where to save your MIDI file."
            : "Choose where to save your MIDI file (the piano stem will be saved alongside it)."

        if panel.runModal() == .OK, let destinationURL = panel.url {
            do {
                if FileManager.default.fileExists(atPath: destinationURL.path) {
                    try FileManager.default.removeItem(at: destinationURL)
                }
                try FileManager.default.moveItem(at: sourceURL, to: destinationURL)
                recentFiles.addMIDI(destinationURL)
                appendLog("MIDI saved to: \(destinationURL.path)")

                if let audioURL = companionAudio,
                   FileManager.default.fileExists(atPath: audioURL.path) {
                    let audioDest = destinationURL.deletingPathExtension().appendingPathExtension("mp3")
                    if FileManager.default.fileExists(atPath: audioDest.path) {
                        try FileManager.default.removeItem(at: audioDest)
                    }
                    try FileManager.default.copyItem(at: audioURL, to: audioDest)
                    appendLog("Piano stem saved to: \(audioDest.path)")
                    currentStepMessage = "Saved: \(destinationURL.lastPathComponent) + \(audioDest.lastPathComponent)"
                } else {
                    currentStepMessage = "Saved: \(destinationURL.lastPathComponent)"
                }

                processingPhase = .done
                if appMode.opensPlayerOnSuccess {
                    openPlayer(with: destinationURL)
                }
            } catch {
                lastWorkingPhase = .saving
                processingPhase = .failed
                currentStepMessage = "Could not save file."
                appendLog("Save error: \(error.localizedDescription)")
            }
        } else {
            processingPhase = .done
            currentStepMessage = "Transcription complete (save cancelled)."
            appendLog("Save cancelled. MIDI remains at: \(sourceURL.path)")
            if appMode.opensPlayerOnSuccess {
                openPlayer(with: sourceURL)
            }
        }
    }
}

// MARK: - Embedded Python runner

struct PipelineRequest: Sendable {
    var pythonURL: URL
    var scriptURL: URL
    var inputURL: URL
    var outputDir: URL
    var outputMIDI: URL?
    var resourcesURL: URL
    var mode: String
    var start: Double?
    var end: Double?
}

enum PipelineOutcome: Sendable {
    case success
    case failure
    case cancelled
}

/// Runs the bundled Python engine off the main thread and supports cancel.
final class PipelineRunner: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var cancelled = false

    var onOutput: (@Sendable (String) -> Void)?

    func cancel() {
        lock.lock()
        cancelled = true
        process?.terminate()
        lock.unlock()
    }

    func run(_ request: PipelineRequest) -> PipelineOutcome {
        lock.lock()
        cancelled = false
        lock.unlock()

        var arguments = [
            request.scriptURL.path,
            "--mode", request.mode,
            "--input", request.inputURL.path,
            "--output-dir", request.outputDir.path,
            "--resources", request.resourcesURL.path
        ]
        if let midi = request.outputMIDI, request.mode != "separate" {
            arguments += ["--output-midi", midi.path]
        }
        if let start = request.start, let end = request.end {
            arguments += ["--start", String(start), "--end", String(end)]
        }

        let process = Process()
        process.executableURL = request.pythonURL
        process.arguments = arguments
        process.currentDirectoryURL = request.outputDir

        var env = ProcessInfo.processInfo.environment
        env.removeValue(forKey: "PYTHONHOME")
        env.removeValue(forKey: "PYTHONPATH")
        env.removeValue(forKey: "PYTHONSTARTUP")
        env["PYTHONDONTWRITEBYTECODE"] = "1"
        env["PYTHONUNBUFFERED"] = "1"
        process.environment = env

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        let fileHandle = pipe.fileHandleForReading

        fileHandle.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let output = String(data: data, encoding: .utf8), !output.isEmpty else {
                return
            }
            self?.onOutput?(output)
        }

        lock.lock()
        self.process = process
        if cancelled {
            lock.unlock()
            fileHandle.readabilityHandler = nil
            return .cancelled
        }
        lock.unlock()

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            fileHandle.readabilityHandler = nil
            onOutput?("System error: could not launch process. \(error.localizedDescription)\n")
            return isCancelled ? .cancelled : .failure
        }

        fileHandle.readabilityHandler = nil
        drainRemaining(fileHandle)

        lock.lock()
        self.process = nil
        let wasCancelled = cancelled
        lock.unlock()

        if wasCancelled || process.terminationReason == .uncaughtSignal {
            return .cancelled
        }
        return process.terminationStatus == 0 ? .success : .failure
    }

    private var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    private func drainRemaining(_ handle: FileHandle) {
        let data = handle.readDataToEndOfFile()
        if !data.isEmpty, let output = String(data: data, encoding: .utf8), !output.isEmpty {
            onOutput?(output)
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AppModel())
        .environmentObject(RecentFilesStore())
}
