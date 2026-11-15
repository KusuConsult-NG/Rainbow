"""Measure an exported Hausa model the way the app will run it.

    python evaluate.py --model-dir export/ --name hausa --manifest data/test.jsonl

Loads the int8 ONNX files with sherpa-onnx, the runtime the app uses,
transcribes every recording in the manifest and reports the word error rate.
With --manifest data/test_distress.jsonl (calls for help recorded in the app
and held back from training), it also prints each transcript next to what was
said, which is what the Hausa distress rules will have to match.

Writes the numbers to --report as JSON so publish.py can record them with the
model.
"""

from __future__ import annotations

import argparse
import json
import sys
import time
from pathlib import Path

import jiwer
import sherpa_onnx
import soundfile as sf

sys.path.insert(0, str(Path(__file__).parent))
from prepare_data import normalize  # noqa: E402


def main() -> None:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--model-dir", type=Path, required=True)
    p.add_argument("--name", default="hausa")
    p.add_argument("--manifest", type=Path, required=True)
    p.add_argument("--limit", type=int, default=None)
    p.add_argument("--report", type=Path, default=None)
    p.add_argument("--show", action="store_true")
    args = p.parse_args()

    d, n = args.model_dir, args.name
    rec = sherpa_onnx.OfflineRecognizer.from_whisper(
        encoder=str(d / f"{n}-encoder.int8.onnx"),
        decoder=str(d / f"{n}-decoder.int8.onnx"),
        tokens=str(d / f"{n}-tokens.txt"),
        language="ha",
        task="transcribe",
        num_threads=2,
    )
    rows = [json.loads(l) for l in args.manifest.read_text(encoding="utf-8").splitlines() if l.strip()]
    rows = rows[: args.limit] if args.limit else rows
    if not rows:
        print(f"{args.manifest}: no recordings")
        return

    refs, hyps, audio_s = [], [], 0.0
    started = time.time()
    for row in rows:
        samples, rate = sf.read(row["audio"], dtype="float32")
        audio_s += len(samples) / rate
        s = rec.create_stream()
        s.accept_waveform(rate, samples)
        rec.decode_stream(s)
        hyp = normalize(s.result.text)
        refs.append(row["text"])
        hyps.append(hyp)
        if args.show:
            print(f"said:  {row['text']}\nheard: {hyp}\n")
    took = time.time() - started

    wer = jiwer.wer(refs, hyps)
    cer = jiwer.cer(refs, hyps)
    result = {
        "manifest": args.manifest.name,
        "recordings": len(rows),
        "wer": round(wer, 4),
        "cer": round(cer, 4),
        "real_time_factor": round(took / audio_s, 3),
    }
    print(json.dumps(result, indent=2))
    if args.report:
        args.report.write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
