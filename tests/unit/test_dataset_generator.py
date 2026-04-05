# ABOUTME: Unit tests for the synthetic dataset generator.
# ABOUTME: Tests all dataset types: classification, regression, time-series, Kafka, and drift.

import json
import os
import sys

import numpy as np
import pandas as pd
import pytest

# Add examples directory to path for import
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', '..', 'examples'))

from sample_dataset_generator import DatasetGenerator


@pytest.fixture
def generator():
    """Create a DatasetGenerator with fixed seed for reproducibility."""
    return DatasetGenerator(seed=42)


class TestClassificationDataset:
    """Tests for classification dataset generation."""

    def test_generates_correct_number_of_samples(self, generator, tmp_path):
        output = tmp_path / "classification.parquet"
        df = generator.generate_classification_dataset(
            n_samples=100, n_features=5, output_file=str(output)
        )
        assert len(df) == 100

    def test_generates_correct_number_of_features(self, generator, tmp_path):
        output = tmp_path / "classification.parquet"
        df = generator.generate_classification_dataset(
            n_samples=50, n_features=10, output_file=str(output)
        )
        feature_cols = [c for c in df.columns if c.startswith('feature_')]
        assert len(feature_cols) == 10

    def test_binary_classification_has_two_classes(self, generator, tmp_path):
        output = tmp_path / "classification.parquet"
        df = generator.generate_classification_dataset(
            n_samples=200, n_classes=2, output_file=str(output)
        )
        assert df['target'].nunique() == 2

    def test_multiclass_classification(self, generator, tmp_path):
        output = tmp_path / "classification.parquet"
        df = generator.generate_classification_dataset(
            n_samples=500, n_classes=5, output_file=str(output)
        )
        assert df['target'].nunique() == 5

    def test_saves_parquet_file(self, generator, tmp_path):
        output = tmp_path / "classification.parquet"
        generator.generate_classification_dataset(
            n_samples=50, output_file=str(output)
        )
        assert output.exists()
        df_loaded = pd.read_parquet(output)
        assert len(df_loaded) == 50

    def test_has_required_columns(self, generator, tmp_path):
        output = tmp_path / "classification.parquet"
        df = generator.generate_classification_dataset(
            n_samples=50, n_features=3, output_file=str(output)
        )
        assert 'target' in df.columns
        assert 'id' in df.columns
        assert 'timestamp' in df.columns


class TestRegressionDataset:
    """Tests for regression dataset generation."""

    def test_generates_correct_shape(self, generator, tmp_path):
        output = tmp_path / "regression.parquet"
        df = generator.generate_regression_dataset(
            n_samples=100, n_features=8, output_file=str(output)
        )
        assert len(df) == 100
        feature_cols = [c for c in df.columns if c.startswith('feature_')]
        assert len(feature_cols) == 8

    def test_target_is_continuous(self, generator, tmp_path):
        output = tmp_path / "regression.parquet"
        df = generator.generate_regression_dataset(
            n_samples=100, output_file=str(output)
        )
        assert df['target'].dtype in [np.float64, np.float32]
        assert df['target'].nunique() > 10


class TestTimeseriesDataset:
    """Tests for time-series dataset generation."""

    def test_generates_timestamps(self, generator, tmp_path):
        output = tmp_path / "timeseries.parquet"
        df = generator.generate_timeseries_dataset(
            n_samples=100, n_features=3, output_file=str(output)
        )
        assert 'timestamp' in df.columns

    def test_creates_lagged_features(self, generator, tmp_path):
        output = tmp_path / "timeseries.parquet"
        df = generator.generate_timeseries_dataset(
            n_samples=100, output_file=str(output)
        )
        lag_cols = [c for c in df.columns if 'lag' in c]
        assert len(lag_cols) == 3  # lag 1, 7, 24

    def test_creates_rolling_features(self, generator, tmp_path):
        output = tmp_path / "timeseries.parquet"
        df = generator.generate_timeseries_dataset(
            n_samples=100, output_file=str(output)
        )
        rolling_cols = [c for c in df.columns if 'rolling' in c]
        assert len(rolling_cols) == 2  # mean and std


class TestKafkaMessages:
    """Tests for Kafka JSON message generation."""

    def test_generates_correct_count(self, generator, tmp_path):
        output = tmp_path / "messages.json"
        messages = generator.generate_kafka_json_messages(
            n_messages=50, output_file=str(output)
        )
        assert len(messages) == 50

    def test_message_structure(self, generator, tmp_path):
        output = tmp_path / "messages.json"
        messages = generator.generate_kafka_json_messages(
            n_messages=5, n_features=3, output_file=str(output)
        )
        msg = messages[0]
        assert 'id' in msg
        assert 'timestamp' in msg
        assert 'features' in msg
        assert 'metadata' in msg
        assert len(msg['features']) == 3

    def test_writes_jsonl_format(self, generator, tmp_path):
        output = tmp_path / "messages.json"
        generator.generate_kafka_json_messages(
            n_messages=10, output_file=str(output)
        )
        with open(output) as f:
            lines = f.readlines()
        assert len(lines) == 10
        for line in lines:
            parsed = json.loads(line)
            assert 'id' in parsed


class TestDriftDatasets:
    """Tests for drift detection dataset generation."""

    def test_generates_reference_and_drifted(self, generator, tmp_path):
        output_dir = tmp_path / "drift"
        df_ref, df_drift = generator.generate_drift_datasets(
            n_samples=100, output_dir=str(output_dir)
        )
        assert len(df_ref) == 100
        assert len(df_drift) == 100

    def test_saves_both_files(self, generator, tmp_path):
        output_dir = tmp_path / "drift"
        generator.generate_drift_datasets(
            n_samples=50, output_dir=str(output_dir)
        )
        assert (output_dir / "reference.parquet").exists()
        assert (output_dir / "drifted.parquet").exists()

    def test_drift_shifts_feature_means(self, generator, tmp_path):
        output_dir = tmp_path / "drift"
        df_ref, df_drift = generator.generate_drift_datasets(
            n_samples=5000, n_features=10, drift_magnitude=1.0,
            output_dir=str(output_dir)
        )
        # First half of features should be shifted
        for i in range(5):
            ref_mean = df_ref[f'feature_{i}'].mean()
            drift_mean = df_drift[f'feature_{i}'].mean()
            assert abs(drift_mean - ref_mean) > 0.5, (
                f"feature_{i}: drift mean {drift_mean:.2f} not shifted enough from ref {ref_mean:.2f}"
            )


class TestReproducibility:
    """Tests for deterministic output with fixed seed."""

    def test_same_seed_same_output(self, tmp_path):
        # Generate first dataset immediately after seeding
        gen1 = DatasetGenerator(seed=999)
        out1 = tmp_path / "out1.parquet"
        df1 = gen1.generate_classification_dataset(
            n_samples=50, output_file=str(out1)
        )

        # Re-seed and generate again - should match
        gen2 = DatasetGenerator(seed=999)
        out2 = tmp_path / "out2.parquet"
        df2 = gen2.generate_classification_dataset(
            n_samples=50, output_file=str(out2)
        )
        pd.testing.assert_frame_equal(df1, df2)
