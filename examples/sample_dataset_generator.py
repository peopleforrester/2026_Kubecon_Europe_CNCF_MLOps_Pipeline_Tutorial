# ABOUTME: Synthetic dataset generator for ML pipeline demos and testing
# ABOUTME: Generates realistic tabular, time-series, and image classification datasets with configurable parameters

import argparse
import json
import pandas as pd
import numpy as np
from datetime import datetime, timedelta, timezone
import os


class DatasetGenerator:
    """Generate synthetic datasets for ML pipeline testing."""

    def __init__(self, seed=42):
        """Initialize generator with random seed."""
        np.random.seed(seed)
        self.seed = seed

    def generate_classification_dataset(
        self,
        n_samples=10000,
        n_features=20,
        n_classes=2,
        output_file='classification_data.parquet'
    ):
        """
        Generate synthetic classification dataset.

        Args:
            n_samples: Number of samples
            n_features: Number of features
            n_classes: Number of target classes
            output_file: Output file path

        Returns:
            DataFrame with features and target
        """
        print(f"Generating classification dataset: {n_samples} samples, {n_features} features, {n_classes} classes")

        # Generate features
        X = np.random.randn(n_samples, n_features)

        # Generate correlated target
        weights = np.random.randn(n_features)
        y_continuous = X @ weights + np.random.randn(n_samples) * 0.5

        # Convert to classes
        if n_classes == 2:
            y = (y_continuous > np.median(y_continuous)).astype(int)
        else:
            y = pd.cut(y_continuous, bins=n_classes, labels=False)

        # Create DataFrame
        df = pd.DataFrame(X, columns=[f'feature_{i}' for i in range(n_features)])
        df['target'] = y
        df['id'] = range(n_samples)
        df['timestamp'] = pd.date_range(start='2024-01-01', periods=n_samples, freq='1min')

        # Save to parquet
        df.to_parquet(output_file, index=False)
        print(f"✓ Saved to {output_file} ({len(df)} records)")

        return df

    def generate_regression_dataset(
        self,
        n_samples=10000,
        n_features=20,
        noise=0.1,
        output_file='regression_data.parquet'
    ):
        """
        Generate synthetic regression dataset.

        Args:
            n_samples: Number of samples
            n_features: Number of features
            noise: Noise level (0-1)
            output_file: Output file path

        Returns:
            DataFrame with features and target
        """
        print(f"Generating regression dataset: {n_samples} samples, {n_features} features")

        # Generate features
        X = np.random.randn(n_samples, n_features)

        # Generate target with non-linear relationships
        weights = np.random.randn(n_features)
        y = (X @ weights +
             0.5 * (X[:, 0] ** 2) +  # Quadratic term
             0.3 * (X[:, 1] * X[:, 2]) +  # Interaction term
             np.random.randn(n_samples) * noise)

        # Create DataFrame
        df = pd.DataFrame(X, columns=[f'feature_{i}' for i in range(n_features)])
        df['target'] = y
        df['id'] = range(n_samples)
        df['timestamp'] = pd.date_range(start='2024-01-01', periods=n_samples, freq='1min')

        # Save to parquet
        df.to_parquet(output_file, index=False)
        print(f"✓ Saved to {output_file} ({len(df)} records)")

        return df

    def generate_timeseries_dataset(
        self,
        n_samples=10000,
        n_features=5,
        seasonality=24,
        trend=0.01,
        output_file='timeseries_data.parquet'
    ):
        """
        Generate synthetic time-series dataset with trend and seasonality.

        Args:
            n_samples: Number of time steps
            n_features: Number of features
            seasonality: Seasonal period (e.g., 24 for hourly data with daily seasonality)
            trend: Linear trend coefficient
            output_file: Output file path

        Returns:
            DataFrame with time-series features
        """
        print(f"Generating time-series dataset: {n_samples} samples, {n_features} features")

        timestamps = pd.date_range(start='2024-01-01', periods=n_samples, freq='1h')

        data = {
            'timestamp': timestamps,
            'id': range(n_samples)
        }

        for i in range(n_features):
            # Base signal with trend
            signal = trend * np.arange(n_samples)

            # Add seasonality
            seasonal = 5 * np.sin(2 * np.pi * np.arange(n_samples) / seasonality)

            # Add random walk
            noise = np.cumsum(np.random.randn(n_samples) * 0.5)

            # Combine
            data[f'feature_{i}'] = signal + seasonal + noise

        df = pd.DataFrame(data)

        # Add lagged features
        for lag in [1, 7, 24]:
            df[f'feature_0_lag_{lag}'] = df['feature_0'].shift(lag)

        # Add rolling statistics
        df['feature_0_rolling_mean_7'] = df['feature_0'].rolling(window=7).mean()
        df['feature_0_rolling_std_7'] = df['feature_0'].rolling(window=7).std()

        # Drop NaN rows
        df = df.dropna()

        # Save to parquet
        df.to_parquet(output_file, index=False)
        print(f"✓ Saved to {output_file} ({len(df)} records)")

        return df

    def generate_kafka_json_messages(
        self,
        n_messages=1000,
        n_features=10,
        output_file='kafka_messages.json'
    ):
        """
        Generate Kafka-compatible JSON messages for data pipeline testing.

        Args:
            n_messages: Number of messages
            n_features: Number of features per message
            output_file: Output file path

        Returns:
            List of JSON messages
        """
        print(f"Generating Kafka JSON messages: {n_messages} messages")

        messages = []
        for i in range(n_messages):
            message = {
                'id': i,
                'timestamp': (datetime.now(timezone.utc) + timedelta(seconds=i)).isoformat(),
                'features': {
                    f'feature_{j}': float(np.random.randn())
                    for j in range(n_features)
                },
                'metadata': {
                    'source': 'sample-generator',
                    'version': '1.0'
                }
            }
            messages.append(message)

        # Save to JSON file (one message per line for Kafka compatibility)
        with open(output_file, 'w') as f:
            for msg in messages:
                f.write(json.dumps(msg) + '\n')

        print(f"✓ Saved to {output_file} ({len(messages)} messages)")

        return messages

    def generate_drift_datasets(
        self,
        n_samples=5000,
        n_features=20,
        drift_magnitude=0.5,
        output_dir='drift_data'
    ):
        """
        Generate reference and drifted datasets for drift detection testing.

        Args:
            n_samples: Number of samples per dataset
            n_features: Number of features
            drift_magnitude: Magnitude of distribution shift (0-1)
            output_dir: Output directory path

        Returns:
            Tuple of (reference_df, drifted_df)
        """
        print(f"Generating drift datasets: {n_samples} samples, drift={drift_magnitude}")

        os.makedirs(output_dir, exist_ok=True)

        # Reference dataset
        X_ref = np.random.randn(n_samples, n_features)
        df_ref = pd.DataFrame(X_ref, columns=[f'feature_{i}' for i in range(n_features)])
        df_ref['id'] = range(n_samples)
        df_ref['timestamp'] = pd.date_range(start='2024-01-01', periods=n_samples, freq='1min')

        # Drifted dataset (shift mean and scale)
        X_drift = np.random.randn(n_samples, n_features)
        # Apply drift to first half of features
        n_drifted_features = n_features // 2
        X_drift[:, :n_drifted_features] = (
            X_drift[:, :n_drifted_features] + drift_magnitude  # Mean shift
        ) * (1 + drift_magnitude)  # Scale shift

        df_drift = pd.DataFrame(X_drift, columns=[f'feature_{i}' for i in range(n_features)])
        df_drift['id'] = range(n_samples, n_samples * 2)
        df_drift['timestamp'] = pd.date_range(start='2024-02-01', periods=n_samples, freq='1min')

        # Save both datasets
        ref_file = os.path.join(output_dir, 'reference.parquet')
        drift_file = os.path.join(output_dir, 'drifted.parquet')

        df_ref.to_parquet(ref_file, index=False)
        df_drift.to_parquet(drift_file, index=False)

        print(f"✓ Saved reference to {ref_file}")
        print(f"✓ Saved drifted to {drift_file}")

        return df_ref, df_drift


