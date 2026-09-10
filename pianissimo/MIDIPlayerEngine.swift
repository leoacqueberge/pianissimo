//
//  MIDIPlayerEngine.swift
//  Pianissimo
//
//  Moteur de lecture MIDI basé sur AVAudioEngine + AVAudioUnitSampler +
//  AVAudioSequencer. Cette pile permet un vrai contrôle du volume, de la
//  vitesse, du seek et de la lecture en boucle, tout en exposant la position
//  de lecture pour synchroniser le piano roll.
//

import Foundation
import AVFoundation
import Combine

@MainActor
final class MIDIPlayerEngine: ObservableObject {
    @Published private(set) var notes: [MIDINote] = []
    @Published private(set) var duration: Double = 0
    @Published private(set) var isPlaying = false
    @Published var currentTime: Double = 0
    @Published private(set) var fileName: String = ""
    @Published private(set) var sourceURL: URL? = nil
    @Published private(set) var loadError: String? = nil
    @Published var isLooping = false
    @Published private(set) var hasEdits = false
    @Published private(set) var canUndo = false
    @Published private(set) var canRedo = false

    /// Touches actuellement enfoncées / tenues (clavier MIDI externe).
    @Published private(set) var livePitches: Set<Int> = []
    /// Pédale sustain enfoncée.
    @Published private(set) var isSustainDown = false
    /// Nombre de sources MIDI détectées (0 = aucun clavier).
    @Published private(set) var midiSourceCount: Int = 0
    /// Écoute du clavier MIDI + son via le sampler de l'app.
    @Published var isMIDIInputEnabled = false {
        didSet {
            if isMIDIInputEnabled {
                startMIDIInput()
            } else {
                stopMIDIInput()
            }
        }
    }

    @Published var rate: Float = 1.0 {
        didSet { sequencer?.rate = rate }
    }
    /// Volume de la lecture du morceau.
    @Published var volume: Float = 0.8 {
        didSet { applyVolume() }
    }
    @Published var isMuted = false {
        didSet { applyVolume() }
    }
    /// Volume du clavier MIDI (indépendant du morceau).
    @Published var liveVolume: Float = 0.9 {
        didSet { applyVolume() }
    }
    @Published var isLiveMuted = false {
        didSet { applyVolume() }
    }

    private let engine = AVAudioEngine()
    private let songSampler = AVAudioUnitSampler()
    private let liveSampler = AVAudioUnitSampler()
    private let songMixer = AVAudioMixerNode()
    private let liveMixer = AVAudioMixerNode()
    private var sequencer: AVAudioSequencer?
    private var displayTimer: Timer?
    private var editedMIDIURL: URL?
    private let midiInput = MIDIInputMonitor()

    /// Touches physiquement enfoncées.
    private var heldPitches: Set<Int> = []
    /// Touches relâchées mais encore sonores grâce au sustain.
    private var sustainedPitches: Set<Int> = []
    private var liveVelocities: [Int: UInt8] = [:]

    private var undoStack: [[MIDINote]] = []
    private var redoStack: [[MIDINote]] = []
    private var originalNotes: [MIDINote] = []
    /// Snapshot pris au début d'un drag (redimensionnement).
    private var gestureBaseline: [MIDINote]?
    private var tempoMap: MIDITempoMap = .standard120
    private let maxUndoLevels = 50

    var usingBundledSoundFont: Bool { MIDIPlayerEngine.bundledSoundFont() != nil }

    init() {
        engine.attach(songSampler)
        engine.attach(liveSampler)
        engine.attach(songMixer)
        engine.attach(liveMixer)
        try? engine.connectNode(songSampler, to: songMixer, format: nil)
        try? engine.connectNode(liveSampler, to: liveMixer, format: nil)
        try? engine.connectNode(songMixer, to: engine.mainMixerNode, format: nil)
        try? engine.connectNode(liveMixer, to: engine.mainMixerNode, format: nil)
        engine.mainMixerNode.outputVolume = 1
        applyVolume()
        loadSoundFont()
        try? engine.start()
        setupMIDIInputCallbacks()
    }

    deinit {
        displayTimer?.invalidate()
        if let editedMIDIURL {
            try? FileManager.default.removeItem(at: editedMIDIURL)
        }
    }

    static func bundledSoundFont() -> URL? {
        for ext in ["sf2", "dls"] {
            if let url = Bundle.main.urls(forResourcesWithExtension: ext, subdirectory: nil)?.first {
                return url
            }
        }
        return nil
    }

    private func loadSoundFont() {
        guard let url = MIDIPlayerEngine.bundledSoundFont() else { return }
        // 0x79 = banque mélodique GM par défaut, programme 0 = piano acoustique.
        for sampler in [songSampler, liveSampler] {
            try? sampler.loadSoundBankInstrument(at: url, program: 0,
                                                 bankMSB: 0x79, bankLSB: 0x00)
        }
    }

