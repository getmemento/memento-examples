#!/usr/bin/env python3
"""
Distributed Data Parallel Training Script

Works with both Kubeflow PyTorchJob and native Kubernetes Jobs.
Environment variables (RANK, WORLD_SIZE, etc.) are set by the orchestrator.
"""

import argparse
import os
import signal
import sys
from pathlib import Path

import torch
import torch.distributed as dist
import torch.nn as nn
import torch.optim as optim
from torch.nn.parallel import DistributedDataParallel as DDP
from torch.utils.data import DataLoader, DistributedSampler
from torch.utils.data.dataset import Dataset


class DummyDataset(Dataset):
    """Replace with your actual dataset."""

    def __init__(self, size: int = 10000, input_dim: int = 512):
        self.size = size
        self.input_dim = input_dim

    def __len__(self):
        return self.size

    def __getitem__(self, idx):
        x = torch.randn(self.input_dim)
        y = torch.randint(0, 10, (1,)).item()
        return x, y


class SimpleModel(nn.Module):
    """Replace with your actual model."""

    def __init__(self, input_dim: int = 512, hidden_dim: int = 1024, num_classes: int = 10):
        super().__init__()
        self.layers = nn.Sequential(
            nn.Linear(input_dim, hidden_dim),
            nn.ReLU(),
            nn.Linear(hidden_dim, hidden_dim),
            nn.ReLU(),
            nn.Linear(hidden_dim, num_classes),
        )

    def forward(self, x):
        return self.layers(x)


class CheckpointManager:
    """Handles checkpoint saving and loading with spot interruption support."""

    def __init__(self, checkpoint_dir: str, rank: int):
        self.checkpoint_dir = Path(checkpoint_dir)
        self.checkpoint_dir.mkdir(parents=True, exist_ok=True)
        self.rank = rank
        self.interrupted = False

        # Handle SIGTERM for spot interruption
        signal.signal(signal.SIGTERM, self._handle_sigterm)

    def _handle_sigterm(self, signum, frame):
        print(f"[Rank {self.rank}] Received SIGTERM, will save checkpoint...")
        self.interrupted = True

    def save(self, model, optimizer, epoch: int, step: int, loss: float):
        if self.rank != 0:
            return

        checkpoint = {
            "epoch": epoch,
            "step": step,
            "model_state_dict": model.module.state_dict(),
            "optimizer_state_dict": optimizer.state_dict(),
            "loss": loss,
        }

        path = self.checkpoint_dir / f"checkpoint_epoch{epoch}_step{step}.pt"
        torch.save(checkpoint, path)
        print(f"[Rank {self.rank}] Saved checkpoint to {path}")

        # Keep symlink to latest
        latest = self.checkpoint_dir / "latest.pt"
        if latest.exists():
            latest.unlink()
        latest.symlink_to(path.name)

    def load_latest(self, model, optimizer):
        latest = self.checkpoint_dir / "latest.pt"
        if not latest.exists():
            return 0, 0

        checkpoint = torch.load(latest, map_location="cpu")
        model.module.load_state_dict(checkpoint["model_state_dict"])
        optimizer.load_state_dict(checkpoint["optimizer_state_dict"])

        print(f"[Rank {self.rank}] Loaded checkpoint from epoch {checkpoint['epoch']}")
        return checkpoint["epoch"], checkpoint["step"]


def setup_distributed():
    """Initialise distributed training."""
    dist.init_process_group(backend="nccl", init_method="env://")

    rank = dist.get_rank()
    world_size = dist.get_world_size()
    local_rank = int(os.environ.get("LOCAL_RANK", 0))

    torch.cuda.set_device(local_rank)

    print(f"[Rank {rank}/{world_size}] Initialised on GPU {local_rank}")
    return rank, world_size, local_rank


def cleanup_distributed():
    """Clean up distributed training."""
    dist.destroy_process_group()


def train(args):
    rank, world_size, local_rank = setup_distributed()

    # Create model and move to GPU
    model = SimpleModel().to(local_rank)
    model = DDP(model, device_ids=[local_rank])

    # Optimiser
    optimizer = optim.AdamW(model.parameters(), lr=args.lr)

    # Loss function
    criterion = nn.CrossEntropyLoss()

    # Dataset with distributed sampler
    dataset = DummyDataset()
    sampler = DistributedSampler(dataset, num_replicas=world_size, rank=rank, shuffle=True)
    dataloader = DataLoader(
        dataset,
        batch_size=args.batch_size,
        sampler=sampler,
        num_workers=4,
        pin_memory=True,
    )

    # Checkpoint manager
    ckpt_manager = CheckpointManager(args.checkpoint_dir, rank)

    # Resume from checkpoint if exists
    start_epoch, start_step = ckpt_manager.load_latest(model, optimizer)

    # Training loop
    global_step = start_step
    for epoch in range(start_epoch, args.epochs):
        sampler.set_epoch(epoch)  # Important for proper shuffling
        model.train()

        for batch_idx, (data, target) in enumerate(dataloader):
            # Check for interruption
            if ckpt_manager.interrupted:
                print(f"[Rank {rank}] Saving checkpoint due to interruption...")
                ckpt_manager.save(model, optimizer, epoch, global_step, loss.item())
                cleanup_distributed()
                sys.exit(0)

            data, target = data.to(local_rank), target.to(local_rank)

            optimizer.zero_grad()
            output = model(data)
            loss = criterion(output, target)
            loss.backward()
            optimizer.step()

            global_step += 1

            if batch_idx % args.log_interval == 0 and rank == 0:
                print(
                    f"Epoch {epoch} [{batch_idx * len(data)}/{len(dataset)}] "
                    f"Loss: {loss.item():.6f}"
                )

            # Periodic checkpoint
            if global_step % args.checkpoint_interval == 0:
                ckpt_manager.save(model, optimizer, epoch, global_step, loss.item())

        # End of epoch checkpoint
        ckpt_manager.save(model, optimizer, epoch + 1, global_step, loss.item())

        if rank == 0:
            print(f"Epoch {epoch} completed")

    cleanup_distributed()
    print(f"[Rank {rank}] Training complete")


def main():
    parser = argparse.ArgumentParser(description="Distributed Training")
    parser.add_argument("--epochs", type=int, default=10)
    parser.add_argument("--batch-size", type=int, default=32)
    parser.add_argument("--lr", type=float, default=1e-4)
    parser.add_argument("--checkpoint-dir", type=str, default="/checkpoints")
    parser.add_argument("--checkpoint-interval", type=int, default=1000)
    parser.add_argument("--log-interval", type=int, default=100)
    args = parser.parse_args()

    train(args)


if __name__ == "__main__":
    main()
