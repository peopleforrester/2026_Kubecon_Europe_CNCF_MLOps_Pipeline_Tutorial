#!/usr/bin/env python3
# ABOUTME: GPU cost calculator comparing spot vs on-demand instances for training workloads
# ABOUTME: Helps teams estimate cost savings from spot instances with checkpoint strategies

import argparse
import json
from dataclasses import dataclass
from typing import Dict, List
from enum import Enum


class InstanceType(Enum):
    """Common GPU instance types with pricing"""
    P3_2XLARGE = ("p3.2xlarge", "V100 16GB", 1, 3.06, 0.918)
    P3_8XLARGE = ("p3.8xlarge", "V100 16GB x4", 4, 12.24, 3.672)
    P3_16XLARGE = ("p3.16xlarge", "V100 16GB x8", 8, 24.48, 7.344)
    P4D_24XLARGE = ("p4d.24xlarge", "A100 40GB x8", 8, 32.77, 9.831)
    G4DN_XLARGE = ("g4dn.xlarge", "T4 16GB", 1, 0.526, 0.158)
    G4DN_12XLARGE = ("g4dn.12xlarge", "T4 16GB x4", 4, 3.912, 1.174)
    G5_XLARGE = ("g5.xlarge", "A10G 24GB", 1, 1.006, 0.302)

    def __init__(self, name: str, gpu: str, gpu_count: int, ondemand: float, spot: float):
        self.instance_name = name
        self.gpu_type = gpu
        self.gpu_count = gpu_count
        self.ondemand_price = ondemand
        self.spot_price = spot


@dataclass
class TrainingJob:
    """Represents a GPU training job with cost estimates"""
    name: str
    duration_hours: float
    instance_type: InstanceType
    checkpoint_interval_minutes: int = 30
    avg_interruption_recovery_minutes: int = 10


def calculate_spot_interruption_overhead(
    duration_hours: float,
    checkpoint_interval_minutes: int,
    avg_interruption_recovery_minutes: int,
    interruption_rate_per_hour: float = 0.05
) -> float:
    """
    Calculate time overhead from spot interruptions.

    Args:
        duration_hours: Total training duration
        checkpoint_interval_minutes: How often checkpoints are saved
        avg_interruption_recovery_minutes: Average time to recover from interruption
        interruption_rate_per_hour: Probability of interruption per hour (default 5%)

    Returns:
        Total overhead hours from interruptions
    """
    expected_interruptions = duration_hours * interruption_rate_per_hour

    # Recovery time includes:
    # 1. Time to spin up new instance (~5 min)
    # 2. Time to load checkpoint (~3 min)
    # 3. Re-compute lost work since last checkpoint (avg half the checkpoint interval)
    avg_lost_work_minutes = checkpoint_interval_minutes / 2
    total_recovery_minutes = avg_interruption_recovery_minutes + avg_lost_work_minutes

    overhead_hours = expected_interruptions * (total_recovery_minutes / 60)
    return overhead_hours


def calculate_costs(job: TrainingJob, interruption_rate: float = 0.05) -> Dict:
    """
    Calculate costs for on-demand vs spot instances.

    Args:
        job: TrainingJob configuration
        interruption_rate: Spot interruption rate per hour (default 5%)

    Returns:
        Dictionary with cost breakdown
    """
    # On-demand costs (no interruptions)
    ondemand_cost = job.duration_hours * job.instance_type.ondemand_price

    # Spot costs (with interruption overhead)
    spot_overhead = calculate_spot_interruption_overhead(
        job.duration_hours,
        job.checkpoint_interval_minutes,
        10,  # avg recovery time
        interruption_rate
    )
    spot_total_hours = job.duration_hours + spot_overhead
    spot_cost = spot_total_hours * job.instance_type.spot_price

    # Savings
    savings = ondemand_cost - spot_cost
    savings_percent = (savings / ondemand_cost) * 100

    return {
        "job_name": job.name,
        "instance_type": job.instance_type.instance_name,
        "gpu_type": job.instance_type.gpu_type,
        "gpu_count": job.instance_type.gpu_count,
        "training_hours": job.duration_hours,
        "on_demand": {
            "hourly_rate": job.instance_type.ondemand_price,
            "total_hours": job.duration_hours,
            "total_cost": round(ondemand_cost, 2)
        },
        "spot": {
            "hourly_rate": job.instance_type.spot_price,
            "interruption_overhead_hours": round(spot_overhead, 2),
            "total_hours": round(spot_total_hours, 2),
            "total_cost": round(spot_cost, 2)
        },
        "savings": {
            "dollars": round(savings, 2),
            "percent": round(savings_percent, 1)
        },
        "checkpoint_interval_minutes": job.checkpoint_interval_minutes,
        "estimated_interruptions": round(job.duration_hours * interruption_rate, 2)
    }


