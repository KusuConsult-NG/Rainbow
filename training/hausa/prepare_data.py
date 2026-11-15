"""Build the Hausa training manifests for train.py.

    python prepare_data.py --out data/ [--recordings path/to/shared/recordings ...]

Sources, all checked for licence before use:

- Google FLEURS, Hausa (ha_ng): CC-BY-4.0, about 3,300 read sentences.
  Downloaded from Hugging Face unless --fleurs points at a copy.
- Recordings shared from the app's "Help build Guardian for Hausa" screen:
  WAV files plus the labels.csv it writes (file,expect,lang,text). These are
  the only ones with actual calls for help in them, so they matter most, and
  every speaker agreed to their use on that screen.

Writes train.jsonl, dev.jsonl and test.jsonl, one {"audio", "text"} object per
line. App recordings go to train, except one in five of the calls for help,
held back in test_distress.jsonl so the distress phrases are also measured on
voices the model has not trained on.
"""

from __future__ import annotations

import argparse
import csv
import json
import re
import tarfile
import urllib.request
from pathlib import Path

FLEURS = "https://huggingface.co/datasets/google/fleurs/resolve/main/data/ha_ng"


def normalize(text: str) -> str:
    """Lower case, Hausa letters kept (ɓ ɗ ƙ ƴ), punctuation dropped.

    The same rule the app applies to what the model hears, so training text
    and runtime text agree.
    """
    text = text.lower().replace("’", "'").replace("ʼ", "'")
    text = re.sub(r"[^0-9a-zɓɗƙƴ' ]+", " ", text)
    return re.sub(r"\s+", " ", text).strip()


def fetch(url: str, dest: Path) -> None:
    if dest.exists():
        return
    print(f"downloading {url}")
    tmp = dest.with_suffix(dest.suffix + ".part")
    urllib.request.urlretrieve(url, tmp)
    tmp.rename(dest)


def fleurs(root: Path, download: bool) -> dict[str, list[dict]]:
    out: dict[str, list[dict]] = {}
    for split in ("train", "dev", "test"):
        tsv = root / f"{split}.tsv"
        audio = root / split
        if download:
            root.mkdir(parents=True, exist_ok=True)
            fetch(f"{FLEURS}/{split}.tsv", tsv)
            if not audio.is_dir():
                tgz = root / f"{split}.tar.gz"
                fetch(f"{FLEURS}/audio/{split}.tar.gz", tgz)
                with tarfile.open(tgz) as t:
                    t.extractall(root, filter="data")
                tgz.unlink()
        rows = []
        for line in tsv.read_text(encoding="utf-8").splitlines():
            cols = line.split("\t")
            if len(cols) < 4:
                continue
            wav = audio / cols[1]
            if wav.exists():
                rows.append({"audio": str(wav.resolve()), "text": normalize(cols[3])})
        out[split] = rows
        print(f"FLEURS {split}: {len(rows)} sentences")
    return out


def app_recordings(dirs: list[Path]) -> tuple[list[dict], list[dict]]:
    """Recordings shared from the app: (for training, held back for testing)."""
    train, held = [], []
    for d in dirs:
        labels = d / "labels.csv"
        if not labels.exists():
            print(f"skipping {d}: no labels.csv")
            continue
        with labels.open(encoding="utf-8") as f:
            for i, row in enumerate(csv.DictReader(f)):
                wav = d / row["file"]
                if not wav.exists() or not row.get("text"):
                    continue
                item = {"audio": str(wav.resolve()), "text": normalize(row["text"]), "expect": row["expect"]}
                (held if row["expect"] == "sos" and i % 5 == 4 else train).append(item)
    print(f"app recordings: {len(train)} for training, {len(held)} held back")
    return train, held


def write(path: Path, rows: list[dict]) -> None:
    path.write_text("".join(json.dumps(r, ensure_ascii=False) + "\n" for r in rows), encoding="utf-8")


def main() -> None:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--out", type=Path, required=True)
    p.add_argument("--fleurs", type=Path, default=None, help="existing FLEURS ha_ng copy; downloaded if omitted")
    p.add_argument("--recordings", type=Path, nargs="*", default=[])
    args = p.parse_args()

    args.out.mkdir(parents=True, exist_ok=True)
    root = args.fleurs or args.out / "fleurs"
    splits = fleurs(root, download=args.fleurs is None)
    extra, held = app_recordings(args.recordings)

    write(args.out / "train.jsonl", splits["train"] + extra)
    write(args.out / "dev.jsonl", splits["dev"])
    write(args.out / "test.jsonl", splits["test"])
    write(args.out / "test_distress.jsonl", held)
    print(f"wrote manifests to {args.out}")


if __name__ == "__main__":
    main()