    private func applyVolume() {
        songMixer.outputVolume = isMuted ? 0 : volume
        liveMixer.outputVolume = isLiveMuted ? 0 : liveVolume
    }

    func load(url: URL) {
        stop()
        clearEditedFile()
        clearUndoHistory()
        hasEdits = false
        fileName = url.lastPathComponent
        sourceURL = url
        loadError = nil
        tempoMap = .standard120

        do {
            let parsed = try MIDIFile.parse(url: url)
            notes = parsed.notes
            duration = parsed.duration
            tempoMap = parsed.tempoMap
        } catch {
            notes = []
            duration = 0
            tempoMap = .standard120
            loadError = error.localizedDescription
        }

        originalNotes = notes
        attachSequencer(from: url)
        currentTime = 0
    }

    func resetToEmpty() {
        stop()
        clearEditedFile()
        clearUndoHistory()
        hasEdits = false
        fileName = ""
        sourceURL = nil
        loadError = nil
        notes = []
        duration = 0
        currentTime = 0
        tempoMap = .standard120
        sequencer = nil
        originalNotes = []
    }

    // MARK: - Édition des notes

    /// Ajoute une note. Retourne son id. Par défaut enregistre un undo.
    @discardableResult
    func addNote(pitch: Int,
                 start: Double,
                 duration: Double = 0.25,
                 velocity: Int = 96,
                 track: Int = 0,
                 registerUndo: Bool = true) -> UUID {
        if registerUndo { registerUndoBeforeChange() }
        let note = MIDINote(
            pitch: min(KeyboardLayout.maxPitch, max(KeyboardLayout.minPitch, pitch)),
            start: max(0, start),
            duration: max(0.05, duration),
            velocity: min(127, max(1, velocity)),
            track: track
        )
        notes.append(note)
        notes.sort { $0.start < $1.start }
        refreshDuration()
        if registerUndo {
            applyEditsToSequencer()
            refreshEditFlags()
        }
        return note.id
    }

    func removeNote(id: UUID) {
        guard notes.contains(where: { $0.id == id }) else { return }
        registerUndoBeforeChange()
        notes.removeAll { $0.id == id }
        refreshDuration()
        applyEditsToSequencer()
        refreshEditFlags()
    }

    /// Ajuste la durée d'une note (minimum 0.05 s). Conserve le début.
    func setNoteDuration(id: UUID, duration newDuration: Double, finalize: Bool = true) {
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
        if finalize { registerUndoBeforeChange() }
        notes[index].duration = max(0.05, newDuration)
        refreshDuration()
        if finalize {
            applyEditsToSequencer()
            refreshEditFlags()
        }
    }

    /// Déplace le début et/ou la fin d'une note (redimensionnement).
    /// Passer `finalize: false` pendant un drag, puis appeler `finalizeEdits()` au relâchement.
    func setNoteTiming(id: UUID, start: Double, end: Double, finalize: Bool = true) {
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
        if finalize { registerUndoBeforeChange() }
        let clampedStart = max(0, start)
        let clampedEnd = max(clampedStart + 0.05, end)
        notes[index].start = clampedStart
        notes[index].duration = clampedEnd - clampedStart
        refreshDuration()
        if finalize {
            applyEditsToSequencer()
            refreshEditFlags()
        }
    }

    /// Déplace une note (pitch + début), durée inchangée.
    func setNotePlacement(id: UUID, pitch: Int, start: Double, duration: Double, finalize: Bool = true) {
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
        if finalize { registerUndoBeforeChange() }
        notes[index].pitch = min(KeyboardLayout.maxPitch, max(KeyboardLayout.minPitch, pitch))
        notes[index].start = max(0, start)
        notes[index].duration = max(0.05, duration)
        notes.sort { $0.start < $1.start }
        refreshDuration()
        if finalize {
            applyEditsToSequencer()
            refreshEditFlags()
        }
    }

    /// À appeler au début d'un drag de redimensionnement (une seule fois).
    func beginGestureEdit() {
        guard gestureBaseline == nil else { return }
        gestureBaseline = notes
    }

    /// Annule le geste en cours (Échap) : restaure le snapshot sans enregistrer d'undo.
    func cancelGestureEdit() {
        guard let baseline = gestureBaseline else { return }
        notes = baseline
        gestureBaseline = nil
        refreshDuration()
    }

    func note(id: UUID) -> MIDINote? {
        notes.first { $0.id == id }
    }

    /// URL à exporter : version éditée si disponible, sinon le fichier source.
    var exportURL: URL? { editedMIDIURL ?? sourceURL }

