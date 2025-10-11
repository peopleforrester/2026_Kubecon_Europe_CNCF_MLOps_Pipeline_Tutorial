# Data Validation for ML Pipelines

## Overview

Data quality is the #1 cause of ML model failures in production. This tutorial shows you how to build automated data validation into your ML pipelines using Argo Workflows.

**What You'll Learn:**
- Schema validation (types, required fields)
- Statistical validation (outliers, distributions)
- Data drift detection (distribution shifts)
- Quality alerts and dead letter queues

**Time:** 30 minutes
**Prerequisites:** Argo Workflows deployed, Kafka cluster running

---

## Why Data Validation Matters

**Real-World Failures:**
- 81% of ML projects fail due to data quality issues
- $15M lost at JPMorgan from missing data validation
- Google Flu Trends failed due to undetected data drift

**Common Data Issues:**
| Issue | Frequency | Impact |
|-------|-----------|--------|
| Schema changes | 45% | Model crashes |
| Missing values | 67% | Biased predictions |
| Outliers | 38% | Poor accuracy |
| Data drift | 29% | Degraded performance |

**Solution:** Automated validation catches issues before training.

---

## Validation Levels

```
┌────────────────────────────────────────────────────────────┐
│  Level 1: Schema Validation (CRITICAL)                      │
│  • Required fields present                                  │
│  • Correct data types                                       │
│  • No duplicate IDs                                         │
│  ➜ Fail workflow if schema invalid                         │
└────────────────────────────────────────────────────────────┘
                          │
                          ▼
┌────────────────────────────────────────────────────────────┐
│  Level 2: Statistical Validation (WARNING)                  │
│  • Value ranges (age: 0-120)                                │
│  • Null rate thresholds (< 10%)                             │
│  • Outlier detection (IQR method)                           │
│  ➜ Warn but continue workflow                              │
└────────────────────────────────────────────────────────────┘
                          │
                          ▼
┌────────────────────────────────────────────────────────────┐
│  Level 3: Drift Detection (ALERT)                           │
│  • Distribution shifts (KS test)                            │
│  • New categorical values                                   │
│  • Feature importance changes                               │
│  ➜ Alert and optionally retrain                            │
└────────────────────────────────────────────────────────────┘
```

---

## Step 1: Schema Validation

### Define Expected Schema

Create `schema.py`:

```python
# Expected schema for customer transactions
EXPECTED_SCHEMA = {
    'id': 'int64',
    'timestamp': 'datetime64[ns]',
    'customer_id': 'int64',
    'amount': 'float64',
    'merchant_category': 'object',
    'is_fraud': 'int64'
}

REQUIRED_FIELDS = ['id', 'timestamp', 'customer_id', 'amount']

VALUE_RANGES = {
    'amount': (0, 1000000),  # $0 to $1M
    'customer_id': (1000, 9999999),
    'is_fraud': (0, 1)
}
```

### Schema Validation Workflow

Create `schema-validation.yaml`:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: WorkflowTemplate
metadata:
  name: schema-validation
  namespace: argo
spec:
  templates:
    - name: validate-schema
      inputs:
        artifacts:
          - name: dataset
            path: /data/input.parquet
      outputs:
        artifacts:
          - name: validation-report
            path: /data/report.json
      container:
        image: python:3.11-slim
        command: [sh, -c]
        args:
          - |
            pip install -q pandas pyarrow
            python3 << 'EOF'
            import pandas as pd
            import json
            from datetime import datetime

            # Load dataset
            df = pd.read_parquet('/data/input.parquet')

            # Expected schema
            expected = {
                'id': 'int64',
                'timestamp': 'datetime64[ns]',
                'customer_id': 'int64',
                'amount': 'float64',
                'merchant_category': 'object',
                'is_fraud': 'int64'
            }

            errors = []

            # Check required fields
            for col, dtype in expected.items():
                if col not in df.columns:
                    errors.append(f"Missing required field: {col}")
                elif str(df[col].dtype) != dtype:
                    errors.append(
                        f"Type mismatch for {col}: "
                        f"expected {dtype}, got {df[col].dtype}"
                    )

            # Check for duplicates
            duplicates = df['id'].duplicated().sum()
            if duplicates > 0:
                errors.append(f"Found {duplicates} duplicate IDs")

            # Check null rates
            null_rates = df.isnull().sum() / len(df)
            high_null = null_rates[null_rates > 0.1]  # > 10%
            for col, rate in high_null.items():
                errors.append(f"High null rate for {col}: {rate:.1%}")

            # Generate report
            report = {
                'timestamp': datetime.utcnow().isoformat(),
                'total_records': len(df),
                'total_columns': len(df.columns),
                'schema_valid': len(errors) == 0,
                'errors': errors
            }

            with open('/data/report.json', 'w') as f:
                json.dump(report, f, indent=2)

            # Print summary
            if len(errors) == 0:
                print("✓ Schema validation PASSED")
            else:
                print(f"✗ Schema validation FAILED ({len(errors)} errors)")
                for err in errors:
                    print(f"  - {err}")
                exit(1)  # Fail workflow
            EOF