def monthly_cost_comparison(daily_gpu_hours: float, instance_type: InstanceType) -> Dict:
    """
    Calculate monthly costs for continuous GPU usage.

    Args:
        daily_gpu_hours: GPU hours per day (e.g., 16 hours/day)
        instance_type: Instance type to use

    Returns:
        Monthly cost breakdown
    """
    monthly_hours = daily_gpu_hours * 30

    ondemand_monthly = monthly_hours * instance_type.ondemand_price
    spot_monthly = monthly_hours * instance_type.spot_price
    savings = ondemand_monthly - spot_monthly

    return {
        "instance_type": instance_type.instance_name,
        "daily_hours": daily_gpu_hours,
        "monthly_hours": monthly_hours,
        "on_demand_monthly": round(ondemand_monthly, 2),
        "spot_monthly": round(spot_monthly, 2),
        "monthly_savings": round(savings, 2),
        "annual_savings": round(savings * 12, 2)
    }


def print_cost_table(results: List[Dict]):
    """Print cost comparison table"""
    print("\n" + "=" * 100)
    print("GPU TRAINING COST COMPARISON: Spot vs On-Demand")
    print("=" * 100)

    for result in results:
        print(f"\nJob: {result['job_name']}")
        print(f"Instance: {result['instance_type']} ({result['gpu_type']} x{result['gpu_count']})")
        print(f"Training Duration: {result['training_hours']} hours")
        print(f"Checkpoint Interval: {result['checkpoint_interval_minutes']} minutes")
        print(f"\nON-DEMAND:")
        print(f"  Rate: ${result['on_demand']['hourly_rate']:.3f}/hour")
        print(f"  Hours: {result['on_demand']['total_hours']:.2f}")
        print(f"  Total: ${result['on_demand']['total_cost']:,.2f}")
        print(f"\nSPOT (with interruptions):")
        print(f"  Rate: ${result['spot']['hourly_rate']:.3f}/hour")
        print(f"  Training Hours: {result['training_hours']:.2f}")
        print(f"  Interruption Overhead: +{result['spot']['interruption_overhead_hours']:.2f} hours")
        print(f"  Total Hours: {result['spot']['total_hours']:.2f}")
        print(f"  Total Cost: ${result['spot']['total_cost']:,.2f}")
        print(f"\nSAVINGS:")
        print(f"  ${result['savings']['dollars']:,.2f} ({result['savings']['percent']:.1f}%)")
        print(f"  Expected Interruptions: {result['estimated_interruptions']:.2f}")
        print("-" * 100)


def main():
    parser = argparse.ArgumentParser(
        description="Calculate GPU training costs: spot vs on-demand instances"
    )
    parser.add_argument(
        "--duration",
        type=float,
        required=True,
        help="Training duration in hours"
    )
    parser.add_argument(
        "--instance",
        type=str,
        choices=[it.instance_name for it in InstanceType],
        required=True,
        help="Instance type"
    )
    parser.add_argument(
        "--checkpoint-interval",
        type=int,
        default=30,
        help="Checkpoint interval in minutes (default: 30)"
    )
    parser.add_argument(
        "--interruption-rate",
        type=float,
        default=0.05,
        help="Spot interruption rate per hour (default: 0.05 = 5%%)"
    )
    parser.add_argument(
        "--json",
        action="store_true",
        help="Output JSON instead of table"
    )

    args = parser.parse_args()

    # Find instance type
    instance = next(it for it in InstanceType if it.instance_name == args.instance)

    # Create training job
    job = TrainingJob(
        name=f"Training on {args.instance}",
        duration_hours=args.duration,
        instance_type=instance,
        checkpoint_interval_minutes=args.checkpoint_interval
    )

    # Calculate costs
    result = calculate_costs(job, args.interruption_rate)

    if args.json:
        print(json.dumps(result, indent=2))
    else:
        print_cost_table([result])

        # Recommendations
        print("\nRECOMMENDATIONS:")
        if result['savings']['percent'] > 60:
            print(f"✓ Spot instances highly recommended ({result['savings']['percent']:.1f}% savings)")
        elif result['savings']['percent'] > 40:
            print(f"✓ Spot instances recommended ({result['savings']['percent']:.1f}% savings)")
        else:
            print(f"⚠ Low savings ({result['savings']['percent']:.1f}%). Consider on-demand or longer checkpoints.")

        if args.checkpoint_interval > 60:
            print(f"⚠ Checkpoint interval ({args.checkpoint_interval} min) is long. Consider 30-60 min for spot.")

        print(f"\nTo reduce interruption overhead:")
        print(f"  - Decrease checkpoint interval to 15-30 minutes")
        print(f"  - Use faster storage for checkpoints (gp3 with 3000+ IOPS)")
        print(f"  - Implement preemptive checkpointing on spot termination signal")


if __name__ == "__main__":
    main()