    private func refreshDuration() {
        duration = notes.map(\.end).max() ?? 0
    }

    // MARK: - Undo / Redo

    func undo() {
        guard let previous = undoStack.popLast() else { return }
        gestureBaseline = nil
        redoStack.append(notes)
        notes = previous
        refreshDuration()
        applyEditsToSequencer()
        refreshEditFlags()
    }

    func redo() {
        guard let next = redoStack.popLast() else { return }
        gestureBaseline = nil
        undoStack.append(notes)
        notes = next
        refreshDuration()
        applyEditsToSequencer()
        refreshEditFlags()
    }

    private func registerUndoBeforeChange() {
        undoStack.append(notes)
        if undoStack.count > maxUndoLevels {
            undoStack.removeFirst()
        }
        redoStack.removeAll()
        updateUndoFlags()
    }

    private func clearUndoHistory() {
        undoStack.removeAll()
        redoStack.removeAll()
        gestureBaseline = nil
        originalNotes = []
        updateUndoFlags()
    }

    private func updateUndoFlags() {
        canUndo = !undoStack.isEmpty
        canRedo = !redoStack.isEmpty
    }

    private func refreshEditFlags() {
        hasEdits = notes != originalNotes
        updateUndoFlags()
    }

    /// Fin d'un geste (drag) : enregistre l'undo si quelque chose a changé, puis sync audio.
    func finalizeEdits() {
        if let baseline = gestureBaseline {
            if baseline != notes {
                undoStack.append(baseline)
                if undoStack.count > maxUndoLevels {
                    undoStack.removeFirst()
                }
                redoStack.removeAll()
            }
            gestureBaseline = nil
        }
        applyEditsToSequencer()
        refreshEditFlags()
    }

    /// Réécrit le MIDI et recharge le séquenceur pour que l'audio suive les edits.
    private func applyEditsToSequencer() {
        let wasPlaying = isPlaying
        let time = currentTime
        if wasPlaying { pause() }

        do {
            let url = try ensureEditedURL()
            try MIDIFile.write(notes: notes, to: url, tempoMap: tempoMap)
            attachSequencer(from: url)
            seek(to: time)
            if wasPlaying { play() }
        } catch {
            loadError = "Edit failed: \(error.localizedDescription)"
        }
    }

    private func ensureEditedURL() throws -> URL {
        if let editedMIDIURL { return editedMIDIURL }
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PianissimoEdits", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let name = (sourceURL?.deletingPathExtension().lastPathComponent ?? "edited") + "-edit.mid"
        let url = dir.appendingPathComponent(name)
        editedMIDIURL = url
        return url
    }

    private func clearEditedFile() {
        if let editedMIDIURL {
            try? FileManager.default.removeItem(at: editedMIDIURL)
        }
        editedMIDIURL = nil
    }

    private func attachSequencer(from url: URL) {
        sequencer = nil
        if !engine.isRunning { try? engine.start() }

        let seq = AVAudioSequencer(audioEngine: engine)
        do {
            try seq.load(from: url, options: [])
            for track in seq.tracks {
                track.destinationAudioUnit = songSampler
            }
            seq.prepareToPlay()
            seq.rate = rate
            sequencer = seq
            if duration <= 0 {
                duration = seq.tracks.map { $0.lengthInSeconds }.max() ?? 0
            }
        } catch {
            let prefix = loadError.map { $0 + " — " } ?? ""
            loadError = prefix + "Audio unavailable: \(error.localizedDescription)"
        }
    }

    func togglePlay() {
        isPlaying ? pause() : play()
    }

    func play() {
        guard let seq = sequencer else { return }
        if currentTime >= duration - 0.02 { seek(to: 0) }
        if !engine.isRunning { try? engine.start() }
        do {
            try seq.start()
            isPlaying = true
            startTimer()
        } catch {
            loadError = "Playback failed: \(error.localizedDescription)"
        }
    }

    func pause() {
        guard let seq = sequencer else { return }
        currentTime = seq.currentPositionInSeconds
        seq.stop()
        allNotesOff()
        isPlaying = false
        stopTimer()
    }

    func stop() {
        sequencer?.stop()
        sequencer?.currentPositionInSeconds = 0
        allNotesOff()
        currentTime = 0
        isPlaying = false
        stopTimer()
    }

    func seek(to time: Double) {
        let clamped = min(max(0, time), max(duration, 0))
        currentTime = clamped
        sequencer?.currentPositionInSeconds = clamped
        allNotesOff()
    }

    private func allNotesOff() {
        // Coupe seulement la piste du morceau — le jeu live continue.
        for channel in UInt8(0)..<16 {
            songSampler.sendController(123, withValue: 0, onChannel: channel)
        }
    }

