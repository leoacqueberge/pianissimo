#!/usr/bin/env python3
"""Pianissimo unified engine: Demucs separation + piano transcription -> MIDI.

Designed to run from embedded Python in the macOS app, with bundled models
(offline operation). All messages are written to stdout (line by line, immediate
flush) for live display in the app.
"""

import argparse
import os
import sys


def log(message):
    print(message, flush=True)


def find_piano_checkpoint(models_dir):
    piano_dir = os.path.join(models_dir, "piano")
    if os.path.isdir(piano_dir):
        for name in sorted(os.listdir(piano_dir)):
            if name.endswith(".pth"):
                return os.path.join(piano_dir, name)
    raise FileNotFoundError(
        "Piano transcription model not found in %s" % piano_dir
    )


def maybe_trim_input(input_path, output_dir, start, end):
    """Trim audio between start and end (seconds). Returns the path to process."""
    import librosa
    import soundfile as sf

    total = librosa.get_duration(path=input_path)
    if start is None:
        start = 0.0
    if end is None:
        end = total

    start = max(0.0, start)
    end = min(end, total)
    duration = end - start

    if duration <= 0:
        log("ERROR: invalid time range (%.1f s -> %.1f s)" % (start, end))
        sys.exit(2)

    log("Trimming audio: %.1f s -> %.1f s (%.1f s of %.1f s)" % (start, end, duration, total))

    trim_dir = os.path.join(output_dir, "_trim")
    os.makedirs(trim_dir, exist_ok=True)
    base = os.path.splitext(os.path.basename(input_path))[0]
    out_path = os.path.join(trim_dir, base + ".wav")

    audio, sr = librosa.load(input_path, sr=None, offset=start, duration=duration)
    sf.write(out_path, audio, sr)
    log("Trim saved: %s" % out_path)
    return out_path


def run_separation(input_path, output_dir):
    from demucs.separate import main as demucs_main

    os.makedirs(output_dir, exist_ok=True)
    demucs_main(["--mp3", "-n", "htdemucs", "-o", output_dir, input_path])

    name = os.path.splitext(os.path.basename(input_path))[0]
    stem_dir = os.path.join(output_dir, "htdemucs", name)
    other_stem = os.path.join(stem_dir, "other.mp3")
    log("Stems saved to: %s" % stem_dir)
    return other_stem


def run_transcription(audio_path, output_midi, models_dir):
    import librosa
    from piano_transcription_inference import PianoTranscription, sample_rate

    if not os.path.exists(audio_path):
        log("ERROR: audio file not found: %s" % audio_path)
        sys.exit(2)

    checkpoint = find_piano_checkpoint(models_dir)

    log("Loading audio (%s)..." % os.path.basename(audio_path))
    audio, _ = librosa.load(audio_path, sr=sample_rate)

    os.makedirs(os.path.dirname(os.path.abspath(output_midi)), exist_ok=True)

    log("Transcribing (CPU)... this may take several minutes.")
    transcriptor = PianoTranscription(device="cpu", checkpoint_path=checkpoint)
    transcriptor.transcribe(audio, output_midi)
    log("MIDI created: %s" % output_midi)


def main():
    parser = argparse.ArgumentParser(description="Pianissimo engine")
    parser.add_argument("--mode", required=True,
                        choices=["both", "separate", "transcribe"])
    parser.add_argument("--input", required=True, help="Source audio file")
    parser.add_argument("--output-dir", required=True,
                        help="Output directory for separated stems")
    parser.add_argument("--output-midi", default=None,
                        help="Output MIDI file path")
    parser.add_argument("--resources", required=True,
                        help="Resources directory containing 'models'")
    parser.add_argument("--start", type=float, default=None,
                        help="Start of segment to process (seconds)")
    parser.add_argument("--end", type=float, default=None,
                        help="End of segment to process (seconds)")
    args = parser.parse_args()

    models_dir = os.path.join(args.resources, "models")

    # Force offline operation on bundled models.
    os.environ["TORCH_HOME"] = os.path.join(models_dir, "torch")
    os.environ["HF_HUB_OFFLINE"] = "1"
    os.environ["TRANSFORMERS_OFFLINE"] = "1"
    # Avoid tokenizer/thread warnings in logs.
    os.environ.setdefault("TOKENIZERS_PARALLELISM", "false")

    if not os.path.exists(args.input):
        log("ERROR: input file not found: %s" % args.input)
        sys.exit(2)

    input_path = args.input
    if args.start is not None or args.end is not None:
        input_path = maybe_trim_input(args.input, args.output_dir, args.start, args.end)

    other_stem = None
    if args.mode in ("both", "separate"):
        log("STEP:Step 1: Separating stems with Demucs...")
        other_stem = run_separation(input_path, args.output_dir)

    if args.mode in ("both", "transcribe"):
        log("STEP:Step 2: Transcribing piano...")
        if args.output_midi is None:
            log("ERROR: --output-midi is required for transcription.")
            sys.exit(2)
        audio_for_transcription = other_stem if args.mode == "both" else input_path
        run_transcription(audio_for_transcription, args.output_midi, models_dir)

    log("DONE")


if __name__ == "__main__":
    main()
