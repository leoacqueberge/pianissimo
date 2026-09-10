//
//  WaveformSampler.swift
//  Pianissimo
//

import AVFoundation

enum WaveformSampler {
    /// Downsampled peak amplitudes for a lightweight waveform preview.
    /// Each bar maps to a contiguous time slice of the file (left → right = start → end).
    static func loadSamples(from url: URL, barCount: Int = 72) async -> [Float] {
        let asset = AVURLAsset(url: url)
        guard let track = try? await asset.loadTracks(withMediaType: .audio).first else {
            return placeholder(count: barCount)
        }

        let durationSeconds: Double
        do {
            let time = try await asset.load(.duration)
            durationSeconds = CMTimeGetSeconds(time)
        } catch {
            return placeholder(count: barCount)
        }
        guard durationSeconds.isFinite, durationSeconds > 0 else {
            return placeholder(count: barCount)
        }

        var channelCount = 2
        var sampleRate = 44100.0
        let formatDescriptions = (try? await track.load(.formatDescriptions)) ?? []
        for desc in formatDescriptions {
            if let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(desc)?.pointee {
                channelCount = max(1, Int(asbd.mChannelsPerFrame))
                if asbd.mSampleRate > 0 {
                    sampleRate = asbd.mSampleRate
                }
            }
        }
        let totalFrames = max(1, Int((durationSeconds * sampleRate).rounded(.up)))

        let reader: AVAssetReader
        do {
            reader = try AVAssetReader(asset: asset)
        } catch {
            return placeholder(count: barCount)
        }

        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsNonInterleaved: false
        ]

        let output = AVAssetReaderTrackOutput(track: track, outputSettings: outputSettings)
        let provider = reader.outputProvider(for: output)

        do {
            try reader.start()
        } catch {
            return placeholder(count: barCount)
        }

        var peaks = [Float](repeating: 0, count: barCount)
        var frameIndex = 0

        do {
            while let readySampleBuffer = try await provider.next() {
                readySampleBuffer.withUnsafeSampleBuffer { sampleBuffer in
                    guard let block = CMSampleBufferGetDataBuffer(sampleBuffer) else { return }

                    let length = CMBlockBufferGetDataLength(block)
                    var data = Data(count: length)
                    data.withUnsafeMutableBytes { ptr in
                        guard let base = ptr.baseAddress else { return }
                        CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: length, destination: base)
                    }

                    let sampleCount = length / MemoryLayout<Int16>.size
                    data.withUnsafeBytes { raw in
                        let samples = raw.bindMemory(to: Int16.self)
                        var i = 0
                        while i < sampleCount {
                            let frame = min(frameIndex, totalFrames - 1)
                            let bar = min(barCount - 1, frame * barCount / totalFrames)
                            let normalized = abs(Float(samples[i]) / Float(Int16.max))
                            peaks[bar] = max(peaks[bar], normalized)
                            i += channelCount
                            frameIndex += 1
                        }
                    }
                }
            }
        } catch {
            return placeholder(count: barCount)
        }

        if peaks.allSatisfy({ $0 == 0 }) {
            return placeholder(count: barCount)
        }

        let maxPeak = peaks.max() ?? 1
        return peaks.map { min(1, ($0 / maxPeak) * 0.92 + 0.08) }
    }

    private static func placeholder(count: Int) -> [Float] {
        (0..<count).map { i in
            Float(0.2 + 0.6 * abs(sin(Double(i) * 0.35)))
        }
    }
}
