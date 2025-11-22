#!/usr/bin/env python3
"""
Simplified training without LoRA - fine-tune last layers only.
This avoids PEFT/ROCm compatibility issues.
"""

import json
import torch
from pathlib import Path
from dataclasses import dataclass
from typing import List

from transformers import (
    AutoModelForCausalLM,
    AutoTokenizer,
    TrainingArguments,
    Trainer,
    DataCollatorForLanguageModeling,
)
from datasets import Dataset
import numpy as np


@dataclass
class TrainingConfig:
    """Training configuration."""
    # Model
    base_model: str = "mistralai/Mistral-7B-Instruct-v0.2"
    output_dir: str = "models/ec4x-mistral-7b-simple"

    # Training hyperparameters
    num_train_epochs: int = 3
    per_device_train_batch_size: int = 1  # Smaller for full model
    gradient_accumulation_steps: int = 16  # Effective batch size = 1 * 16 = 16
    learning_rate: float = 1e-5  # Lower LR for full model fine-tuning
    max_grad_norm: float = 0.3
    warmup_ratio: float = 0.03
    lr_scheduler_type: str = "cosine"

    # Optimization
    optim: str = "adamw_torch"
    weight_decay: float = 0.001
    max_seq_length: int = 512  # Shorter sequences to fit in memory

    # Checkpointing
    save_steps: int = 100
    save_total_limit: int = 3
    logging_steps: int = 10

    # Data
    train_data_file: str = "training_data/training_dataset_processed.json"
    validation_split: float = 0.05  # 5% for validation

    # Freeze all but last N layers
    num_trainable_layers: int = 4  # Only train last 4 layers


def load_training_data(config: TrainingConfig):
    """Load and prepare training dataset."""
    print("Loading training data...")

    data_path = Path(config.train_data_file)
    with open(data_path) as f:
        data = json.load(f)

    examples = data["examples"]
    print(f"  Loaded {len(examples)} examples")

    # Split into train/validation
    np.random.seed(42)
    np.random.shuffle(examples)

    split_idx = int(len(examples) * (1 - config.validation_split))
    train_examples = examples[:split_idx]
    val_examples = examples[split_idx:]

    print(f"  Train: {len(train_examples)}")
    print(f"  Validation: {len(val_examples)}")

    train_dataset = Dataset.from_list(train_examples)
    val_dataset = Dataset.from_list(val_examples)

    return train_dataset, val_dataset


def tokenize_dataset(dataset: Dataset, tokenizer, max_length: int) -> Dataset:
    """Tokenize dataset for training."""
    def tokenize_function(examples):
        tokenized = tokenizer(
            examples["text"],
            truncation=True,
            max_length=max_length,
            padding=False,
        )
        tokenized["labels"] = tokenized["input_ids"].copy()
        return tokenized

    print("Tokenizing dataset...")
    tokenized_dataset = dataset.map(
        tokenize_function,
        batched=True,
        remove_columns=dataset.column_names,
        desc="Tokenizing"
    )

    return tokenized_dataset


def setup_model_and_tokenizer(config: TrainingConfig):
    """Load model and freeze all but last N layers."""
    print(f"\nLoading base model: {config.base_model}")

    # Load tokenizer
    tokenizer = AutoTokenizer.from_pretrained(config.base_model)
    if tokenizer.pad_token is None:
        tokenizer.pad_token = tokenizer.eos_token
        tokenizer.pad_token_id = tokenizer.eos_token_id

    print(f"  Tokenizer vocabulary size: {len(tokenizer)}")

    # Load model
    print("  Loading model in FP16...")
    model = AutoModelForCausalLM.from_pretrained(
        config.base_model,
        device_map="auto",
        torch_dtype=torch.float16,
        trust_remote_code=True,
    )

    print(f"  Model loaded on: {model.device}")
    print(f"  Model dtype: {model.dtype}")

    # Freeze all parameters first
    print(f"\nFreezing all but last {config.num_trainable_layers} layers...")
    for param in model.parameters():
        param.requires_grad = False

    # Unfreeze last N decoder layers
    num_layers = len(model.model.layers)
    trainable_start = num_layers - config.num_trainable_layers

    for i in range(trainable_start, num_layers):
        for param in model.model.layers[i].parameters():
            param.requires_grad = True

    # Also unfreeze the language model head
    for param in model.lm_head.parameters():
        param.requires_grad = True

    # Count trainable parameters
    total_params = sum(p.numel() for p in model.parameters())
    trainable_params = sum(p.numel() for p in model.parameters() if p.requires_grad)

    print(f"  Total parameters: {total_params:,}")
    print(f"  Trainable parameters: {trainable_params:,} ({100 * trainable_params / total_params:.2f}%)")

    return model, tokenizer