```

**Use in workflow:**

```bash
kubectl apply -f schema-validation.yaml -n argo

# Test with sample data
kubectl create -f - <<EOF
apiVersion: argoproj.io/v1alpha1
kind: Workflow
metadata:
  generateName: test-schema-
  namespace: argo
spec:
  entrypoint: main
  templates:
    - name: main
      steps:
        - - name: validate
            templateRef:
              name: schema-validation
              template: validate-schema
            arguments:
              artifacts:
                - name: dataset
                  s3:
                    key: "test-data/sample.parquet"
EOF
```

---

## Step 2: Statistical Validation

### Outlier Detection

Create `statistical-validation.yaml`:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: WorkflowTemplate
metadata:
  name: statistical-validation
  namespace: argo
spec:
  templates:
    - name: validate-statistics
      inputs:
        artifacts:
          - name: dataset
            path: /data/input.parquet
      outputs:
        artifacts:
          - name: stats-report
            path: /data/stats.json
      container:
        image: python:3.11-slim
        command: [sh, -c]
        args:
          - |
            pip install -q pandas pyarrow scipy
            python3 << 'EOF'
            import pandas as pd
            import json
            import numpy as np
            from scipy import stats

            df = pd.read_parquet('/data/input.parquet')

            warnings = []
            stats_summary = {}

            # Numerical columns
            numerical_cols = df.select_dtypes(include=['float64', 'int64']).columns

            for col in numerical_cols:
                col_stats = {
                    'mean': float(df[col].mean()),
                    'median': float(df[col].median()),
                    'std': float(df[col].std()),
                    'min': float(df[col].min()),
                    'max': float(df[col].max()),
                    'q25': float(df[col].quantile(0.25)),
                    'q75': float(df[col].quantile(0.75))
                }

                # Outlier detection (IQR method)
                Q1 = df[col].quantile(0.25)
                Q3 = df[col].quantile(0.75)
                IQR = Q3 - Q1

                outliers = (
                    (df[col] < (Q1 - 1.5 * IQR)) |
                    (df[col] > (Q3 + 1.5 * IQR))
                ).sum()

                col_stats['outlier_count'] = int(outliers)
                col_stats['outlier_rate'] = float(outliers / len(df))

                # Warn if high outlier rate
                if col_stats['outlier_rate'] > 0.05:  # > 5%
                    warnings.append(
                        f"{col}: {col_stats['outlier_rate']:.1%} outliers"
                    )

                # Check for constant values
                if df[col].nunique() == 1:
                    warnings.append(f"{col}: constant value ({df[col].iloc[0]})")

                stats_summary[col] = col_stats

            # Generate report
            report = {
                'total_records': len(df),
                'statistics': stats_summary,
                'warnings': warnings,
                'valid': len(warnings) < 5  # Warn if > 5 issues
            }

            with open('/data/stats.json', 'w') as f:
                json.dump(report, f, indent=2)

            # Print summary
            print(f"Statistical Validation: {len(warnings)} warnings")
            for w in warnings:
                print(f"  ⚠ {w}")

            if len(warnings) >= 5:
                print("\n✗ Too many statistical issues, failing workflow")
                exit(1)
            else:
                print("\n✓ Statistical validation passed")
            EOF
```

---

## Step 3: Data Drift Detection

### Distribution Shift Detection

**Kolmogorov-Smirnov Test** compares distributions:

Create `drift-detection.yaml`:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: WorkflowTemplate
metadata:
  name: drift-detection
  namespace: argo