    // MARK: - Entrée MIDI live

    private func setupMIDIInputCallbacks() {
        midiInput.onNoteOn = { [weak self] pitch, velocity in
            self?.handleLiveNoteOn(pitch: pitch, velocity: velocity)
        }
        midiInput.onNoteOff = { [weak self] pitch in
            self?.handleLiveNoteOff(pitch: pitch)
        }
        midiInput.onSustain = { [weak self] down in
            self?.handleSustain(down)
        }
        midiInput.onSourcesChanged = { [weak self] count in
            self?.midiSourceCount = count
        }
    }

    private func startMIDIInput() {
        if !engine.isRunning { try? engine.start() }
        isSustainDown = false
        sustainedPitches.removeAll()
        midiInput.sustainInverted = sustainPedalInverted
        midiInput.start()
    }

    /// Polarité de la pédale (certaines envoient 127 au repos).
    var sustainPedalInverted = false {
        didSet {
            midiInput.sustainInverted = sustainPedalInverted
            // Recalage : on considère la pédale relevée après un changement de polarité.
            if isSustainDown {
                handleSustain(false)
            }
        }
    }

    private func stopMIDIInput() {
        clearAllLiveNotes()
        isSustainDown = false
        midiInput.stop()
        midiSourceCount = 0
    }

    private func handleLiveNoteOn(pitch: Int, velocity: Int) {
        guard isMIDIInputEnabled else { return }
        let vel = UInt8(clamping: min(127, max(1, velocity)))
        liveVelocities[pitch] = vel
        heldPitches.insert(pitch)
        // Retrigger : sort de l'ensemble « tenu par pédale ».
        sustainedPitches.remove(pitch)
        liveSampler.startNote(UInt8(clamping: pitch), withVelocity: vel, onChannel: 0)
        publishLivePitches()
    }

    private func handleLiveNoteOff(pitch: Int) {
        guard heldPitches.contains(pitch) || sustainedPitches.contains(pitch) || liveVelocities[pitch] != nil else {
            // Note-off orphelin (souvent dû à un ancien bug d'ordre) : coupe quand même.
            releaseLivePitch(pitch)
            publishLivePitches()
            return
        }
        heldPitches.remove(pitch)
        if isSustainDown {
            sustainedPitches.insert(pitch)
            publishLivePitches()
        } else {
            sustainedPitches.remove(pitch)
            releaseLivePitch(pitch)
            publishLivePitches()
        }
    }

    private func handleSustain(_ down: Bool) {
        guard isMIDIInputEnabled else { return }
        let wasDown = isSustainDown
        isSustainDown = down
        if wasDown && !down {
            // Relâche toutes les notes tenues uniquement par la pédale.
            let toRelease = sustainedPitches.subtracting(heldPitches)
            for pitch in toRelease {
                releaseLivePitch(pitch)
            }
            sustainedPitches.removeAll()
            publishLivePitches()
        }
    }

    private func releaseLivePitch(_ pitch: Int) {
        liveSampler.stopNote(UInt8(clamping: pitch), onChannel: 0)
        // Filet de sécurité : certains soundfonts répondent mieux au note-off MIDI brut.
        liveSampler.sendMIDIEvent(0x80, data1: UInt8(clamping: pitch), data2: 0)
        liveVelocities.removeValue(forKey: pitch)
    }

    private func publishLivePitches() {
        livePitches = heldPitches.union(sustainedPitches)
    }

    private func clearAllLiveNotes() {
        for pitch in heldPitches.union(sustainedPitches).union(Set(liveVelocities.keys)) {
            liveSampler.stopNote(UInt8(clamping: pitch), onChannel: 0)
        }
        heldPitches.removeAll()
        sustainedPitches.removeAll()
        liveVelocities.removeAll()
        livePitches.removeAll()
        liveSampler.sendController(123, withValue: 0, onChannel: 0)
        liveSampler.sendController(64, withValue: 0, onChannel: 0)
    }

    private func playbackDidFinish() {
        isPlaying = false
        stopTimer()
        currentTime = duration
        sequencer?.stop()
        allNotesOff()
    }

    private func startTimer() {
        stopTimer()
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in self.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        displayTimer = timer
    }

    private func stopTimer() {
        displayTimer?.invalidate()
        displayTimer = nil
    }

    private func tick() {
        guard let seq = sequencer, isPlaying else { return }
        currentTime = seq.currentPositionInSeconds
        if currentTime >= duration - 0.01 {
            if isLooping {
                seq.currentPositionInSeconds = 0
                allNotesOff()
                currentTime = 0
                if !seq.isPlaying { try? seq.start() }
            } else {
                playbackDidFinish()
            }
        }
    }
}
