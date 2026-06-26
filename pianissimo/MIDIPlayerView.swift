//
//  MIDIPlayerView.swift
//  Pianissimo
//
//  Lecteur MIDI "piano roll" : barre d'outils en haut, notes qui tombent sur
//  un clavier 88 touches, et timeline en bas. Thème clair par défaut avec
//  bascule sombre. Raccourcis : espace = play/pause, flèches = ±1 s.
//

import SwiftUI
import UniformTypeIdentifiers
import AppKit

// MARK: - Géométrie du clavier

/// Calcule la position de chaque touche d'un piano 88 touches (La0 -> Do8).
struct KeyboardLayout {
    static let minPitch = 21   // A0
    static let maxPitch = 108  // C8
    private static let whiteClasses: Set<Int> = [0, 2, 4, 5, 7, 9, 11]

    let whiteWidth: CGFloat
    let blackWidth: CGFloat
    private let whiteIndex: [Int: Int]   // pitch -> rang de touche blanche
    let whiteCount: Int

    init(totalWidth: CGFloat) {
        var index: [Int: Int] = [:]
        var counter = 0
        for pitch in KeyboardLayout.minPitch...KeyboardLayout.maxPitch
        where KeyboardLayout.whiteClasses.contains(pitch % 12) {
            index[pitch] = counter
            counter += 1
        }
        whiteIndex = index
        whiteCount = max(counter, 1)
        whiteWidth = totalWidth / CGFloat(whiteCount)
        blackWidth = whiteWidth * 0.62
    }

    static func isWhite(_ pitch: Int) -> Bool { whiteClasses.contains(pitch % 12) }

    func centerX(_ pitch: Int) -> CGFloat {
        if KeyboardLayout.isWhite(pitch) {
            let i = whiteIndex[pitch] ?? 0
            return (CGFloat(i) + 0.5) * whiteWidth
        } else {
            let lower = whiteIndex[pitch - 1] ?? 0
            return (CGFloat(lower) + 1.0) * whiteWidth
        }
    }

    func leftEdge(_ pitch: Int) -> CGFloat {
        centerX(pitch) - whiteWidth / 2
    }

    func noteWidth(_ pitch: Int) -> CGFloat {
        KeyboardLayout.isWhite(pitch) ? whiteWidth * 0.86 : blackWidth * 0.92
    }
}

// MARK: - Palette de couleurs (clair / sombre)

struct PianoPalette {
    var background: Color
    var toolbarBg: Color
    var toolbarBorder: Color
    var stageBg: Color
    var gridLine: Color
    var whiteKey: Color
    var blackKey: Color
    var keyBorder: Color
    var text: Color
    var subtleText: Color
    var accent: Color
    var noteWhite: Color
    var noteBlack: Color
    var activeKey: Color
    var sliderTint: Color

    static let light = PianoPalette(
        background: Color(red: 0.98, green: 0.98, blue: 0.98),
        toolbarBg: Color.white,
        toolbarBorder: Color.black.opacity(0.08),
        stageBg: Color(red: 0.985, green: 0.985, blue: 0.99),
        gridLine: Color.black.opacity(0.06),
        whiteKey: Color.white,
        blackKey: Color(red: 0.18, green: 0.20, blue: 0.26),
        keyBorder: Color.black.opacity(0.12),
        text: Color(red: 0.13, green: 0.14, blue: 0.17),
        subtleText: Color.black.opacity(0.4),
        accent: Color(red: 0.20, green: 0.45, blue: 0.95),
        noteWhite: Color(red: 0.26, green: 0.52, blue: 0.96),
        noteBlack: Color(red: 0.45, green: 0.40, blue: 0.92),
        activeKey: Color(red: 0.30, green: 0.55, blue: 0.98),
        sliderTint: Color(red: 0.20, green: 0.45, blue: 0.95)
    )

    static let dark = PianoPalette(
        background: Color(red: 0.07, green: 0.07, blue: 0.09),
        toolbarBg: Color(red: 0.11, green: 0.11, blue: 0.14),
        toolbarBorder: Color.white.opacity(0.08),
        stageBg: Color(red: 0.09, green: 0.09, blue: 0.12),
        gridLine: Color.white.opacity(0.06),
        whiteKey: Color(red: 0.93, green: 0.93, blue: 0.95),
        blackKey: Color(red: 0.10, green: 0.11, blue: 0.15),
        keyBorder: Color.black.opacity(0.4),
        text: Color.white.opacity(0.92),
        subtleText: Color.white.opacity(0.4),
        accent: Color(red: 0.40, green: 0.65, blue: 1.0),
        noteWhite: Color(red: 0.35, green: 0.60, blue: 1.0),
        noteBlack: Color(red: 0.58, green: 0.50, blue: 1.0),
        activeKey: Color(red: 0.45, green: 0.70, blue: 1.0),
        sliderTint: Color(red: 0.40, green: 0.65, blue: 1.0)
    )
}