spec:
  templates:
    - name: detect-drift
      inputs:
        artifacts:
          - name: current-data
            path: /data/current.parquet
          - name: reference-data
            path: /data/reference.parquet
      outputs:
        artifacts:
          - name: drift-report
            path: /data/drift.json
      container:
        image: python:3.11-slim
        command: [sh, -c]
        args:
          - |
            pip install -q pandas pyarrow scipy
            python3 << 'EOF'
            import pandas as pd
            import json
            from scipy import stats

            # Load data
            df_current = pd.read_parquet('/data/current.parquet')
            df_reference = pd.read_parquet('/data/reference.parquet')

            drift_results = []
            drift_detected = False

            # Get common numerical columns
            numerical_cols = list(
                set(df_current.select_dtypes(include=['float64', 'int64']).columns) &
                set(df_reference.select_dtypes(include=['float64', 'int64']).columns)
            )

            for col in numerical_cols:
                # KS test for distribution similarity
                ks_stat, p_value = stats.ks_2samp(
                    df_reference[col].dropna(),
                    df_current[col].dropna()
                )

                # Mean shift
                mean_shift = abs(
                    df_current[col].mean() - df_reference[col].mean()
                ) / df_reference[col].std() if df_reference[col].std() > 0 else 0

                # Drift detected if p < 0.05 or mean shift > 0.5 std devs
                has_drift = p_value < 0.05 or mean_shift > 0.5

                if has_drift:
                    drift_detected = True

                drift_results.append({
                    'column': col,
                    'ks_statistic': float(ks_stat),
                    'p_value': float(p_value),
                    'mean_shift': float(mean_shift),
                    'drift_detected': has_drift
                })

            # Generate report
            report = {
                'drift_detected': drift_detected,
                'drifted_columns': [
                    r['column'] for r in drift_results if r['drift_detected']
                ],
                'drift_results': drift_results
            }

            with open('/data/drift.json', 'w') as f:
                json.dump(report, f, indent=2)

            # Print summary
            if drift_detected:
                print("⚠ DRIFT DETECTED")
                for r in drift_results:
                    if r['drift_detected']:
                        print(f"  - {r['column']}: p={r['p_value']:.4f}, shift={r['mean_shift']:.2f}σ")
            else:
                print("✓ No drift detected")
            EOF
```

**When to retrain based on drift:**

- **Low drift** (mean shift < 0.3): Monitor
- **Medium drift** (0.3-0.5): Alert team
- **High drift** (> 0.5): Trigger retraining

---

## Step 4: Complete Validation Pipeline

### End-to-End Example

Create `full-validation-pipeline.yaml`:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Workflow
metadata:
  generateName: validate-data-
  namespace: argo
spec:
  entrypoint: validation-pipeline

  templates:
    - name: validation-pipeline
      dag:
        tasks:
          # Fetch data from Kafka
          - name: fetch-data
            template: fetch-from-kafka

          # Parallel validation
          - name: validate-schema
            dependencies: [fetch-data]
            templateRef:
              name: schema-validation
              template: validate-schema
            arguments:
              artifacts:
                - name: dataset
                  from: "{{tasks.fetch-data.outputs.artifacts.data}}"

          - name: validate-stats
            dependencies: [fetch-data]
            templateRef:
              name: statistical-validation
              template: validate-statistics
            arguments:
              artifacts:
                - name: dataset
                  from: "{{tasks.fetch-data.outputs.artifacts.data}}"

          - name: detect-drift
            dependencies: [fetch-data]
            templateRef:
              name: drift-detection
              template: detect-drift
            arguments:
              artifacts:
                - name: current-data
                  from: "{{tasks.fetch-data.outputs.artifacts.data}}"
                - name: reference-data
                  s3:
                    key: "reference-data/baseline.parquet"

          # Generate quality report
          - name: quality-report
            dependencies: [validate-schema, validate-stats, detect-drift]
            template: generate-report
            arguments:
              artifacts:
                - name: schema-report
                  from: "{{tasks.validate-schema.outputs.artifacts.validation-report}}"
                - name: stats-report
                  from: "{{tasks.validate-stats.outputs.artifacts.stats-report}}"
                - name: drift-report
                  from: "{{tasks.detect-drift.outputs.artifacts.drift-report}}"

          # Send alert if quality low
          - name: alert
            dependencies: [quality-report]
            template: send-alert
            when: "{{tasks.quality-report.outputs.result}} == 'FAIL'"

    # Template: Fetch from Kafka
    - name: fetch-from-kafka
      outputs:
        artifacts:
          - name: data
            path: /data/fetched.parquet
      container:
        image: python:3.11-slim
        command: [sh, -c]
        args:
          - |
            pip install -q pandas pyarrow kafka-python-ng
            python3 << 'EOF'
            import pandas as pd
            import json
            from kafka import KafkaConsumer

            consumer = KafkaConsumer(
                'ml-raw-data',
                bootstrap_servers=['ml-data-cluster-kafka-bootstrap.kafka.svc.cluster.local:9092'],
                group_id='validation-pipeline',
                auto_offset_reset='earliest',
                max_poll_records=1000,
                value_deserializer=lambda m: json.loads(m.decode('utf-8'))
            )

            records = []
            for message in consumer:
                records.append(message.value)
                if len(records) >= 1000:
                    break

            df = pd.DataFrame(records)
            df.to_parquet('/data/fetched.parquet', index=False)
            consumer.close()

            print(f"Fetched {len(df)} records")
            EOF

    # Template: Generate quality report
    - name: generate-report
      inputs:
        artifacts:
          - name: schema-report
            path: /data/schema.json
          - name: stats-report
            path: /data/stats.json
          - name: drift-report
            path: /data/drift.json
      outputs:
        result: /data/status.txt
      container:
        image: python:3.11-slim
        command: [sh, -c]
        args:
          - |
            python3 << 'EOF'
            import json

            with open('/data/schema.json') as f:
                schema = json.load(f)
            with open('/data/stats.json') as f:
                stats = json.load(f)
            with open('/data/drift.json') as f:
                drift = json.load(f)

            # Determine overall status
            if not schema['schema_valid']:
                status = 'FAIL'
            elif drift['drift_detected']:
                status = 'WARNING'
            elif not stats['valid']:
                status = 'WARNING'
            else:
                status = 'PASS'

            with open('/data/status.txt', 'w') as f:
                f.write(status)

            print(f"Data Quality: {status}")
            print(f"  Schema: {'✓' if schema['schema_valid'] else '✗'}")
            print(f"  Statistics: {'✓' if stats['valid'] else '⚠'}")
            print(f"  Drift: {'⚠' if drift['drift_detected'] else '✓'}")
            EOF

    # Template: Send alert
    - name: send-alert
      container:
        image: python:3.11-slim
        command: [sh, -c]
        args:
          - |
            pip install -q kafka-python-ng
            python3 << 'EOF'
            import json
            from kafka import KafkaProducer

            producer = KafkaProducer(
                bootstrap_servers=['ml-data-cluster-kafka-bootstrap.kafka.svc.cluster.local:9092'],
                value_serializer=lambda v: json.dumps(v).encode('utf-8')
            )

            alert = {
                'type': 'data_quality_alert',
                'severity': 'high',
                'message': 'Data validation failed'
            }

            producer.send('ml-data-quality', value=alert)
            producer.flush()
            print("🚨 Alert sent to ml-data-quality topic")
            EOF
```

