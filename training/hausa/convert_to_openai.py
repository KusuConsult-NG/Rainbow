"""Turn a fine-tuned Hugging Face Whisper checkpoint into OpenAI's format.

    python convert_to_openai.py --hf runs/base --out runs/base/hausa.pt

sherpa-onnx's Whisper exporter (export_onnx.py) loads models with
`whisper.load_model`, which reads OpenAI's checkpoint layout. Training happens
in Hugging Face transformers, so the weights are renamed here: the reverse of
transformers' own convert_openai_to_hf.py.
"""

from __future__ import annotations

import argparse
import re
from pathlib import Path

import torch
from transformers import WhisperForConditionalGeneration

# Hugging Face name -> OpenAI name, applied in order.
RENAMES = [
    (r"^model\.encoder\.embed_positions\.weight$", "encoder.positional_embedding"),
    (r"^model\.decoder\.embed_positions\.weight$", "decoder.positional_embedding"),
    (r"^model\.decoder\.embed_tokens\.weight$", "decoder.token_embedding.weight"),
    (r"^model\.encoder\.layer_norm\.", "encoder.ln_post."),
    (r"^model\.decoder\.layer_norm\.", "decoder.ln."),
    (r"^model\.encoder\.conv", "encoder.conv"),
    (r"^model\.(encoder|decoder)\.layers\.(\d+)\.", r"\1.blocks.\2."),
    (r"\.self_attn\.q_proj\.", ".attn.query."),
    (r"\.self_attn\.k_proj\.", ".attn.key."),
    (r"\.self_attn\.v_proj\.", ".attn.value."),
    (r"\.self_attn\.out_proj\.", ".attn.out."),
    (r"\.self_attn_layer_norm\.", ".attn_ln."),
    (r"\.encoder_attn\.q_proj\.", ".cross_attn.query."),
    (r"\.encoder_attn\.k_proj\.", ".cross_attn.key."),
    (r"\.encoder_attn\.v_proj\.", ".cross_attn.value."),
    (r"\.encoder_attn\.out_proj\.", ".cross_attn.out."),
    (r"\.encoder_attn_layer_norm\.", ".cross_attn_ln."),
    (r"\.fc1\.", ".mlp.0."),
    (r"\.fc2\.", ".mlp.2."),
    (r"\.final_layer_norm\.", ".mlp_ln."),
]


def rename(key: str) -> str:
    for pattern, repl in RENAMES:
        key = re.sub(pattern, repl, key)
    return key


def main() -> None:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--hf", type=Path, required=True)
    p.add_argument("--out", type=Path, required=True)
    args = p.parse_args()

    model = WhisperForConditionalGeneration.from_pretrained(args.hf)
    c = model.config
    state = {}
    for k, v in model.state_dict().items():
        if k == "proj_out.weight":
            continue  # tied to the token embedding in OpenAI's model
        state[rename(k)] = v
    dims = {
        "n_mels": c.num_mel_bins,
        "n_vocab": c.vocab_size,
        "n_audio_ctx": c.max_source_positions,
        "n_audio_state": c.d_model,
        "n_audio_head": c.encoder_attention_heads,
        "n_audio_layer": c.encoder_layers,
        "n_text_ctx": c.max_target_positions,
        "n_text_state": c.d_model,
        "n_text_head": c.decoder_attention_heads,
        "n_text_layer": c.decoder_layers,
    }
    torch.save({"dims": dims, "model_state_dict": state}, args.out)

    # Prove it loads in OpenAI's code before anything is exported from it.
    import whisper

    m = whisper.load_model(str(args.out), device="cpu")
    print(f"wrote {args.out}: {sum(p.numel() for p in m.parameters()) / 1e6:.1f}M parameters, loads in openai-whisper")


if __name__ == "__main__":
    main()