def train(config: TrainingConfig):
    """Main training loop."""
    print("=" * 70)
    print("EC4X Model Training (Simplified)")
    print("=" * 70)
    print()

    # Check GPU
    print("GPU Information:")
    if torch.cuda.is_available():
        print(f"  Device count: {torch.cuda.device_count()}")
        print(f"  Device name: {torch.cuda.get_device_name(0)}")
        memory_gb = torch.cuda.get_device_properties(0).total_memory / 1e9
        print(f"  Total memory: {memory_gb:.1f} GB")
    else:
        print("  WARNING: No GPU detected")
    print()

    # Load data
    train_dataset, val_dataset = load_training_data(config)

    # Setup model
    model, tokenizer = setup_model_and_tokenizer(config)

    # Tokenize
    train_dataset_tokenized = tokenize_dataset(train_dataset, tokenizer, config.max_seq_length)
    val_dataset_tokenized = tokenize_dataset(val_dataset, tokenizer, config.max_seq_length)

    # Data collator
    data_collator = DataCollatorForLanguageModeling(
        tokenizer=tokenizer,
        mlm=False,
    )

    # Training arguments
    output_dir = Path(config.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    training_args = TrainingArguments(
        output_dir=str(output_dir),
        num_train_epochs=config.num_train_epochs,
        per_device_train_batch_size=config.per_device_train_batch_size,
        per_device_eval_batch_size=config.per_device_train_batch_size,
        gradient_accumulation_steps=config.gradient_accumulation_steps,
        learning_rate=config.learning_rate,
        max_grad_norm=config.max_grad_norm,
        warmup_ratio=config.warmup_ratio,
        lr_scheduler_type=config.lr_scheduler_type,
        optim=config.optim,
        weight_decay=config.weight_decay,
        fp16=True,
        save_steps=config.save_steps,
        save_total_limit=config.save_total_limit,
        logging_steps=config.logging_steps,
        eval_strategy="steps",
        eval_steps=config.save_steps,
        load_best_model_at_end=True,
        metric_for_best_model="eval_loss",
        greater_is_better=False,
        report_to=[],
        save_safetensors=True,
    )

    # Create trainer
    trainer = Trainer(
        model=model,
        args=training_args,
        train_dataset=train_dataset_tokenized,
        eval_dataset=val_dataset_tokenized,
        data_collator=data_collator,
        tokenizer=tokenizer,
    )

    # Train
    print("\n" + "=" * 70)
    print("Starting Training")
    print("=" * 70)
    print()

    train_result = trainer.train()

    # Save
    print("\n" + "=" * 70)
    print("Training Complete!")
    print("=" * 70)
    print()
    print(f"Final training loss: {train_result.training_loss:.4f}")

    final_model_path = output_dir / "final"
    trainer.save_model(str(final_model_path))
    tokenizer.save_pretrained(str(final_model_path))

    print(f"\n✓ Model saved to: {final_model_path}")

    # Save metrics
    metrics_file = output_dir / "training_metrics.json"
    with open(metrics_file, 'w') as f:
        json.dump({
            "training_loss": float(train_result.training_loss),
            "training_runtime": train_result.metrics["train_runtime"],
            "num_examples": len(train_dataset),
            "config": config.__dict__,
        }, f, indent=2)

    print(f"✓ Metrics saved to: {metrics_file}")


def main():
    """Main entry point."""
    config = TrainingConfig()

    if not Path(config.train_data_file).exists():
        print(f"ERROR: Training data not found: {config.train_data_file}")
        return 1

    try:
        train(config)
        return 0
    except KeyboardInterrupt:
        print("\n\nTraining interrupted by user")
        return 130
    except Exception as e:
        print(f"\n\nERROR: Training failed: {e}")
        import traceback
        traceback.print_exc()
        return 1


if __name__ == "__main__":
    exit(main())