---

## Best Practices

### 1. Fail Fast on Schema Errors

Schema violations always fail the workflow:

```python
if not schema_valid:
    print("Schema validation failed")
    exit(1)  # Hard failure
```

### 2. Warn on Statistical Issues

Statistical anomalies generate warnings but continue:

```python
if outlier_rate > 0.05:
    print(f"WARNING: {outlier_rate:.1%} outliers")
    # Continue workflow
```

### 3. Alert on Drift

Drift triggers alerts and potentially retraining:

```python
if drift_detected:
    send_kafka_alert("Drift detected, consider retraining")
    # Optional: trigger retraining workflow
```

### 4. Use Reference Datasets

Store baseline distributions for drift detection:

```bash
# Save reference data to S3
aws s3 cp reference-baseline.parquet s3://ml-pipeline-artifacts/reference-data/baseline.parquet
```

---

## Monitoring Quality Over Time

### Track Validation Metrics in Prometheus

```python
from prometheus_client import Gauge

# Define metrics
schema_valid = Gauge('ml_schema_validation', 'Schema validation status')
outlier_rate = Gauge('ml_outlier_rate', 'Outlier detection rate')
drift_score = Gauge('ml_drift_score', 'Data drift score')

# Update in validation workflow
schema_valid.set(1 if valid else 0)
outlier_rate.set(outliers / total_records)
drift_score.set(ks_statistic)
```

### Alert Rules

```yaml
groups:
  - name: data-quality
    rules:
      - alert: SchemaValidationFailed
        expr: ml_schema_validation == 0
        for: 5m
        annotations:
          summary: "Schema validation failed for {{ $labels.dataset }}"

      - alert: HighDriftDetected
        expr: ml_drift_score > 0.5
        for: 30m
        annotations:
          summary: "Data drift detected, consider retraining"
```

---

## Troubleshooting

### Issue: False Positives in Drift Detection

**Symptom:** Drift detected on seasonal data

**Fix:** Normalize for time-based patterns:

```python
# Remove seasonal effects before KS test
from statsmodels.tsa.seasonal import seasonal_decompose

decomposition = seasonal_decompose(df['value'], model='additive', period=24)
df['deseasonalized'] = df['value'] - decomposition.seasonal
```

### Issue: Slow Validation on Large Datasets

**Symptom:** Validation takes > 10 minutes

**Fix:** Sample large datasets:

```python
# Sample 10% of data for validation
df_sample = df.sample(frac=0.1, random_state=42)
```

---

## Next Steps

- **Tutorial 04:** [Feature Engineering](04-feature-engineering.md)
- **Example:** [Data Validation Workflow](../../components/01-data-pipeline/argo-workflows/data-validation-workflow.yaml)
- **Docs:** [Cross-Foundation Integration](../decision-frameworks/cross-foundation.md)
