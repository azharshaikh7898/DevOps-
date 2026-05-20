import os
from functools import lru_cache

import torch
from transformers import AutoModelForCausalLM, AutoTokenizer
from iii_sdk import InitOptions, register_worker

MODEL_PATH = os.environ.get("MODEL_PATH", "/opt/models/gemma-3-270m")
DEVICE = "cuda" if torch.cuda.is_available() else "cpu"


@lru_cache(maxsize=1)
def load_model():
    tokenizer = AutoTokenizer.from_pretrained(MODEL_PATH, trust_remote_code=True)
    model = AutoModelForCausalLM.from_pretrained(
        MODEL_PATH,
        torch_dtype=torch.float16 if DEVICE == "cuda" else torch.float32,
        device_map="auto" if DEVICE == "cuda" else None,
        trust_remote_code=True,
    )
    model.eval()
    return tokenizer, model


def run_inference_handler(payload):
    tokenizer, model = load_model()
    prompt = payload.get("prompt") or payload.get("body") or payload.get("text") or "Say hello from III."

    inputs = tokenizer(prompt, return_tensors="pt")
    model_device = next(model.parameters()).device
    inputs = {key: value.to(model_device) for key, value in inputs.items()}

    with torch.no_grad():
        output_tokens = model.generate(
            **inputs,
            max_new_tokens=int(payload.get("max_new_tokens", 128)),
            temperature=float(payload.get("temperature", 0.7)),
            do_sample=True,
        )

    response_text = tokenizer.decode(output_tokens[0], skip_special_tokens=True)

    return {
        "success": True,
        "model": MODEL_PATH,
        "device": DEVICE,
        "response": response_text,
    }


iii = register_worker(
    os.environ.get("III_URL", "ws://iii-engine.iii.internal:49134"),
    InitOptions(worker_name="inference-worker"),
)

iii.register_function("inference::run_inference", run_inference_handler)