// MARK: - Vue principale

struct MIDIPlayerView: View {
    @StateObject private var engine = MIDIPlayerEngine()
    let url: URL?
    var onClose: () -> Void

    @State private var isDark = false
    @State private var showGrid = false

    private let rates: [Float] = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0]
    private var palette: PianoPalette { isDark ? .dark : .light }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            stage
            timeline
        }
        .frame(minWidth: 760, minHeight: 520)
        .background(palette.background)
        .background(keyboardShortcuts)
        .onAppear {
            if let url, engine.sourceURL != url { engine.load(url: url) }
        }
        .onChange(of: url) { _, newURL in
            if let newURL, engine.sourceURL != newURL { engine.load(url: newURL) }
        }
    }

    // MARK: Raccourcis clavier (espace, flèches)

    private var keyboardShortcuts: some View {
        ZStack {
            Button("") { engine.togglePlay() }
                .keyboardShortcut(.space, modifiers: [])
            Button("") { engine.seek(to: engine.currentTime - 1) }
                .keyboardShortcut(.leftArrow, modifiers: [])
            Button("") { engine.seek(to: engine.currentTime + 1) }
                .keyboardShortcut(.rightArrow, modifiers: [])
        }
        .opacity(0)
        .frame(width: 0, height: 0)
    }

    // MARK: Barre d'outils

    private var toolbar: some View {
        HStack(spacing: 10) {
            Spacer()

            iconButton("square.and.arrow.up", help: "Open a .mid file") { openMIDIFile() }

            iconButton(engine.isPlaying ? "pause.fill" : "play.fill",
                       help: "Play / Pause",
                       disabled: engine.notes.isEmpty) {
                engine.togglePlay()
            }

            iconButton("stop.fill", help: "Stop", disabled: engine.notes.isEmpty) {
                engine.stop()
            }

            iconButton("square.and.arrow.down", help: "Export a copy",
                       disabled: engine.sourceURL == nil) {
                exportMIDI()
            }

            Divider().frame(height: 18).overlay(palette.toolbarBorder)

            // grid: off / on
            Button { showGrid.toggle() } label: {
                Text("grid: \(showGrid ? "on" : "off")")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(showGrid ? palette.accent : palette.subtleText)
            }
            .buttonStyle(.plain)
            .help("Show rhythm grid")

            // loop
            iconButton("repeat", help: "Loop playback",
                       active: engine.isLooping) {
                engine.isLooping.toggle()
            }

            // vitesse
            Menu {
                ForEach(rates, id: \.self) { r in
                    Button {
                        engine.rate = r
                    } label: {
                        if engine.rate == r { Label(rateLabel(r), systemImage: "checkmark") }
                        else { Text(rateLabel(r)) }
                    }
                }
            } label: {
                Text(rateLabel(engine.rate))
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(palette.text)
                    .frame(minWidth: 28)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Playback speed")

            Divider().frame(height: 18).overlay(palette.toolbarBorder)

            // volume
            HStack(spacing: 6) {
                Text("volume")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(palette.subtleText)
                Slider(value: $engine.volume, in: 0...1)
                    .frame(width: 80)
                    .tint(palette.sliderTint)
                iconButton(engine.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                           help: "Mute", active: engine.isMuted) {
                    engine.isMuted.toggle()
                }
            }

            // thème
            iconButton(isDark ? "sun.max.fill" : "moon.fill",
                       help: "Light / dark theme") {
                withAnimation(.easeInOut(duration: 0.2)) { isDark.toggle() }
            }

            // fermer
            iconButton("xmark", help: "Close player") {
                engine.stop()
                onClose()
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 46)
        .background(palette.toolbarBg)
        .overlay(alignment: .bottom) {
            Rectangle().fill(palette.toolbarBorder).frame(height: 1)
        }
    }

    private func iconButton(_ systemName: String, help: String,
                            disabled: Bool = false, active: Bool = false,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 13))
                .frame(width: 26, height: 26)
                .foregroundColor(active ? palette.accent
                                 : (disabled ? palette.subtleText.opacity(0.5) : palette.text))
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(active ? palette.accent.opacity(0.12) : Color.clear)
                )
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .help(help)
    }

    // MARK: Stage (notes qui tombent + clavier + labels)

    private var stage: some View {
        ZStack {
            TimelineView(.animation) { _ in
                Canvas { context, size in
                    drawScene(context: &context, size: size)
                }
            }

            if engine.notes.isEmpty {
                VStack {
                    placeholderCard
                        .padding(.top, 48)
                    Spacer()
                }
            } else {
                // Capture du défilement vertical pour naviguer dans le temps.
                ScrollWheelCatcher(onScroll: handleScroll)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Convertit un défilement vertical en navigation temporelle (seek).
    private func handleScroll(_ deltaY: CGFloat, precise: Bool) {
        guard engine.duration > 0 else { return }
        // Trackpad (deltas précis) : pas fin. Molette souris : pas plus large.
        let factor = precise ? 0.010 : 0.12
        let newTime = engine.currentTime + Double(deltaY) * factor
        engine.seek(to: newTime)
    }

    private var placeholderCard: some View {
        VStack(spacing: 6) {
            Text("click, drag or drop a midi file")
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundColor(palette.text)
            Text("supported: .mid, .midi")
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(palette.subtleText)
        }
        .padding(.horizontal, 36)
        .padding(.vertical, 26)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(palette.toolbarBg.opacity(0.9))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(palette.toolbarBorder, lineWidth: 1)
                )
        )
        .contentShape(Rectangle())
        .onTapGesture { openMIDIFile() }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            handleDrop(providers)
        }
    }

    private func drawScene(context: inout GraphicsContext, size: CGSize) {
        let labelHeight: CGFloat = 16
        let keyboardHeight: CGFloat = min(120, max(90, size.height * 0.24))
        let stageHeight = size.height - keyboardHeight - labelHeight
        let layout = KeyboardLayout(totalWidth: size.width)
        let t = engine.currentTime
        let lookAhead = 4.0
        let pps = stageHeight / lookAhead

        // Fond de la scène
        context.fill(Path(CGRect(x: 0, y: 0, width: size.width, height: stageHeight)),
                     with: .color(palette.stageBg))

        // Lignes verticales d'octaves (chaque Do) + repère léger
        for pitch in stride(from: 24, through: 108, by: 12) {
            let x = layout.leftEdge(pitch)
            context.stroke(Path { p in
                p.move(to: CGPoint(x: x, y: 0))
                p.addLine(to: CGPoint(x: x, y: stageHeight))
            }, with: .color(palette.gridLine), lineWidth: 1)
        }

        // Grille rythmique horizontale (optionnelle)
        if showGrid {
            for i in 0...Int(lookAhead) + 1 {
                let lineTime = floor(t) + Double(i)
                let y = stageHeight - (lineTime - t) * pps
                if y >= 0, y <= stageHeight {
                    context.stroke(Path { p in
                        p.move(to: CGPoint(x: 0, y: y))
                        p.addLine(to: CGPoint(x: size.width, y: y))
                    }, with: .color(palette.gridLine), lineWidth: 1)
                }
            }
        }

        // Notes qui tombent
        var activePitches = Set<Int>()
        for note in engine.notes {
            let topY = stageHeight - (note.end - t) * pps
            let botY = stageHeight - (note.start - t) * pps
            if botY < 0 || topY > stageHeight { continue }

            let isActive = note.start <= t && t <= note.end
            if isActive { activePitches.insert(note.pitch) }

            let isWhite = KeyboardLayout.isWhite(note.pitch)
            let w = layout.noteWidth(note.pitch)
            let x = layout.centerX(note.pitch) - w / 2
            let clampedTop = max(0, topY)
            let clampedBot = min(stageHeight, botY)
            let h = max(2, clampedBot - clampedTop)

            let rect = CGRect(x: x, y: clampedTop, width: w, height: h)
            let path = Path(roundedRect: rect, cornerRadius: min(4, w / 3))

            let base = isActive ? palette.activeKey : (isWhite ? palette.noteWhite : palette.noteBlack)
            let intensity = 0.6 + Double(note.velocity) / 127.0 * 0.4
            context.fill(path, with: .color(base.opacity(intensity)))
            if isActive {
                context.stroke(path, with: .color(palette.accent), lineWidth: 1.5)
            }
        }

        // Ligne de frappe
        context.fill(Path(CGRect(x: 0, y: stageHeight - 1.5, width: size.width, height: 1.5)),
                     with: .color(palette.accent.opacity(0.5)))

        drawKeyboard(context: &context, size: size, stageHeight: stageHeight,
                     keyboardHeight: keyboardHeight, layout: layout,
                     activePitches: activePitches)

        drawOctaveLabels(context: &context, size: size,
                         keyboardBottom: stageHeight + keyboardHeight,
                         layout: layout)
    }

    private func drawKeyboard(context: inout GraphicsContext, size: CGSize,
                              stageHeight: CGFloat, keyboardHeight: CGFloat,
                              layout: KeyboardLayout, activePitches: Set<Int>) {
        let top = stageHeight

        for pitch in KeyboardLayout.minPitch...KeyboardLayout.maxPitch
        where KeyboardLayout.isWhite(pitch) {
            let x = layout.leftEdge(pitch)
            let rect = CGRect(x: x, y: top, width: layout.whiteWidth - 1, height: keyboardHeight)
            let isActive = activePitches.contains(pitch)
            context.fill(Path(rect), with: .color(isActive ? palette.activeKey : palette.whiteKey))
            context.stroke(Path(rect), with: .color(palette.keyBorder), lineWidth: 0.5)
        }

        let blackHeight = keyboardHeight * 0.62
        for pitch in KeyboardLayout.minPitch...KeyboardLayout.maxPitch
        where !KeyboardLayout.isWhite(pitch) {
            let x = layout.centerX(pitch) - layout.blackWidth / 2
            let rect = CGRect(x: x, y: top, width: layout.blackWidth, height: blackHeight)
            let isActive = activePitches.contains(pitch)
            let path = Path(roundedRect: rect, cornerRadius: 2)
            context.fill(path, with: .color(isActive ? palette.activeKey : palette.blackKey))
        }
    }

    private func drawOctaveLabels(context: inout GraphicsContext, size: CGSize,
                                  keyboardBottom: CGFloat, layout: KeyboardLayout) {
        for (i, pitch) in stride(from: 24, through: 108, by: 12).enumerated() {
            let x = layout.centerX(pitch)
            let text = Text("C\(i + 1)")
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(palette.subtleText)
            context.draw(context.resolve(text),
                         at: CGPoint(x: x, y: keyboardBottom + 8), anchor: .center)
        }
    }

    // MARK: Timeline (en bas, sous les touches)

    private var timeline: some View {
        HStack(spacing: 10) {
            Text(timeString(engine.currentTime))
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(palette.subtleText)
                .frame(width: 42, alignment: .leading)

            Slider(
                value: Binding(
                    get: { engine.currentTime },
                    set: { engine.seek(to: $0) }
                ),
                in: 0...max(engine.duration, 0.01)
            )
            .tint(palette.sliderTint)
            .disabled(engine.notes.isEmpty)

            Text(timeString(engine.duration))
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(palette.subtleText)
                .frame(width: 42, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .frame(height: 40)
        .background(palette.toolbarBg)
        .overlay(alignment: .top) {
            Rectangle().fill(palette.toolbarBorder).frame(height: 1)
        }
    }

    // MARK: Actions & helpers

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        _ = provider.loadObject(ofClass: URL.self) { url, _ in
            guard let url else { return }
            DispatchQueue.main.async { engine.load(url: url) }
        }
        return true
    }

    private func rateLabel(_ r: Float) -> String {
        r == 1.0 ? "1×" : String(format: "%g×", r)
    }

    private func timeString(_ t: Double) -> String {
        guard t.isFinite, t >= 0 else { return "0:00" }
        let total = Int(t.rounded(.down))
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    private func openMIDIFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if let midiType = UTType(filenameExtension: "mid") {
            panel.allowedContentTypes = [midiType, .midi]
        } else {
            panel.allowedContentTypes = [.midi]
        }
        if panel.runModal() == .OK, let url = panel.url {
            engine.load(url: url)
        }
    }

    private func exportMIDI() {
        guard let source = engine.sourceURL else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.midi]
        panel.nameFieldStringValue = source.lastPathComponent
        panel.directoryURL = PianissimoPaths.outputDirectory()
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let dest = panel.url {
            try? FileManager.default.removeItem(at: dest)
            try? FileManager.default.copyItem(at: source, to: dest)
        }
    }
}

// MARK: - Capture de la molette / trackpad

/// Vue transparente qui transmet le défilement vertical sans bloquer le
/// glisser-déposer (elle ne s'enregistre pas pour les types de drag).
struct ScrollWheelCatcher: NSViewRepresentable {
    var onScroll: (_ deltaY: CGFloat, _ precise: Bool) -> Void

    func makeNSView(context: Context) -> ScrollNSView {
        let view = ScrollNSView()
        view.onScroll = onScroll
        return view
    }

    func updateNSView(_ nsView: ScrollNSView, context: Context) {
        nsView.onScroll = onScroll
    }

    final class ScrollNSView: NSView {
        var onScroll: ((CGFloat, Bool) -> Void)?

        override func scrollWheel(with event: NSEvent) {
            let dy = event.scrollingDeltaY
            if dy != 0 {
                onScroll?(dy, event.hasPreciseScrollingDeltas)
            } else {
                super.scrollWheel(with: event)
            }
        }
    }
}