def main():
    """Main function for command-line usage."""
    parser = argparse.ArgumentParser(description='Generate synthetic datasets for ML pipeline testing')

    parser.add_argument('--type', type=str, default='classification',
                        choices=['classification', 'regression', 'timeseries', 'kafka', 'drift'],
                        help='Type of dataset to generate')

    parser.add_argument('--n-samples', type=int, default=10000,
                        help='Number of samples')

    parser.add_argument('--n-features', type=int, default=20,
                        help='Number of features')

    parser.add_argument('--output', type=str, default=None,
                        help='Output file path')

    parser.add_argument('--seed', type=int, default=42,
                        help='Random seed')

    args = parser.parse_args()

    generator = DatasetGenerator(seed=args.seed)

    if args.type == 'classification':
        output = args.output or 'classification_data.parquet'
        generator.generate_classification_dataset(
            n_samples=args.n_samples,
            n_features=args.n_features,
            output_file=output
        )

    elif args.type == 'regression':
        output = args.output or 'regression_data.parquet'
        generator.generate_regression_dataset(
            n_samples=args.n_samples,
            n_features=args.n_features,
            output_file=output
        )

    elif args.type == 'timeseries':
        output = args.output or 'timeseries_data.parquet'
        generator.generate_timeseries_dataset(
            n_samples=args.n_samples,
            n_features=args.n_features,
            output_file=output
        )

    elif args.type == 'kafka':
        output = args.output or 'kafka_messages.json'
        generator.generate_kafka_json_messages(
            n_messages=args.n_samples,
            n_features=args.n_features,
            output_file=output
        )

    elif args.type == 'drift':
        output_dir = args.output or 'drift_data'
        generator.generate_drift_datasets(
            n_samples=args.n_samples,
            n_features=args.n_features,
            output_dir=output_dir
        )

    print("\n✓ Dataset generation complete!")
    print(f"\nUsage examples:")
    print(f"  python sample-dataset-generator.py --type classification --n-samples 10000")
    print(f"  python sample-dataset-generator.py --type kafka --n-samples 1000")
    print(f"  python sample-dataset-generator.py --type drift --n-samples 5000")


if __name__ == '__main__':
    main()
