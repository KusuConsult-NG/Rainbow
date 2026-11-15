# Guardian's Hausa model (phase 3)

AI Emergency Guardian listens for calls for help on the phone itself. English
and Pidgin use a bundled model. No small offline Hausa model was accurate
enough, so this folder trains one, and the app downloads it when a person
switches Hausa on.

## The short version

Open `train_hausa.ipynb` in Google Colab or Kaggle with a T4 GPU and run it
top to bottom. It trains, measures, and publishes to Hugging Face. Then put the
address it prints in the app's `.env` before building:

```
GUARDIAN_HAUSA_MANIFEST_URL=https://huggingface.co/<repo>/resolve/main/manifest.json
```

The Guardian screen then offers *Download Hausa*. The app checks every file's
size and SHA-256 against the manifest (`lib/core/guardian/hausa_model.dart`).
Leave the variable blank and Guardian offers English and Pidgin only.

## The steps it runs

| Step | Script | What it does |
|---|---|---|
| 1 | `prepare_data.py` | Builds training lists from Google FLEURS Hausa (CC-BY-4.0) and any recordings shared from the app's Hausa recording screen. One in five of the recorded calls for help is held back for testing. |
| 2 | `train.py` | Fine-tunes Whisper (default `openai/whisper-base`) on Hausa, with the language fixed to Hausa. |
| 3 | `convert_to_openai.py` | Renames the weights to OpenAI's layout, which the exporter reads. It then loads the result in OpenAI's code. |
| 4 | `export_onnx.py` | sherpa-onnx's own Whisper exporter (Apache-2.0), vendored with three marked changes. It writes the int8 ONNX files the app runs. |
| 5 | `evaluate.py` | Transcribes the test sets with sherpa-onnx 2.0.1, the same runtime and version as the app, and reports the word error rate. |
| 6 | `publish.py` | Uploads the three files plus a `manifest.json` (sizes and SHA-256) to your Hugging Face repo. |

## What has been verified, and what has not

Run end to end on a CPU on 2026-11-15, with `whisper-tiny` for 20 steps on 80
FLEURS sentences. This was a smoke test of the plumbing, not a usable model:

- Training ran at about 2 s per step on 4 CPU cores.
- The converted checkpoint gives exactly the same encoder outputs and logits
  as the trained one (largest difference 0.0).
- The export produced `hausa-encoder.int8.onnx` (13 MB),
  `hausa-decoder.int8.onnx` (90 MB) and `hausa-tokens.txt`.
- sherpa-onnx transcribed Hausa with them at 0.08× real time. Accuracy, as
  expected after 20 steps: word error 0.97, character error 0.34. The output
  sounded like Hausa but was wrongly split into words.
- Reading app recordings, and `publish.py --dry-run`, both worked.

**Not yet done: the real training run.** Its accuracy is unknown until the
notebook runs on a GPU. The notebook says how to read the result before
publishing it.

## Size

A `whisper-tiny` model is about 103 MB to download, and `whisper-base`
somewhat more. Most of it is the decoder's vocabulary table, which int8
quantization leaves at full precision. Quantizing that table as well was
tried: it made the file larger, because the table is shared with the output
layer and ended up stored twice.

## Running a step by hand

```
python -m venv venv && . venv/bin/activate
pip install -r requirements.txt
python prepare_data.py --out data --recordings path/to/shared/recordings
python train.py --data data --model openai/whisper-base --out runs/hausa
python convert_to_openai.py --hf runs/hausa --out runs/hausa/hausa.pt
mkdir export && cd export && python ../export_onnx.py --model hausa --checkpoint ../runs/hausa/hausa.pt && cd ..
python evaluate.py --model-dir export --manifest data/test.jsonl --report export/report.json
HF_TOKEN=... python publish.py --model-dir export --repo your-org/guardian-hausa --report export/report.json
```

For a quick check that everything runs on a laptop, add `--max-steps 20
--batch 4 --limit 80` to `train.py` and `--limit 5` to `evaluate.py`.

## Licences

- **Google FLEURS:** CC-BY-4.0. Credit Google in anything published.
- **OpenAI Whisper:** MIT.
- **sherpa-onnx export script:** Apache-2.0.
- **Recordings from the app:** given with consent on the recording screen, for
  building and testing Guardian only.
- **Not used, and why:**
  - CLEAR-Global TWB Voice: a custom licence behind a login.
  - NaijaVoices: needs an account.

  Both could be added once their terms have been accepted.
