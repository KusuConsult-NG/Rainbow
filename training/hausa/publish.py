"""Publish an exported Hausa model to Hugging Face for the app to download.

    HF_TOKEN=... python publish.py --model-dir export/ --name hausa \\
        --repo your-org/guardian-hausa --report export/report.json

Uploads the three files the app needs and a manifest.json beside them:

    {"version": "...", "language": "ha", "files": [{"name", "size", "sha256"}],
     "wer": ..., "licence": ..., "trained_on": [...]}

The app downloads manifest.json first, then each file, and refuses any file
whose size or SHA-256 does not match, so a truncated or tampered download is
never loaded. Nothing else in the repo is touched.

The token needs write access to --repo only. It is read from HF_TOKEN and
never written anywhere.
"""

from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import os
from pathlib import Path

from huggingface_hub import HfApi

APP_FILES = ("encoder.int8.onnx", "decoder.int8.onnx", "tokens.txt")


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def main() -> None:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--model-dir", type=Path, required=True)
    p.add_argument("--name", default="hausa")
    p.add_argument("--repo", required=True, help="Hugging Face model repo, e.g. your-org/guardian-hausa")
    p.add_argument("--report", type=Path, default=None, help="evaluate.py's JSON for the test set")
    p.add_argument("--base-model", default="openai/whisper-base")
    p.add_argument("--dry-run", action="store_true", help="write manifest.json only, upload nothing")
    args = p.parse_args()

    files = []
    for suffix in APP_FILES:
        path = args.model_dir / f"{args.name}-{suffix}"
        if not path.exists():
            raise SystemExit(f"missing {path}: run export_onnx.py first")
        files.append({"name": path.name, "size": path.stat().st_size, "sha256": sha256(path)})

    report = json.loads(args.report.read_text()) if args.report else {}
    manifest = {
        "version": dt.datetime.now(dt.timezone.utc).strftime("%Y%m%d%H%M"),
        "language": "ha",
        "base_model": args.base_model,
        "files": files,
        "wer": report.get("wer"),
        "cer": report.get("cer"),
        "evaluated_on": report.get("manifest"),
        "licence": "Model weights derived from OpenAI Whisper (MIT). Trained on Google FLEURS "
        "(CC-BY-4.0) and recordings contributed through Plateau Eye with consent.",
        "trained_on": ["google/fleurs ha_ng (CC-BY-4.0)", "Plateau Eye contributed recordings"],
    }
    out = args.model_dir / "manifest.json"
    out.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(manifest, indent=2))
    if args.dry_run:
        print(f"dry run: wrote {out}, uploaded nothing")
        return

    token = os.environ.get("HF_TOKEN")
    if not token:
        raise SystemExit("set HF_TOKEN to a token with write access to the repo")
    api = HfApi(token=token)
    api.create_repo(args.repo, repo_type="model", exist_ok=True)
    for f in files:
        api.upload_file(path_or_fileobj=str(args.model_dir / f["name"]), path_in_repo=f["name"], repo_id=args.repo)
    api.upload_file(path_or_fileobj=str(out), path_in_repo="manifest.json", repo_id=args.repo)
    print(f"published to https://huggingface.co/{args.repo}")
    print(f"app download address: https://huggingface.co/{args.repo}/resolve/main/manifest.json")


if __name__ == "__main__":
    main()
