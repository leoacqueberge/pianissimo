//
//  MIDIPlayerView.swift
//  Pianissimo
//
//  Lecteur MIDI "piano roll" : titre et ouverture en haut, notes qui tombent
//  sur un clavier 88 touches, transport en bas. Le thème et les options
//  suivent Réglages. Raccourcis : espace = play/pause, flèches = ±1 s,
//  ⌘O = ouvrir, ⇧⌘S = exporter.
//  Clic sur une note pour la sélectionner, puis supprimer ou allonger/raccourcir.
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

    /// Pitch le plus proche d'une position x (pour créer une note au clic).
    func pitchNearest(to x: CGFloat) -> Int {
        var best = KeyboardLayout.minPitch
        var bestDist = CGFloat.greatestFiniteMagnitude
        for pitch in KeyboardLayout.minPitch...KeyboardLayout.maxPitch {
            let d = abs(centerX(pitch) - x)
            if d < bestDist {
                bestDist = d
                best = pitch
            }
        }
        return best
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
    var liveKey: Color
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
        liveKey: Color(red: 0.95, green: 0.45, blue: 0.20),
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
        liveKey: Color(red: 1.0, green: 0.55, blue: 0.28),
        sliderTint: Color(red: 0.40, green: 0.65, blue: 1.0)
    )
}

// MARK: - Géométrie de la scène (partagée dessin / hit-test)

private struct StageMetrics {
    let size: CGSize
    let keyboardHeight: CGFloat
    let stageHeight: CGFloat
    let layout: KeyboardLayout
    let lookAhead: Double = 4.0
    let pps: Double

    init(size: CGSize) {
        self.size = size
        keyboardHeight = min(120, max(90, size.height * 0.24))
        stageHeight = size.height - keyboardHeight
        layout = KeyboardLayout(totalWidth: size.width)
        pps = Double(stageHeight) / lookAhead
    }

    func noteRect(_ note: MIDINote, at time: Double) -> CGRect? {
        let topY = stageHeight - (note.end - time) * pps
        let botY = stageHeight - (note.start - time) * pps
        if botY < 0 || topY > stageHeight { return nil }
        let w = layout.noteWidth(note.pitch)
        let x = layout.centerX(note.pitch) - w / 2
        let clampedTop = max(0, topY)
        let clampedBot = min(stageHeight, botY)
        let h = max(2, clampedBot - clampedTop)
        return CGRect(x: x, y: clampedTop, width: w, height: h)
    }
}

private enum NoteDragMode {
    case resizeStart  // bas de la note (début)
    case resizeEnd    // haut de la note (fin)
    case move         // déplacer pitch + timing
}

// MARK: - Vue principale

struct MIDIPlayerView: View {
    @StateObject private var engine = MIDIPlayerEngine()
    let url: URL?

    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("showKeyNoteLabels") private var showKeyNoteLabels = false
    @AppStorage("midiInputEnabled") private var midiInputEnabled = true
    @AppStorage("showRhythmGrid") private var showGrid = false
    @State private var selectedNoteID: UUID?
    @State private var stageSize: CGSize = .zero
    @State private var dragMode: NoteDragMode?
    @State private var dragOriginalStart: Double = 0
    @State private var dragOriginalEnd: Double = 0
    @State private var dragOriginalPitch: Int = 60
    @State private var dragGrabOffsetTime: Double = 0
    @State private var pendingCreate: (point: CGPoint, metrics: StageMetrics, time: Double)?
    @State private var exportError: String?
    @State private var showExportError = false
    @State private var isDropTargeted = false
    @State private var showVolumeDetails = false

