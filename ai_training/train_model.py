#!/usr/bin/env python3
"""
Train EC4X AI Model using LoRA fine-tuning on Mistral-7B.

This script:
1. Loads the processed training dataset
2. Downloads Mistral-7B-Instruct-v0.2 base model
3. Applies LoRA (Low-Rank Adaptation) for efficient fine-tuning
4. Trains the model on EC4X gameplay data
5. Saves checkpoints and the final model
"""

import json
import torch
from pathlib import Path
from dataclasses import dataclass
from typing import List, Dict

from transformers import (
    AutoModelForCausalLM,
    AutoTokenizer,
    TrainingArguments,
    Trainer,
    DataCollatorForLanguageModeling,
)
from peft import LoraConfig, get_peft_model, TaskType, PeftModel
from datasets import Dataset
import numpy as np


@dataclass
class TrainingConfig:
    """Training configuration."""
    # Model
    base_model: str = "mistralai/Mistral-7B-Instruct-v0.2"
    output_dir: str = "models/ec4x-mistral-7b"

    # LoRA configuration
    lora_r: int = 16  # Rank
    lora_alpha: int = 32  # Alpha
    lora_dropout: float = 0.05
    lora_target_modules: List[str] = None  # Set in __post_init__

    # Training hyperparameters
    num_train_epochs: int = 3
    per_device_train_batch_size: int = 2  # Adjust based on VRAM
    gradient_accumulation_steps: int = 8  # Effective batch size = 2 * 8 = 16
    learning_rate: float = 2e-4
    max_grad_norm: float = 0.3
    warmup_ratio: float = 0.03
    lr_scheduler_type: str = "cosine"

    # Optimization
    optim: str = "adamw_torch"
    weight_decay: float = 0.001
    max_seq_length: int = 2048

    # Checkpointing
    save_steps: int = 100
    save_total_limit: int = 3
    logging_steps: int = 10

    # Quantization
    load_in_8bit: bool = True  # Reduce VRAM usage
    load_in_4bit: bool = False  # Even more aggressive (may reduce quality)

    # Data
    train_data_file: str = "training_data/training_dataset_processed.json"
    validation_split: float = 0.05  # 5% for validation

    def __post_init__(self):
        if self.lora_target_modules is None:
            # Target all linear layers in attention for Mistral
            self.lora_target_modules = ["q_proj", "k_proj", "v_proj", "o_proj"]


def load_training_data(config: TrainingConfig) -> tuple[Dataset, Dataset]:
    """Load and prepare training dataset."""
    print("Loading training data...")

    data_path = Path(config.train_data_file)
    if not data_path.exists():
        raise FileNotFoundError(
            f"Training data not found: {data_path}\n"
            f"Run prepare_training_data.py first."
        )

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

    # Convert to Hugging Face Dataset
    train_dataset = Dataset.from_list(train_examples)
    val_dataset = Dataset.from_list(val_examples)

    return train_dataset, val_dataset


def tokenize_dataset(dataset: Dataset, tokenizer, max_length: int) -> Dataset:
    """Tokenize dataset for training."""
    def tokenize_function(examples):
        # Tokenize the combined text (prompt + completion)
        tokenized = tokenizer(
            examples["text"],
            truncation=True,
            max_length=max_length,
            padding=False,  # Will be handled by data collator
        )

        # Labels are the same as input_ids for causal LM
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
    """Load base model and apply LoRA."""
    print(f"\nLoading base model: {config.base_model}")

    # Load tokenizer
    tokenizer = AutoTokenizer.from_pretrained(config.base_model)

    # Add pad token if missing (Mistral doesn't have one by default)
    if tokenizer.pad_token is None:
        tokenizer.pad_token = tokenizer.eos_token
        tokenizer.pad_token_id = tokenizer.eos_token_id

    print(f"  Tokenizer vocabulary size: {len(tokenizer)}")

    # Configure quantization
    quantization_config = None
    if config.load_in_8bit:
        from transformers import BitsAndBytesConfig
        quantization_config = BitsAndBytesConfig(
            load_in_8bit=True,
            llm_int8_threshold=6.0,
        )
        print("  Using 8-bit quantization")
    elif config.load_in_4bit:
        from transformers import BitsAndBytesConfig
        quantization_config = BitsAndBytesConfig(
            load_in_4bit=True,
            bnb_4bit_compute_dtype=torch.float16,
            bnb_4bit_quant_type="nf4",
            bnb_4bit_use_double_quant=True,
        )
        print("  Using 4-bit quantization")

    # Load model
    model = AutoModelForCausalLM.from_pretrained(
        config.base_model,
        quantization_config=quantization_config,
        device_map="auto",  # Automatically distribute across available GPUs
        torch_dtype=torch.float16,
        trust_remote_code=True,
    )

    print(f"  Model loaded on: {model.device}")
    print(f"  Model dtype: {model.dtype}")

    # Configure LoRA
    print("\nApplying LoRA...")
    lora_config = LoraConfig(
        task_type=TaskType.CAUSAL_LM,
        r=config.lora_r,
        lora_alpha=config.lora_alpha,
        lora_dropout=config.lora_dropout,
        target_modules=config.lora_target_modules,
        bias="none",
    )

    model = get_peft_model(model, lora_config)
    model.print_trainable_parameters()

    return model, tokenizer


