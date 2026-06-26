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

    @Published var rate: Float = 1.0 {
        didSet { sequencer?.rate = rate }
    }
    @Published var volume: Float = 0.8 {
        didSet { applyVolume() }
    }
    @Published var isMuted = false {
        didSet { applyVolume() }
    }

    private let engine = AVAudioEngine()
    private let sampler = AVAudioUnitSampler()
    private var sequencer: AVAudioSequencer?
    private var displayTimer: Timer?

    var usingBundledSoundFont: Bool { MIDIPlayerEngine.bundledSoundFont() != nil }

    init() {
        engine.attach(sampler)
        try? engine.connectNode(sampler, to: engine.mainMixerNode, format: nil)
        applyVolume()
        loadSoundFont()
        try? engine.start()
    }

    deinit { displayTimer?.invalidate() }

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
        try? sampler.loadSoundBankInstrument(at: url, program: 0,
                                             bankMSB: 0x79, bankLSB: 0x00)
    }

    private func applyVolume() {
        engine.mainMixerNode.outputVolume = isMuted ? 0 : volume
    }

    func load(url: URL) {
        stop()
        fileName = url.lastPathComponent
        sourceURL = url
        loadError = nil

        do {
            let parsed = try MIDIFile.parse(url: url)
            notes = parsed.notes
            duration = parsed.duration
        } catch {
            notes = []
            duration = 0
            loadError = error.localizedDescription
        }

        sequencer = nil
        if !engine.isRunning { try? engine.start() }

        let seq = AVAudioSequencer(audioEngine: engine)
        do {
            try seq.load(from: url, options: [])
            for track in seq.tracks {
                track.destinationAudioUnit = sampler
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

        currentTime = 0
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
        for channel in UInt8(0)..<16 {
            sampler.sendController(123, withValue: 0, onChannel: channel)
        }
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
