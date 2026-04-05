# ABOUTME: Unit tests for the spot vs on-demand GPU cost calculator.
# ABOUTME: Tests cost calculations, interruption overhead, monthly projections, and edge cases.

import sys
import os

import pytest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', '..', 'cost-analysis', 'calculators'))

from spot_vs_ondemand import (
    InstanceType,
    TrainingJob,
    calculate_costs,
    calculate_spot_interruption_overhead,
    monthly_cost_comparison,
)


class TestInstanceType:
    """Tests for the InstanceType enum."""

    def test_instance_has_expected_attributes(self):
        p3 = InstanceType.P3_2XLARGE
        assert p3.instance_name == "p3.2xlarge"
        assert p3.gpu_type == "V100 16GB"
        assert p3.gpu_count == 1
        assert p3.ondemand_price == 3.06
        assert p3.spot_price == 0.918

    def test_spot_price_less_than_ondemand(self):
        for it in InstanceType:
            assert it.spot_price < it.ondemand_price, (
                f"{it.instance_name}: spot ({it.spot_price}) >= ondemand ({it.ondemand_price})"
            )


class TestSpotInterruptionOverhead:
    """Tests for spot interruption overhead calculation."""

    def test_zero_duration_zero_overhead(self):
        overhead = calculate_spot_interruption_overhead(
            duration_hours=0, checkpoint_interval_minutes=30,
            avg_interruption_recovery_minutes=10
        )
        assert overhead == 0.0

    def test_longer_duration_more_overhead(self):
        short = calculate_spot_interruption_overhead(
            duration_hours=1, checkpoint_interval_minutes=30,
            avg_interruption_recovery_minutes=10
        )
        long = calculate_spot_interruption_overhead(
            duration_hours=10, checkpoint_interval_minutes=30,
            avg_interruption_recovery_minutes=10
        )
        assert long > short

    def test_shorter_checkpoint_less_overhead(self):
        frequent = calculate_spot_interruption_overhead(
            duration_hours=10, checkpoint_interval_minutes=10,
            avg_interruption_recovery_minutes=10
        )
        infrequent = calculate_spot_interruption_overhead(
            duration_hours=10, checkpoint_interval_minutes=60,
            avg_interruption_recovery_minutes=10
        )
        assert frequent < infrequent

    def test_zero_interruption_rate_zero_overhead(self):
        overhead = calculate_spot_interruption_overhead(
            duration_hours=100, checkpoint_interval_minutes=30,
            avg_interruption_recovery_minutes=10,
            interruption_rate_per_hour=0.0
        )
        assert overhead == 0.0


class TestCalculateCosts:
    """Tests for the main cost calculation function."""

    def test_spot_cheaper_than_ondemand(self):
        job = TrainingJob(
            name="test-job",
            duration_hours=10,
            instance_type=InstanceType.P3_2XLARGE,
        )
        result = calculate_costs(job)
        assert result['spot']['total_cost'] < result['on_demand']['total_cost']

    def test_savings_percent_positive(self):
        job = TrainingJob(
            name="test-job",
            duration_hours=10,
            instance_type=InstanceType.P4D_24XLARGE,
        )
        result = calculate_costs(job)
        assert result['savings']['percent'] > 0

    def test_result_contains_expected_keys(self):
        job = TrainingJob(
            name="test-job",
            duration_hours=5,
            instance_type=InstanceType.G5_XLARGE,
        )
        result = calculate_costs(job)
        assert 'job_name' in result
        assert 'instance_type' in result
        assert 'on_demand' in result
        assert 'spot' in result
        assert 'savings' in result

    def test_ondemand_cost_matches_manual_calculation(self):
        job = TrainingJob(
            name="test-job",
            duration_hours=10,
            instance_type=InstanceType.G4DN_XLARGE,
        )
        result = calculate_costs(job, interruption_rate=0.05)
        expected_ondemand = 10 * 0.526
        assert result['on_demand']['total_cost'] == round(expected_ondemand, 2)

    def test_high_interruption_rate_reduces_savings(self):
        job = TrainingJob(
            name="test-job",
            duration_hours=10,
            instance_type=InstanceType.P3_2XLARGE,
        )
        low_interrupt = calculate_costs(job, interruption_rate=0.01)
        high_interrupt = calculate_costs(job, interruption_rate=0.20)
        assert low_interrupt['savings']['percent'] > high_interrupt['savings']['percent']


class TestMonthlyCostComparison:
    """Tests for monthly cost projection."""

    def test_monthly_hours_calculation(self):
        result = monthly_cost_comparison(16, InstanceType.P3_2XLARGE)
        assert result['daily_hours'] == 16
        assert result['monthly_hours'] == 480  # 16 * 30

    def test_annual_savings_is_12x_monthly(self):
        result = monthly_cost_comparison(8, InstanceType.G5_XLARGE)
        assert result['annual_savings'] == round(result['monthly_savings'] * 12, 2)

    def test_spot_monthly_cheaper(self):
        result = monthly_cost_comparison(24, InstanceType.P4D_24XLARGE)
        assert result['spot_monthly'] < result['on_demand_monthly']
