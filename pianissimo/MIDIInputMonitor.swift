//
//  MIDIInputMonitor.swift
//  Pianissimo
//
//  Écoute les claviers MIDI branchés (CoreMIDI) et remonte note on / note off.
//  Les callbacks CoreMIDI arrivent hors du main thread : on republie sur le
//  main queue en FIFO (pas de Task concurrent, sinon note-off avant note-on).
//

import Foundation
import CoreMIDI

/// Surveille les sources MIDI externes et notifie chaque note jouée / relâchée.
final class MIDIInputMonitor: @unchecked Sendable {
    /// Appelé sur le main queue (ordre FIFO).
    var onNoteOn: (@MainActor (Int, Int) -> Void)?
    var onNoteOff: (@MainActor (Int) -> Void)?
    /// Pédale sustain (CC64), déjà corrigée selon la polarité.
    var onSustain: (@MainActor (Bool) -> Void)?
    var onSourcesChanged: (@MainActor (Int) -> Void)?

    /// Certaines pédales envoient 127 au repos (polarité inversée).
    var sustainInverted = false

    private var client = MIDIClientRef()
    private var inputPort = MIDIPortRef()
    private var isStarted = false

    func start() {
        guard !isStarted else {
            reconnectSources()
            return
        }

        let name = "Pianissimo" as CFString
        let status = MIDIClientCreateWithBlock(name, &client) { [weak self] notification in
            self?.handleNotification(notification)
        }
        guard status == noErr else { return }

        let portStatus = MIDIInputPortCreateWithProtocol(
            client,
            "Pianissimo Input" as CFString,
            MIDIProtocolID._1_0,
            &inputPort
        ) { [weak self] eventList, _ in
            self?.handle(eventList: eventList)
        }
        guard portStatus == noErr else { return }

        isStarted = true
        reconnectSources()
    }

    func stop() {
        guard isStarted else { return }
        let count = MIDIGetNumberOfSources()
        for i in 0..<count {
            MIDIPortDisconnectSource(inputPort, MIDIGetSource(i))
        }
        if inputPort != 0 {
            MIDIPortDispose(inputPort)
            inputPort = 0
        }
        if client != 0 {
            MIDIClientDispose(client)
            client = 0
        }
        isStarted = false
        DispatchQueue.main.async { [weak self] in
            self?.onSourcesChanged?(0)
        }
    }

    func reconnectSources() {
        guard isStarted, inputPort != 0 else { return }
        let count = MIDIGetNumberOfSources()
        for i in 0..<count {
            let src = MIDIGetSource(i)
            MIDIPortConnectSource(inputPort, src, nil)
        }
        DispatchQueue.main.async { [weak self] in
            self?.onSourcesChanged?(count)
        }
    }

    // MARK: - CoreMIDI

    private func handleNotification(_ notification: UnsafePointer<MIDINotification>) {
        switch notification.pointee.messageID {
        case .msgSetupChanged, .msgObjectAdded, .msgObjectRemoved:
            reconnectSources()
        default:
            break
        }
    }

    private func handle(eventList: UnsafePointer<MIDIEventList>) {
        // Parcourir la liste en place (pas de copie) pour un Next correct.
        for packetPtr in eventList.unsafeSequence() {
            let packet = packetPtr.pointee
            let wordCount = Int(packet.wordCount)
            guard wordCount > 0 else { continue }
            withUnsafePointer(to: packet.words) { wordsPtr in
                let raw = UnsafeRawPointer(wordsPtr).assumingMemoryBound(to: UInt32.self)
                for i in 0..<min(wordCount, 16) {
                    parseUMPWord(raw[i])
                }
            }
        }
    }

    private func parseUMPWord(_ word: UInt32) {
        let messageType = (word >> 28) & 0xF
        // 0x2 = MIDI 1.0 channel voice message (32-bit UMP)
        guard messageType == 0x2 else { return }

        let status = UInt8((word >> 16) & 0xFF)
        let data1 = Int((word >> 8) & 0xFF)
        let data2 = Int(word & 0xFF)
        let command = status & 0xF0

        switch command {
        case 0x90: // note on (velocity 0 = note off)
            guard (0...127).contains(data1) else { return }
            let pitch = data1
            if data2 > 0 {
                let velocity = data2
                post { self.onNoteOn?(pitch, velocity) }
            } else {
                post { self.onNoteOff?(pitch) }
            }
        case 0x80: // note off
            guard (0...127).contains(data1) else { return }
            let pitch = data1
            post { self.onNoteOff?(pitch) }
        case 0xB0: // control change
            if data1 == 64 {
                // Standard MIDI : ≥64 = enfoncée. Polarité inversée : l'inverse.
                let rawDown = data2 >= 64
                let down = sustainInverted ? !rawDown : rawDown
                post { self.onSustain?(down) }
            }
        default:
            break
        }
    }

    /// Main queue FIFO — conserve l'ordre note-on → note-off.
    private func post(_ body: @escaping @MainActor () -> Void) {
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                body()
            }
        }
    }

    deinit {
        if isStarted {
            if inputPort != 0 { MIDIPortDispose(inputPort) }
            if client != 0 { MIDIClientDispose(client) }
        }
    }
}
