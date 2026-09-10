#!/usr/bin/env python3
"""Pianissimo unified engine: Demucs separation + piano transcription -> MIDI.

Designed to run from embedded Python in the macOS app, with bundled models
(offline operation). All messages are written to stdout (line by line, immediate
flush) for live display in the app.
"""

import argparse
import os
import shutil
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


def pick_device():
    """Prefer Apple GPU (MPS), then CUDA, else CPU."""
    try:
        import torch
        if hasattr(torch.backends, "mps") and torch.backends.mps.is_available():
            return "mps"
        if torch.cuda.is_available():
            return "cuda"
    except Exception:
        pass
    return "cpu"


def maybe_trim_input(input_path, output_dir, start, end):
    """Trim audio between start and end (seconds). Returns (path, trim_dir_or_None)."""
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
    return out_path, trim_dir


def run_separation(input_path, output_dir, stem_name=None):
    from demucs.separate import main as demucs_main

    os.makedirs(output_dir, exist_ok=True)
    model = "htdemucs_6s"
    demucs_main(["--mp3", "-n", model, "-o", output_dir, input_path])

    name = stem_name or os.path.splitext(os.path.basename(input_path))[0]
    stem_dir = os.path.join(output_dir, model, name)
    log("Stems saved to: %s" % stem_dir)

    piano = os.path.join(stem_dir, "piano.mp3")
    if os.path.isfile(piano):
        log("Using piano stem: %s" % piano)
        return piano

    other = os.path.join(stem_dir, "other.mp3")
    if os.path.isfile(other):
        log("WARNING: piano stem missing, falling back to other: %s" % other)
        return other

    log("ERROR: no usable stem found in %s" % stem_dir)
    sys.exit(2)


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

    os.environ.setdefault("PYTORCH_ENABLE_MPS_FALLBACK", "1")
    device = pick_device()
    log("Transcribing (%s)... this may take several minutes." % device)

    def transcribe_on(dev):
        transcriptor = PianoTranscription(device=dev, checkpoint_path=checkpoint)
        # piano_transcription_inference only .to()'s CUDA devices.
        if dev not in ("cpu",):
            transcriptor.model.to(dev)
        transcriptor.transcribe(audio, output_midi)

    try:
        transcribe_on(device)
    except Exception as exc:
        if device != "cpu":
            log("GPU transcription failed (%s), retrying on CPU..." % exc)
            transcribe_on("cpu")
        else:
            raise

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

    original_name = os.path.splitext(os.path.basename(args.input))[0]
    input_path = args.input
    trim_dir = None
    try:
        if args.start is not None or args.end is not None:
            input_path, trim_dir = maybe_trim_input(
                args.input, args.output_dir, args.start, args.end
            )

        other_stem = None
        if args.mode in ("both", "separate"):
            log("STEP:Step 1: Isolating the piano with Demucs...")
            other_stem = run_separation(
                input_path, args.output_dir, stem_name=original_name
            )

        if args.mode in ("both", "transcribe"):
            log("STEP:Step 2: Transcribing piano...")
            if args.output_midi is None:
                log("ERROR: --output-midi is required for transcription.")
                sys.exit(2)
            audio_for_transcription = other_stem if args.mode == "both" else input_path
            run_transcription(audio_for_transcription, args.output_midi, models_dir)

        log("DONE")
    finally:
        if trim_dir and os.path.isdir(trim_dir):
            shutil.rmtree(trim_dir, ignore_errors=True)


if __name__ == "__main__":
    main()