    private let rates: [Float] = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0]
    private var palette: PianoPalette { colorScheme == .dark ? .dark : .light }

    private var isEmptyBoard: Bool {
        engine.sourceURL == nil && engine.notes.isEmpty && !engine.hasEdits
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            stage
            timeline
        }
        .frame(minWidth: 760, minHeight: 520)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(palette.background)
        .background(keyboardShortcuts)
        .onAppear {
            if let url {
                if engine.sourceURL != url { engine.load(url: url) }
            } else if engine.sourceURL != nil || !engine.notes.isEmpty {
                engine.resetToEmpty()
            }
            engine.isMIDIInputEnabled = midiInputEnabled
        }
        .onChange(of: midiInputEnabled) { _, enabled in
            engine.isMIDIInputEnabled = enabled
        }
        .onChange(of: url) { _, newURL in
            selectedNoteID = nil
            pendingCreate = nil
            dragMode = nil
            if let newURL {
                if engine.sourceURL != newURL { engine.load(url: newURL) }
            } else {
                engine.resetToEmpty()
            }
        }
        .onChange(of: engine.sourceURL) { _, _ in
            selectedNoteID = nil
        }
        .onDisappear {
            engine.stop()
        }
        .alert("Couldn’t export MIDI", isPresented: $showExportError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(exportError ?? "The file could not be written.")
        }
    }

    private var scoreTitle: String {
        if !engine.fileName.isEmpty {
            return engine.hasEdits ? "\(engine.fileName) · Edited" : engine.fileName
        }
        if !engine.notes.isEmpty || engine.hasEdits {
            return "Untitled"
        }
        return "No score"
    }

    // MARK: Raccourcis clavier (espace, flèches, supprimer)

    private var keyboardShortcuts: some View {
        ZStack {
            Button("") { engine.togglePlay() }
                .keyboardShortcut(.space, modifiers: [])
            Button("") { engine.seek(to: engine.currentTime - 1) }
                .keyboardShortcut(.leftArrow, modifiers: [])
            Button("") { engine.seek(to: engine.currentTime + 1) }
                .keyboardShortcut(.rightArrow, modifiers: [])
            Button("") { deleteSelectedNote() }
                .keyboardShortcut(.delete, modifiers: [])
            Button("") { deleteSelectedNote() }
                .keyboardShortcut(.deleteForward, modifiers: [])
            Button("") { cancelNoteEditing() }
                .keyboardShortcut(.escape, modifiers: [])
            Button("") { engine.undo() }
                .keyboardShortcut("z", modifiers: .command)
                .disabled(!engine.canUndo)
            Button("") { engine.redo() }
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .disabled(!engine.canRedo)
            Button("") { openMIDIFile() }
                .keyboardShortcut("o", modifiers: .command)
            Button("") { exportMIDI() }
                .keyboardShortcut("s", modifiers: [.command, .shift])
                .disabled(engine.exportURL == nil)
        }
        .opacity(0)
        .frame(width: 0, height: 0)
    }

    // MARK: Barre d'outils

    private var toolbar: some View {
        VStack(spacing: 0) {
            toolbarButtons
            if let error = engine.loadError {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                    Text(error)
                        .lineLimit(2)
                    Spacer()
                }
                .font(.system(size: 11))
                .foregroundColor(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(Color.red.opacity(0.85))
            }
        }
    }

    private var toolbarButtons: some View {
        HStack(spacing: 10) {
            Text(scoreTitle)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(palette.text)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(scoreTitle)

            Spacer(minLength: 12)

            Button("Open…", action: openMIDIFile)
                .buttonStyle(.bordered)
                .controlSize(.small)

            Menu {
                Button("Export MIDI…", action: exportMIDI)
                    .disabled(engine.exportURL == nil)
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 14))
                    .foregroundStyle(palette.text)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .help("More")
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 44)
        .background(palette.toolbarBg)
        .overlay(alignment: .bottom) {
            Rectangle().fill(palette.toolbarBorder).frame(height: 1)
        }
    }

    // MARK: - Helpers UI

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
                // Dépendances explicites pour redessiner aussi à l'arrêt (notes live).
                let _ = engine.livePitches
                let _ = engine.currentTime
                Canvas { context, size in
                    drawScene(context: &context, size: size)
                }
                // Capture la taille réelle du Canvas (source de vérité pour le hit-test).
                .background(
                    GeometryReader { geo in
                        Color.clear.preference(key: StageSizeKey.self, value: geo.size)
                    }
                )
            }

            StagePointerLayer(
                onScroll: handleScroll,
                onDown: handlePointerDown,
                onDrag: handlePointerDrag,
                onUp: handlePointerUp,
                onRightClick: handleRightClick,
                onKey: handleStageKey
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())

            if isEmptyBoard {
                emptyBoardOverlay
            }

            if isDropTargeted && !isEmptyBoard {
                dropTargetHighlight
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers)
        }
        .onPreferenceChange(StageSizeKey.self) { stageSize = $0 }
        .animation(.easeInOut(duration: 0.2), value: isDropTargeted)
    }

    /// Convertit un défilement vertical en navigation temporelle (seek).
    private func handleScroll(_ deltaY: CGFloat, precise: Bool) {
        guard engine.duration > 0 else { return }
        // Trackpad (deltas précis) : pas fin. Molette souris : pas plus large.
        let factor = precise ? 0.010 : 0.12
        let newTime = engine.currentTime + Double(deltaY) * factor
        engine.seek(to: newTime)
    }

    private func handlePointerDown(_ point: CGPoint, viewSize: CGSize) {
        // Préférer la taille live de la NSView (évite stageSize encore à zéro).
        let size = viewSize.width > 1 ? viewSize : stageSize
        if size.width > 1 { stageSize = size }
        guard size.width > 1, size.height > 1 else { return }
        let metrics = StageMetrics(size: size)
        guard point.y <= metrics.stageHeight else {
            selectedNoteID = nil
            pendingCreate = nil
            return
        }

        let t = engine.currentTime
        let handle: CGFloat = 14

        // Si une note est déjà sélectionnée, prioriser ses poignées.
        if let id = selectedNoteID,
           let note = engine.note(id: id),
           let rect = metrics.noteRect(note, at: t) {
            if abs(point.y - rect.minY) <= handle, rect.insetBy(dx: -6, dy: 0).contains(CGPoint(x: point.x, y: rect.midY)) {
                beginResize(note: note, edge: .resizeEnd)
                return
            }
            if abs(point.y - rect.maxY) <= handle, rect.insetBy(dx: -6, dy: 0).contains(CGPoint(x: point.x, y: rect.midY)) {
                beginResize(note: note, edge: .resizeStart)
                return
            }
        }

        // Hit-test : dernière note dessinée (au premier plan) en premier.
        pendingCreate = nil
        if let hit = hitTestNote(at: point, metrics: metrics, time: t) {
            selectedNoteID = hit.id
            if engine.isPlaying { engine.pause() }
            if let rect = metrics.noteRect(hit, at: t) {
                if abs(point.y - rect.minY) <= handle {
                    beginResize(note: hit, edge: .resizeEnd)
                } else if abs(point.y - rect.maxY) <= handle {
                    beginResize(note: hit, edge: .resizeStart)
                } else {
                    beginMove(note: hit, at: point, metrics: metrics, time: t)
                }
            }
        } else {
            // Clic dans le vide → désélection. Un drag crée une note.
            selectedNoteID = nil
            pendingCreate = (point, metrics, t)
            dragMode = nil
        }
    }

    private func createNote(at point: CGPoint, metrics: StageMetrics, time: Double) {
        if engine.isPlaying { engine.pause() }

        let pitch = metrics.layout.pitchNearest(to: point.x)
        let start = max(0, time + (metrics.stageHeight - Double(point.y)) / metrics.pps)
        let initialDuration = 0.25

        engine.beginGestureEdit()
        let id = engine.addNote(
            pitch: pitch,
            start: start,
            duration: initialDuration,
            registerUndo: false
        )
        selectedNoteID = id
        dragMode = .resizeEnd
        dragOriginalStart = start
        dragOriginalEnd = start + initialDuration
        dragOriginalPitch = pitch
    }

    private func handleRightClick(_ point: CGPoint, viewSize: CGSize) {
        let size = viewSize.width > 1 ? viewSize : stageSize
        if size.width > 1 { stageSize = size }
        guard size.width > 1, size.height > 1 else { return }
        let metrics = StageMetrics(size: size)
        guard point.y <= metrics.stageHeight else { return }

        guard let hit = hitTestNote(at: point, metrics: metrics, time: engine.currentTime) else {
            return
        }
        if engine.isPlaying { engine.pause() }
        engine.removeNote(id: hit.id)
        if selectedNoteID == hit.id {
            selectedNoteID = nil
        }
        dragMode = nil
    }

    private func handlePointerDrag(_ point: CGPoint, viewSize: CGSize) {
        if let pending = pendingCreate, dragMode == nil {
            let dist = hypot(point.x - pending.point.x, point.y - pending.point.y)
            if dist > 6 {
                createNote(at: pending.point, metrics: pending.metrics, time: pending.time)
                pendingCreate = nil
            } else {
                return
            }
        }

        guard let mode = dragMode,
              let id = selectedNoteID else { return }
        let size = viewSize.width > 1 ? viewSize : stageSize
        guard size.width > 1 else { return }
        let metrics = StageMetrics(size: size)
        let t = engine.currentTime
        let eventTime = t + (metrics.stageHeight - Double(point.y)) / metrics.pps

        switch mode {
        case .resizeEnd:
            engine.setNoteTiming(id: id, start: dragOriginalStart,
                                 end: max(dragOriginalStart + 0.05, eventTime),
                                 finalize: false)
        case .resizeStart:
            engine.setNoteTiming(id: id,
                                 start: min(eventTime, dragOriginalEnd - 0.05),
                                 end: dragOriginalEnd,
                                 finalize: false)
        case .move:
            let duration = max(0.05, dragOriginalEnd - dragOriginalStart)
            let newStart = max(0, eventTime - dragGrabOffsetTime)
            let newPitch = metrics.layout.pitchNearest(to: point.x)
            engine.setNotePlacement(id: id, pitch: newPitch, start: newStart,
                                    duration: duration, finalize: false)
        }
    }

    private func handlePointerUp(_ point: CGPoint, viewSize: CGSize) {
        pendingCreate = nil
        if dragMode != nil {
            engine.finalizeEdits()
        }
        dragMode = nil
    }

    private func cancelNoteEditing() {
        pendingCreate = nil
        if dragMode != nil {
            engine.cancelGestureEdit()
            dragMode = nil
        }
        selectedNoteID = nil
    }

    private func handleStageKey(_ command: StageKeyCommand) {
        switch command {
        case .escape: cancelNoteEditing()
        case .space: engine.togglePlay()
        case .left: engine.seek(to: engine.currentTime - 1)
        case .right: engine.seek(to: engine.currentTime + 1)
        case .delete: deleteSelectedNote()
        case .undo: engine.undo()
        case .redo: engine.redo()
        }
    }

    private func beginResize(note: MIDINote, edge: NoteDragMode) {
        dragMode = edge
        dragOriginalStart = note.start
        dragOriginalEnd = note.end
        dragOriginalPitch = note.pitch
        engine.beginGestureEdit()
    }

    private func beginMove(note: MIDINote, at point: CGPoint, metrics: StageMetrics, time: Double) {
        dragMode = .move
        dragOriginalStart = note.start
        dragOriginalEnd = note.end
        dragOriginalPitch = note.pitch
        let grabTime = time + (metrics.stageHeight - Double(point.y)) / metrics.pps
        dragGrabOffsetTime = grabTime - note.start
        engine.beginGestureEdit()
    }

    private func hitTestNote(at point: CGPoint, metrics: StageMetrics, time: Double) -> MIDINote? {
        for note in engine.notes.reversed() {
            guard let rect = metrics.noteRect(note, at: time) else { continue }
            // Zone de clic élargie (surtout utile pour les notes très courtes).
            let hit = rect.insetBy(dx: -3, dy: -6)
            if hit.contains(point) { return note }
        }
        return nil
    }

    private func deleteSelectedNote() {
        guard let id = selectedNoteID else { return }
        engine.removeNote(id: id)
        selectedNoteID = nil
    }

    private var emptyBoardOverlay: some View {
        GeometryReader { geo in
            let metrics = StageMetrics(size: geo.size)

            VStack(spacing: 0) {
                ZStack {
                    emptyDropZone
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                Color.clear
                    .frame(height: metrics.keyboardHeight)
                    .allowsHitTesting(false)
            }
        }
    }

    private var emptyDropZone: some View {
        Button(action: openMIDIFile) {
            VStack(spacing: 10) {
                Image(systemName: "square.and.arrow.down")
                    .font(.system(size: 24, weight: .light))
                    .foregroundStyle(palette.accent)
                    .symbolEffect(.bounce, value: isDropTargeted)

                Text(isDropTargeted ? "Drop to open" : "Drop a MIDI file")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(palette.text)

                Text("Open MIDI file…")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(palette.accent))
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 18)
            .frame(width: 280)
            .contentShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(palette.accent.opacity(isDropTargeted ? 0.14 : 0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(
                    isDropTargeted ? palette.accent : palette.toolbarBorder,
                    style: StrokeStyle(lineWidth: isDropTargeted ? 2 : 1, dash: [8, 6])
                )
        )
    }

    private var dropTargetHighlight: some View {
        RoundedRectangle(cornerRadius: 16)
            .fill(palette.accent.opacity(0.12))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(palette.accent, style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
            )
            .padding(12)
            .allowsHitTesting(false)
    }

    private func drawScene(context: inout GraphicsContext, size: CGSize) {
        let metrics = StageMetrics(size: size)
        let layout = metrics.layout
        let stageHeight = metrics.stageHeight
        let keyboardHeight = metrics.keyboardHeight
        let t = engine.currentTime
        let pps = metrics.pps

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
            for i in 0...Int(metrics.lookAhead) + 1 {
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
            guard let rect = metrics.noteRect(note, at: t) else { continue }

            let isActive = note.start <= t && t <= note.end
            if isActive { activePitches.insert(note.pitch) }
            let isSelected = note.id == selectedNoteID
            let isWhite = KeyboardLayout.isWhite(note.pitch)

            let path = Path(roundedRect: rect, cornerRadius: min(4, rect.width / 3))
            let base = isActive || isSelected
                ? palette.activeKey
                : (isWhite ? palette.noteWhite : palette.noteBlack)
            let intensity = 0.6 + Double(note.velocity) / 127.0 * 0.4
            context.fill(path, with: .color(base.opacity(intensity)))

            if isSelected {
                context.stroke(path, with: .color(palette.accent), lineWidth: 2.5)
                // Poignées haut / bas bien visibles pour redimensionner
                let handleW = max(12, rect.width)
                let handleH: CGFloat = 6
                let hx = rect.midX - handleW / 2
                let topHandle = CGRect(x: hx, y: rect.minY - 2, width: handleW, height: handleH)
                let botHandle = CGRect(x: hx, y: rect.maxY - handleH + 2, width: handleW, height: handleH)
                context.fill(Path(roundedRect: topHandle, cornerRadius: 3), with: .color(.white))
                context.stroke(Path(roundedRect: topHandle, cornerRadius: 3), with: .color(palette.accent), lineWidth: 1.5)
                context.fill(Path(roundedRect: botHandle, cornerRadius: 3), with: .color(.white))
                context.stroke(Path(roundedRect: botHandle, cornerRadius: 3), with: .color(palette.accent), lineWidth: 1.5)
            } else if isActive {
                context.stroke(path, with: .color(palette.accent), lineWidth: 1.5)
            }
        }

        // Ligne de frappe
        context.fill(Path(CGRect(x: 0, y: stageHeight - 1.5, width: size.width, height: 1.5)),
                     with: .color(palette.accent.opacity(0.5)))

        drawKeyboard(context: &context, size: size, stageHeight: stageHeight,
                     keyboardHeight: keyboardHeight, layout: layout,
                     activePitches: activePitches,
                     livePitches: engine.livePitches)
    }

    private func drawKeyboard(context: inout GraphicsContext, size: CGSize,
                              stageHeight: CGFloat, keyboardHeight: CGFloat,
                              layout: KeyboardLayout, activePitches: Set<Int>,
                              livePitches: Set<Int>) {
        let top = stageHeight

        for pitch in KeyboardLayout.minPitch...KeyboardLayout.maxPitch
        where KeyboardLayout.isWhite(pitch) {
            let x = layout.leftEdge(pitch)
            let rect = CGRect(x: x, y: top, width: layout.whiteWidth - 1, height: keyboardHeight)
            let isLive = livePitches.contains(pitch)
            let isActive = activePitches.contains(pitch)
            let fill: Color = {
                if isLive { return palette.liveKey }
                if isActive { return palette.activeKey }
                return palette.whiteKey
            }()
            context.fill(Path(rect), with: .color(fill))
            context.stroke(Path(rect), with: .color(palette.keyBorder), lineWidth: 0.5)

            if showKeyNoteLabels {
                let label = PitchName.solfege(pitch)
                let fontSize: CGFloat = layout.whiteWidth >= 18 ? 8 : 6.5
                let textColor = (isLive || isActive)
                    ? Color.white.opacity(0.95)
                    : palette.text.opacity(0.55)
                let text = Text(label)
                    .font(.system(size: fontSize, weight: .medium, design: .rounded))
                    .foregroundColor(textColor)
                context.draw(
                    context.resolve(text),
                    at: CGPoint(x: rect.midX, y: rect.maxY - 10),
                    anchor: .center
                )
            }
        }

        let blackHeight = keyboardHeight * 0.62
        for pitch in KeyboardLayout.minPitch...KeyboardLayout.maxPitch
        where !KeyboardLayout.isWhite(pitch) {
            let x = layout.centerX(pitch) - layout.blackWidth / 2
            let rect = CGRect(x: x, y: top, width: layout.blackWidth, height: blackHeight)
            let isLive = livePitches.contains(pitch)
            let isActive = activePitches.contains(pitch)
            let fill: Color = {
                if isLive { return palette.liveKey }
                if isActive { return palette.activeKey }
                return palette.blackKey
            }()
            let path = Path(roundedRect: rect, cornerRadius: 2)
            context.fill(path, with: .color(fill))

            if showKeyNoteLabels, layout.blackWidth >= 10 {
                let label = PitchName.solfege(pitch)
                let text = Text(label)
                    .font(.system(size: 5.5, weight: .medium, design: .rounded))
                    .foregroundColor(Color.white.opacity((isLive || isActive) ? 0.95 : 0.7))
                context.draw(
                    context.resolve(text),
                    at: CGPoint(x: rect.midX, y: rect.maxY - 8),
                    anchor: .center
                )
            }
        }
    }

    // MARK: Timeline (en bas, sous les touches)

    private var timeline: some View {
        HStack(spacing: 12) {
            HStack(spacing: 4) {
                iconButton("backward.end.fill", help: "Back to start",
                           disabled: engine.notes.isEmpty) {
                    engine.stop()
                }
                playButton
            }

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

            iconButton("repeat", help: "Loop playback",
                       active: engine.isLooping) {
                engine.isLooping.toggle()
            }

            speedMenu
            volumeControl
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 52)
        .background(palette.toolbarBg)
        .overlay(alignment: .top) {
            Rectangle().fill(palette.toolbarBorder).frame(height: 1)
        }
    }

    private var playButton: some View {
        Button {
            engine.togglePlay()
        } label: {
            Image(systemName: engine.isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 32, height: 32)
                .foregroundColor(engine.notes.isEmpty ? palette.subtleText.opacity(0.5) : palette.text)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(palette.accent.opacity(engine.isPlaying ? 0.14 : 0.08))
                )
        }
        .buttonStyle(.plain)
        .disabled(engine.notes.isEmpty)
        .help("Play / Pause")
    }

    private var speedMenu: some View {
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
    }

    private var volumeControl: some View {
        HStack(spacing: 6) {
            iconButton(engine.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                       help: "Mute song", active: engine.isMuted) {
                engine.isMuted.toggle()
            }
            Slider(value: $engine.volume, in: 0...1)
                .frame(width: 78)
                .tint(palette.sliderTint)
            Button {
                showVolumeDetails.toggle()
            } label: {
                Image(systemName: "chevron.up")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(palette.subtleText)
                    .rotationEffect(.degrees(showVolumeDetails ? 180 : 0))
                    .frame(width: 18, height: 18)
                    .animation(.easeInOut(duration: 0.15), value: showVolumeDetails)
            }
            .buttonStyle(.plain)
            .help("Song and keyboard volume")
            .popover(isPresented: $showVolumeDetails, arrowEdge: .top) {
                volumePopover
            }
        }
    }

    private var volumePopover: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Volume")
                .font(.headline)

            volumeRow(
                title: "Song",
                volume: $engine.volume,
                muted: $engine.isMuted,
                tint: palette.sliderTint,
                enabled: true
            )

            volumeRow(
                title: "Keys",
                volume: $engine.liveVolume,
                muted: $engine.isLiveMuted,
                tint: palette.liveKey,
                enabled: midiInputEnabled
            )

            if !midiInputEnabled {
                Text("Turn on MIDI keyboard in Settings to play along.")
                    .font(.caption)
                    .foregroundStyle(palette.subtleText)
                    .fixedSize(horizontal: false, vertical: true)
            } else if engine.midiSourceCount > 0 {
                HStack(spacing: 6) {
                    Circle()
                        .fill(palette.liveKey)
                        .frame(width: 6, height: 6)
                    Text("Keyboard connected")
                        .font(.caption)
                        .foregroundStyle(palette.liveKey)
                }
            }
        }
        .padding(16)
        .frame(width: 260)
    }

    private func volumeRow(
        title: String,
        volume: Binding<Float>,
        muted: Binding<Bool>,
        tint: Color,
        enabled: Bool
    ) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(enabled ? palette.text : palette.subtleText)
                .frame(width: 44, alignment: .leading)
            Slider(value: volume, in: 0...1)
                .tint(tint)
                .disabled(!enabled || muted.wrappedValue)
            Button {
                muted.wrappedValue.toggle()
            } label: {
                Image(systemName: muted.wrappedValue ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(muted.wrappedValue ? palette.accent : palette.subtleText)
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .disabled(!enabled)
        }
    }

    // MARK: Actions & helpers

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        _ = provider.loadObject(ofClass: URL.self) { url, _ in
            guard let url else { return }
            DispatchQueue.main.async {
                let ext = url.pathExtension.lowercased()
                guard ext == "mid" || ext == "midi" else { return }
                selectedNoteID = nil
                engine.load(url: url)
            }
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
            selectedNoteID = nil
            engine.load(url: url)
        }
    }

    private func exportMIDI() {
        guard let source = engine.exportURL else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.midi]
        let baseName = engine.sourceURL?.lastPathComponent ?? source.lastPathComponent
        panel.nameFieldStringValue = engine.hasEdits
            ? (engine.sourceURL?.deletingPathExtension().lastPathComponent ?? "edited") + "-edited.mid"
            : baseName
        panel.directoryURL = PianissimoPaths.outputDirectory()
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let dest = panel.url {
            do {
                if FileManager.default.fileExists(atPath: dest.path) {
                    try FileManager.default.removeItem(at: dest)
                }
                try FileManager.default.copyItem(at: source, to: dest)
            } catch {
                exportError = error.localizedDescription
                showExportError = true
            }
        }
    }
}