def train(config: TrainingConfig):
    """Main training loop."""
    print("=" * 70)
    print("EC4X Model Training")
    print("=" * 70)
    print()

    # Check GPU availability
    print("GPU Information:")
    if torch.cuda.is_available():
        print(f"  Device count: {torch.cuda.device_count()}")
        print(f"  Current device: {torch.cuda.current_device()}")
        print(f"  Device name: {torch.cuda.get_device_name(0)}")
        memory_gb = torch.cuda.get_device_properties(0).total_memory / 1e9
        print(f"  Total memory: {memory_gb:.1f} GB")
    else:
        print("  WARNING: No GPU detected. Training will be very slow on CPU.")
    print()

    # Load data
    train_dataset, val_dataset = load_training_data(config)

    # Setup model and tokenizer
    model, tokenizer = setup_model_and_tokenizer(config)

    # Tokenize datasets
    train_dataset_tokenized = tokenize_dataset(train_dataset, tokenizer, config.max_seq_length)
    val_dataset_tokenized = tokenize_dataset(val_dataset, tokenizer, config.max_seq_length)

    # Data collator (handles padding)
    data_collator = DataCollatorForLanguageModeling(
        tokenizer=tokenizer,
        mlm=False,  # We're doing causal LM, not masked LM
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
        fp16=True,  # Use mixed precision for speed
        save_steps=config.save_steps,
        save_total_limit=config.save_total_limit,
        logging_steps=config.logging_steps,
        evaluation_strategy="steps",
        eval_steps=config.save_steps,
        load_best_model_at_end=True,
        metric_for_best_model="eval_loss",
        greater_is_better=False,
        report_to=[],  # Disable wandb/tensorboard for now
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

    # Save final model
    print("\n" + "=" * 70)
    print("Training Complete!")
    print("=" * 70)
    print()
    print(f"Final training loss: {train_result.training_loss:.4f}")

    # Save the final model
    final_model_path = output_dir / "final"
    trainer.save_model(str(final_model_path))
    tokenizer.save_pretrained(str(final_model_path))

    print(f"\n✓ Model saved to: {final_model_path}")
    print(f"✓ Checkpoints saved to: {output_dir}")

    # Save training metrics
    metrics_file = output_dir / "training_metrics.json"
    with open(metrics_file, 'w') as f:
        json.dump({
            "training_loss": float(train_result.training_loss),
            "training_runtime": train_result.metrics["train_runtime"],
            "training_samples_per_second": train_result.metrics["train_samples_per_second"],
            "num_examples": len(train_dataset),
            "config": config.__dict__,
        }, f, indent=2)

    print(f"✓ Metrics saved to: {metrics_file}")
    print()
    print("Next steps:")
    print("1. Export to GGUF format for inference: python export_to_gguf.py")
    print("2. Test the model: python test_model.py")
    print()


def main():
    """Main entry point."""
    # Load configuration
    config = TrainingConfig()

    # Verify training data exists
    if not Path(config.train_data_file).exists():
        print(f"ERROR: Training data not found: {config.train_data_file}")
        print("\nRun these steps first:")
        print("1. python generate_parallel.py  # Generate raw training data")
        print("2. python prepare_training_data.py  # Process into training format")
        return 1

    # Start training
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
