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

    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    @State private var selectedFileURL: URL? = nil
    @State private var isTargeted = false

    @State private var appMode: AppMode = .full
    @State private var isProcessing = false
    @State private var processingPhase: ProcessingPhase = .idle
    @State private var currentStepMessage = "Ready to process"

    @State private var fileDuration: Double? = nil
    @State private var useSegment = false
    @State private var segmentStart: Double = 0
    @State private var segmentEnd: Double = 60
    @State private var waveformSamples: [Float] = []

    @State private var consoleOutput: String = ""
    @State private var showLogs = false

    private let theme = HomeTheme.shared
    private let windowWidth: CGFloat = 900
    private let windowHeight: CGFloat = 540

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 0) {
                leftPanel
                Rectangle()
                    .fill(theme.divider)
                    .frame(width: 1)
                rightPanel
            }

            bottomBar
                .padding(.horizontal, 24)
                .padding(.vertical, 14)
        }
        .frame(minWidth: windowWidth, maxWidth: windowWidth, minHeight: windowHeight, maxHeight: windowHeight)
        .background(theme.background)
        .onAppear {
            NotificationManager.requestAuthorization()
        }
        .sheet(isPresented: onboardingBinding) {
            OnboardingView(isPresented: onboardingBinding)
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
        .onChange(of: appMode) { _, newMode in
            if newMode == .playerOnly {
                selectedFileURL = nil
                resetFileState()
                currentStepMessage = "Open a MIDI file or the empty player."
            } else {
                currentStepMessage = "Drop an audio file to get started."
            }
        }
    }

    private var onboardingBinding: Binding<Bool> {
        Binding(
            get: { !hasCompletedOnboarding },
            set: { if !$0 { hasCompletedOnboarding = true } }
        )
    }

    // MARK: - Layout

    private var leftPanel: some View {
        ScrollView {
            VStack(spacing: 14) {
                ModeCardPicker(selection: $appMode, disabled: isProcessing)

                if appMode == .playerOnly {
                    PlayerModePanel(
                        onOpenMIDI: openMIDIFileSelector,
                        onOpenEmpty: { openPlayer(with: nil) }
                    )
                } else {
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
                        guard !isProcessing else { return false }
                        guard let provider = providers.first else { return false }
                        _ = provider.loadObject(ofClass: URL.self) { url, _ in
                            if let fileURL = url {
                                DispatchQueue.main.async {
                                    self.selectedFileURL = fileURL
                                    self.appendLog("File selected: \(fileURL.path)")
                                }
                            }
                        }
                        return true
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
                }

                RecentFilesSection(
                    audioFiles: recentFiles.audioFiles,
                    midiFiles: recentFiles.midiFiles,
                    onSelectAudio: { url in
                        selectedFileURL = url
                    },
                    onSelectMIDI: { url in
                        recentFiles.addMIDI(url)
                        openPlayer(with: url)
                    }
                )
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 12)
        }
        .frame(minWidth: 400, maxWidth: 400, maxHeight: .infinity)
    }

    private var rightPanel: some View {
        ZStack(alignment: .bottom) {
            Group {
                if isProcessing || processingPhase == .failed || processingPhase == .done {
                    PipelineTimeline(
                        mode: appMode,
                        phase: processingPhase,
                        currentMessage: currentStepMessage
                    )
                } else {
                    ModeInfoPanel(mode: appMode)
                }
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            if showLogs {
                LogsOverlay(text: $consoleOutput, isPresented: $showLogs)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .frame(minWidth: 499, maxWidth: 499, maxHeight: .infinity)
        .animation(.easeInOut(duration: 0.25), value: showLogs)
    }

    private var bottomBar: some View {
        HStack(spacing: 12) {
            if isProcessing {
                ProgressView()
                    .controlSize(.small)
                VStack(alignment: .leading, spacing: 2) {
                    Text(currentStepMessage)
                        .font(.subheadline.weight(.medium))
                    if let duration = fileDuration {
                        Text("estimated time: ~\(estimatedMinutes) min · \(PianissimoFormatters.formatTime(processingDuration(duration))) of audio")
                            .font(.caption)
                            .foregroundStyle(theme.subtleText)
                    }
                }
                Spacer()
                Button(showLogs ? "hide logs" : "show logs") {
                    withAnimation { showLogs.toggle() }
                }
                .buttonStyle(.borderless)
                .font(.caption)
            } else if appMode != .playerOnly, selectedFileURL != nil {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Ready to start")
                        .font(.subheadline.weight(.medium))
                    Text("~\(estimatedMinutes) min estimated")
                        .font(.caption)
                        .foregroundStyle(theme.subtleText)
                }
                Spacer()
                Button("Start") {
                    startProcessing()
                }
                .buttonStyle(.borderedProminent)
                .tint(theme.accent)
                .controlSize(.large)
                .disabled(useSegment && fileDuration == nil)
            } else {
                Text(currentStepMessage)
                    .font(.subheadline)
                    .foregroundStyle(processingPhase == .failed ? .red : theme.subtleText)
                Spacer()
            }
        }
    }

    private var estimatedMinutes: Int {
        PianissimoFormatters.estimatedMinutes(
            duration: fileDuration ?? 0,
            useSegment: useSegment,
            segmentStart: segmentStart,
            segmentEnd: segmentEnd
        )
    }

    private func processingDuration(_ total: Double) -> Double {
        useSegment ? max(0, segmentEnd - segmentStart) : total
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
        openWindow(id: AppModel.playerWindowID)
    }

    func openFileSelector() {
        guard appMode != .playerOnly else { return }
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.audio, .movie]

        if panel.runModal() == .OK, let url = panel.url {
            selectedFileURL = url
            appendLog("File selected: \(url.path)")
        }
    }

    func openMIDIFileSelector() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.midi]
        panel.directoryURL = PianissimoPaths.outputDirectory()

        if panel.runModal() == .OK, let url = panel.url {
            openPlayer(with: url)
        }
    }

    func appendLog(_ text: String) {
        DispatchQueue.main.async {
            consoleOutput += "[\(timestamp())] \(text)\n"
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

        isProcessing = true
        consoleOutput = ""
        showLogs = false
        processingPhase = .preparing
        currentStepMessage = "Preparing..."

        let mode = appMode.engineMode
        let outputDir = PianissimoPaths.outputDirectory()
        let baseName = fileURL.deletingPathExtension().lastPathComponent
        let tempMidiURL = outputDir.appendingPathComponent("\(baseName)_Piano.mid")

        DispatchQueue.global(qos: .userInitiated).async {
            var arguments = [
                scriptURL.path,
                "--mode", mode,
                "--input", fileURL.path,
                "--output-dir", outputDir.path,
                "--resources", engineDir.path
            ]
            if mode != "separate" {
                arguments += ["--output-midi", tempMidiURL.path]
            }
            if self.useSegment {
                arguments += [
                    "--start", String(self.segmentStart),
                    "--end", String(self.segmentEnd)
                ]
            }

            let success = runCommandLine(
                executable: pythonURL.path,
                arguments: arguments,
                currentDirectory: outputDir.path
            )

            DispatchQueue.main.async {
                self.isProcessing = false
                if success {
                    self.showLogs = false
                    NSSound.beep()
                    self.selectedFileURL = nil
                    if mode == "separate" {
                        self.processingPhase = .done
                        self.currentStepMessage = "Separation complete."
                        self.appendLog("Stems available at: \(outputDir.path)")
                        NotificationManager.notify(title: "Pianissimo", body: "Stem separation complete")
                        NSWorkspace.shared.activateFileViewerSelecting([outputDir])
                    } else {
                        self.processingPhase = .saving
                        self.currentStepMessage = "Saving MIDI..."
                        self.appendLog("Processing completed successfully.")
                        NotificationManager.notify(title: "Pianissimo", body: "MIDI transcription complete")
                        let otherStemURL = outputDir.appendingPathComponent("htdemucs/\(baseName)/other.mp3")
                        self.promptSaveMIDI(
                            producedAt: tempMidiURL,
                            suggestedName: "\(baseName)_Piano.mid",
                            companionAudio: FileManager.default.fileExists(atPath: otherStemURL.path) ? otherStemURL : nil
                        )
                    }
                } else {
                    self.processingPhase = .failed
                    self.currentStepMessage = "Processing failed (see console)."
                    self.appendLog("An error occurred. Check the logs.")
                    NotificationManager.notify(title: "Pianissimo", body: "Processing failed")
                    self.showLogs = true
                    self.selectedFileURL = nil
                }
            }
        }
    }

    func promptSaveMIDI(producedAt sourceURL: URL, suggestedName: String, companionAudio: URL? = nil) {
        guard FileManager.default.fileExists(atPath: sourceURL.path) else {
            processingPhase = .failed
            currentStepMessage = "MIDI not found after transcription."
            appendLog("MIDI file not found at expected location: \(sourceURL.path)")
            return
        }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.midi]
        panel.nameFieldStringValue = suggestedName
        panel.directoryURL = PianissimoPaths.outputDirectory()
        panel.canCreateDirectories = true
        panel.title = "Save MIDI score"
        panel.message = "Choose where to save your MIDI file (the audio stem will be saved alongside it)."

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
                    appendLog("Audio stem saved to: \(audioDest.path)")
                    currentStepMessage = "Saved: \(destinationURL.lastPathComponent) + \(audioDest.lastPathComponent)"
                } else {
                    currentStepMessage = "Saved: \(destinationURL.lastPathComponent)"
                }

                processingPhase = .done
                if appMode.opensPlayerOnSuccess {
                    openPlayer(with: destinationURL)
                }
            } catch {
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

    func runCommandLine(executable: String, arguments: [String], currentDirectory: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.currentDirectoryURL = URL(fileURLWithPath: currentDirectory)

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

        fileHandle.readabilityHandler = { handle in
            let data = handle.availableData
            if let output = String(data: data, encoding: .utf8), !output.isEmpty {
                DispatchQueue.main.async {
                    self.consoleOutput += output
                    for line in output.split(whereSeparator: { $0 == "\n" || $0 == "\r" }) {
                        if let range = line.range(of: "STEP:") {
                            let message = String(line[range.upperBound...])
                            self.currentStepMessage = message
                            self.updatePhase(from: message)
                        }
                    }
                }
            }
        }

        do {
            try process.run()
            process.waitUntilExit()
            fileHandle.readabilityHandler = nil
            return process.terminationStatus == 0
        } catch {
            fileHandle.readabilityHandler = nil
            appendLog("System error: Could not launch process. Detail: \(error.localizedDescription)")
            return false
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AppModel())
        .environmentObject(RecentFilesStore())
}