// MARK: - Taille de la scène

private struct StageSizeKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        value = nextValue()
    }
}

// MARK: - Interaction piano roll

private enum StageKeyCommand {
    case escape, space, left, right, delete, undo, redo
}

/// Couche pleine surface : clic / drag pour éditer, molette pour seek.
/// Utilise AppKit avec un layout explicite (les NSView "vides" sont sinon
/// ignorées par le hit-testing SwiftUI).
private struct StagePointerLayer: NSViewRepresentable {
    var onScroll: (_ deltaY: CGFloat, _ precise: Bool) -> Void
    var onDown: (CGPoint, CGSize) -> Void
    var onDrag: (CGPoint, CGSize) -> Void
    var onUp: (CGPoint, CGSize) -> Void
    var onRightClick: (CGPoint, CGSize) -> Void
    var onKey: (StageKeyCommand) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> StageNSView {
        let view = StageNSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor
        context.coordinator.bind(view, representable: self)
        return view
    }

    func updateNSView(_ nsView: StageNSView, context: Context) {
        context.coordinator.bind(nsView, representable: self)
    }

    /// Oblige SwiftUI à donner toute la place proposée (sinon taille 0 → aucun clic).
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: StageNSView, context: Context) -> CGSize? {
        let fallback = CGSize(width: 800, height: 400)
        return CGSize(
            width: proposal.width ?? fallback.width,
            height: proposal.height ?? fallback.height
        )
    }

    final class Coordinator {
        func bind(_ view: StageNSView, representable: StagePointerLayer) {
            view.onScroll = representable.onScroll
            view.onDown = representable.onDown
            view.onDrag = representable.onDrag
            view.onUp = representable.onUp
            view.onRightClick = representable.onRightClick
            view.onKey = representable.onKey
        }
    }

    final class StageNSView: NSView {
        var onScroll: ((CGFloat, Bool) -> Void)?
        var onDown: ((CGPoint, CGSize) -> Void)?
        var onDrag: ((CGPoint, CGSize) -> Void)?
        var onUp: ((CGPoint, CGSize) -> Void)?
        var onRightClick: ((CGPoint, CGSize) -> Void)?
        var onKey: ((StageKeyCommand) -> Void)?
        private var tracking = false

        override var isFlipped: Bool { true }
        override var acceptsFirstResponder: Bool { true }

        override func hitTest(_ point: NSPoint) -> NSView? {
            bounds.contains(point) ? self : nil
        }

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        private func point(from event: NSEvent) -> CGPoint {
            convert(event.locationInWindow, from: nil)
        }

        override func scrollWheel(with event: NSEvent) {
            let dy = event.scrollingDeltaY
            if dy != 0 {
                onScroll?(dy, event.hasPreciseScrollingDeltas)
            } else {
                super.scrollWheel(with: event)
            }
        }

        override func mouseDown(with event: NSEvent) {
            window?.makeFirstResponder(self)
            tracking = true
            onDown?(point(from: event), bounds.size)
        }

        override func mouseDragged(with event: NSEvent) {
            guard tracking else { return }
            onDrag?(point(from: event), bounds.size)
        }

        override func mouseUp(with event: NSEvent) {
            tracking = false
            onUp?(point(from: event), bounds.size)
        }

        override func rightMouseDown(with event: NSEvent) {
            window?.makeFirstResponder(self)
            onRightClick?(point(from: event), bounds.size)
        }

        override func keyDown(with event: NSEvent) {
            if event.modifierFlags.contains(.command),
               event.charactersIgnoringModifiers?.lowercased() == "z" {
                onKey?(event.modifierFlags.contains(.shift) ? .redo : .undo)
                return
            }
            switch event.keyCode {
            case 53: onKey?(.escape)
            case 49: onKey?(.space)
            case 123: onKey?(.left)
            case 124: onKey?(.right)
            case 51, 117: onKey?(.delete)
            default:
                super.keyDown(with: event)
            }
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AppModel())
        .environmentObject(RecentFilesStore())
}
