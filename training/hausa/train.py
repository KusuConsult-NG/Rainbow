"""Fine-tune Whisper on Hausa for AI Emergency Guardian (phase 3).

    python train.py --data data/ --model openai/whisper-base --out runs/base

Reads the manifests prepare_data.py writes (train.jsonl, dev.jsonl), trains
with the language fixed to Hausa and the task to transcription, and saves a
Hugging Face checkpoint to --out. convert_to_openai.py and export_onnx.py
turn that into the files the app downloads.

Runs on a CPU for a smoke test (--max-steps 20) and on a GPU for real; the
Colab notebook calls it with GPU settings.
"""

from __future__ import annotations

import argparse
import json
from dataclasses import dataclass
from pathlib import Path

import soundfile as sf
import torch
from torch.utils.data import Dataset
from transformers import (
    Seq2SeqTrainer,
    Seq2SeqTrainingArguments,
    WhisperForConditionalGeneration,
    WhisperProcessor,
)

LANGUAGE = "hausa"
SAMPLE_RATE = 16000


class Manifest(Dataset):
    """One JSON object per line: {"audio": path, "text": transcript}."""

    def __init__(self, path: Path, processor: WhisperProcessor, limit: int | None = None):
        rows = [json.loads(l) for l in path.read_text(encoding="utf-8").splitlines() if l.strip()]
        self.rows = rows[:limit] if limit else rows
        self.base = path.parent
        self.processor = processor

    def __len__(self) -> int:
        return len(self.rows)

    def __getitem__(self, i: int) -> dict:
        row = self.rows[i]
        audio, rate = sf.read(self.base / row["audio"], dtype="float32")
        if rate != SAMPLE_RATE:
            raise ValueError(f"{row['audio']}: {rate} Hz; prepare_data.py writes 16 kHz")
        features = self.processor.feature_extractor(
            audio, sampling_rate=SAMPLE_RATE
        ).input_features[0]
        labels = self.processor.tokenizer(row["text"]).input_ids
        return {"input_features": features, "labels": labels}


@dataclass
class Collator:
    processor: WhisperProcessor
    decoder_start: int

    def __call__(self, batch: list[dict]) -> dict:
        feats = self.processor.feature_extractor.pad(
            [{"input_features": b["input_features"]} for b in batch], return_tensors="pt"
        )
        labels = self.processor.tokenizer.pad(
            [{"input_ids": b["labels"]} for b in batch], return_tensors="pt"
        )
        ids = labels["input_ids"].masked_fill(labels.attention_mask.ne(1), -100)
        # The tokenizer adds the start token; the model adds it again.
        if (ids[:, 0] == self.decoder_start).all().item():
            ids = ids[:, 1:]
        feats["labels"] = ids
        return feats


def main() -> None:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--data", type=Path, required=True, help="folder with train.jsonl and dev.jsonl")
    p.add_argument("--model", default="openai/whisper-base")
    p.add_argument("--out", type=Path, required=True)
    p.add_argument("--epochs", type=float, default=5)
    p.add_argument("--max-steps", type=int, default=-1, help="stop early; 20 is a smoke test")
    p.add_argument("--batch", type=int, default=16)
    p.add_argument("--lr", type=float, default=1e-5)
    p.add_argument("--limit", type=int, default=None, help="use only the first N training rows")
    args = p.parse_args()

    processor = WhisperProcessor.from_pretrained(args.model, language=LANGUAGE, task="transcribe")
    model = WhisperForConditionalGeneration.from_pretrained(args.model)
    model.generation_config.language = LANGUAGE
    model.generation_config.task = "transcribe"
    model.generation_config.forced_decoder_ids = None

    train = Manifest(args.data / "train.jsonl", processor, args.limit)
    dev = Manifest(args.data / "dev.jsonl", processor, 64 if args.limit else None)
    gpu = torch.cuda.is_available()

    training_args = Seq2SeqTrainingArguments(
        output_dir=str(args.out),
        per_device_train_batch_size=args.batch,
        per_device_eval_batch_size=args.batch,
        learning_rate=args.lr,
        warmup_steps=0 if args.max_steps > 0 else 200,
        num_train_epochs=args.epochs,
        max_steps=args.max_steps,
        fp16=gpu,
        eval_strategy="epoch" if args.max_steps < 0 else "no",
        save_strategy="epoch" if args.max_steps < 0 else "no",
        save_total_limit=1,
        load_best_model_at_end=args.max_steps < 0,
        metric_for_best_model="eval_loss",
        logging_steps=10,
        report_to=[],
        remove_unused_columns=False,
        dataloader_num_workers=2 if gpu else 0,
    )
    trainer = Seq2SeqTrainer(
        model=model,
        args=training_args,
        train_dataset=train,
        eval_dataset=dev,
        data_collator=Collator(processor, model.config.decoder_start_token_id),
    )
    trainer.train()
    trainer.save_model(str(args.out))
    processor.save_pretrained(str(args.out))
    print(f"saved to {args.out}")


if __name__ == "__main__":
    main()
