# Guardian's offline speech models

These files let AI Emergency Guardian turn speech into text on the phone
itself, with no network. Nothing heard leaves the device.

## Speech recognizer: zipformer transducer, English, small, int8

- Files: `encoder-epoch-99-avg-1.int8.onnx`, `decoder-epoch-99-avg-1.int8.onnx`,
  `joiner-epoch-99-avg-1.int8.onnx`, `tokens.txt`
- Source: https://huggingface.co/csukuangfj/sherpa-onnx-zipformer-small-en-2023-06-26
  (k2-fsa / icefall, exported for sherpa-onnx)
- Licence: Apache License 2.0

## Voice activity detector: Silero VAD

- File: `silero_vad.onnx`
- Source: https://github.com/k2-fsa/sherpa-onnx/releases/tag/asr-models
  (from https://github.com/snakers4/silero-vad)
- Licence: MIT

## Runtime

- `sherpa_onnx` (Apache License 2.0), which bundles ONNX Runtime (MIT).

## Checksums (SHA-256)

Recorded so a changed file is noticed; `test/guardian_model_assets_test.dart`
checks them.

```
3a6ac78a31cc2c60ca8c1e2e2f43c878fbbcaf051ada4900e0a42ef8ba53d375  encoder-epoch-99-avg-1.int8.onnx
f462ab9189ba6f9b2658774e6bf3d651913de54a3833655dc5e093e2f5e4c2b6  decoder-epoch-99-avg-1.int8.onnx
6b183b6ec656e4d3ca6b86d0aeca992dac14df80aae6b416d7c068d0ff2bd4d7  joiner-epoch-99-avg-1.int8.onnx
49e3c2646595fd907228b3c6787069658f67b17377c60aeb8619c4551b2316fb  tokens.txt
9e2449e1087496d8d4caba907f23e0bd3f78d91fa552479bb9c23ac09cbb1fd6  silero_vad.onnx
```
