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

Check the published model from the repository before building, the way a
phone will, and let it write that line for you:

```
dart run tool/verify_hausa_manifest.dart https://huggingface.co/<repo>/resolve/main/manifest.json --env .env
```

It downloads every file and checks each size and SHA-256 with the app's own
code (`lib/core/guardian/hausa_model.dart`). It refuses a model above 0.50
word error, or one with no word error recorded. Only then does it write the
address. Without `--env` it only checks.

The Guardian screen then offers *Download Hausa*. The app makes the same
checks on the phone.
Leave the variable blank and Guardian offers English and Pidgin only.

## The steps it runs

| Step | Script | What it does |
|---|---|---|
| 1 | `prepare_data.py` | Builds training lists from Google FLEURS Hausa (CC-BY-4.0) and any recordings shared from the app's Hausa recording screen. One in five of the recorded calls for help is held back for testing. |
| 2 | `train.py` | Fine-tunes Whisper (default `openai/whisper-base`) on Hausa, with the language fixed to Hausa. |
| 3 | `convert_to_openai.py` | Renames the weights to OpenAI's layout, which the exporter reads. It then loads the result in OpenAI's code. |
| 4 | `export_onnx.py` | sherpa-onnx's own Whisper exporter (Apache-2.0), vendored with changes marked `GUARDIAN`. It writes the int8 ONNX files the app runs. |
| 5 | `evaluate.py` | Transcribes the test sets with sherpa-onnx 2.0.1, the same runtime and version as the app, and reports the word error rate. |
| 6 | `publish.py` | Uploads the three files plus a `manifest.json` (sizes and SHA-256) to your Hugging Face repo. It refuses when word error is above 0.50 (`--force` overrides), and lists in the manifest what the model was trained on. |

## What has been verified, and what has not

Run end to end on a CPU on 2026-11-15, with `whisper-tiny` for 20 steps on 80
FLEURS sentences. This was a smoke test of the plumbing, not a usable model:

- Training ran at about 2 s per step on 4 CPU cores.
- The converted checkpoint gives exactly the same encoder outputs and logits
  as the trained one (largest difference 0.0).
- The export produced `hausa-encoder.int8.onnx` (13 MB),
  `hausa-decoder.int8.onnx` (90 MB then; 50 MB since the change under
  *Size and speed*) and `hausa-tokens.txt`.
- sherpa-onnx transcribed Hausa with them at 0.08× real time. Accuracy, as
  expected after 20 steps: word error 0.97, character error 0.34. The output
  sounded like Hausa but was wrongly split into words.
- Reading app recordings, and `publish.py --dry-run`, both worked.

Rehearsed again on 2026-11-16 with the notebook's own commands and
`whisper-base`, its default. This time training took the real run's path: no
`--max-steps`, so it evaluated and saved after each epoch, warmed up, and
reloaded the best checkpoint at the end. (Two epochs on 96 sentences, CPU.)
- Training: 6 GB peak memory on a CPU; dev loss fell from 3.23 to 2.94.
- Convert, export, evaluate (0.14x real time on 2 threads) and
  `publish.py --dry-run` all worked on the result.
- The export is about 107 MB.
- The rehearsal found that the notebook cloned `main` before this code was
  merged; it now has a `BRANCH` setting.

**Not yet done: the real training run.** Its accuracy is unknown until the
notebook runs on a GPU. The notebook says how to read the result before
publishing it.

## Size and speed

A `whisper-tiny` model is about 63 MB to download, and a `whisper-base` model
(the notebook's default) about 107 MB: a 29 MB encoder and a 78 MB decoder.

Most of the decoder is its table of 51,865 word pieces. sherpa-onnx's
exporter uses that one table twice:
- to look up each word piece going in;
- to score every word piece coming out, at every decoding step.

The second use stopped int8 quantization from reaching the table, so it
stayed in 32-bit floats, and the scoring step was most of the decoder's time.
`export_onnx.py` now gives the scoring step its own copy of the table, and
quantizes both copies to int8.

Measured on 2026-11-15 with stock `whisper-tiny`, one CPU thread, through
sherpa-onnx 2.0.1:

| | Before | After |
|---|---|---|
| Decoder file | 90 MB | 50 MB |
| Time per word piece | 34 ms | 23 ms |
| Word error, 60 English FLEURS clips | 0.40 | 0.35 |

English was used because stock Whisper can't transcribe Hausa, so on Hausa
there is nothing to compare. Run `evaluate.py` on the trained model as usual.

**Tried, and not used:** less trailing silence for sherpa-onnx's Whisper
(`tail_paddings`, 10 s by default). It saved no time and raised word error from
0.35 to 0.54 at 5 s.

## Running a step by hand

```
python -m venv venv && . venv/bin/activate
pip install -r requirements.txt
python prepare_data.py --out data --recordings path/to/shared/recordings
python train.py --data data --model openai/whisper-base --out runs/hausa
python convert_to_openai.py --hf runs/hausa --out runs/hausa/hausa.pt
mkdir export && cd export && python ../export_onnx.py --model hausa --checkpoint ../runs/hausa/hausa.pt && cd ..
python evaluate.py --model-dir export --manifest data/test.jsonl --report export/report.json
HF_TOKEN=... python publish.py --model-dir export --repo your-org/guardian-hausa --report export/report.json --data data
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
