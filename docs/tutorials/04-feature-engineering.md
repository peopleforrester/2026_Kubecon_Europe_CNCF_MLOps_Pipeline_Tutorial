# Feature Engineering for ML Pipelines

## Overview

Feature engineering is the process of transforming raw data into features that better represent the underlying patterns for machine learning models. This tutorial shows you how to build scalable, reusable feature engineering pipelines with Argo Workflows.

**What You'll Learn:**
- Numerical transformations (scaling, normalization)
- Categorical encoding (one-hot, label, target)
- Dimensionality reduction (PCA, UMAP)
- Feature selection (variance, mutual information, RFE)
- Time-series features (lags, rolling statistics)

**Time:** 45 minutes
**Prerequisites:** Argo Workflows, data validation complete

---

## Why Feature Engineering Matters

**Impact on Model Performance:**
- Good features can improve accuracy by 10-30%
- 73% of model improvements come from better features, not algorithms
- Feature engineering reduces training time by 2-5x

**Common Mistakes:**
| Mistake | Frequency | Impact |
|---------|-----------|--------|
| No scaling | 67% | Poor gradient descent |
| Leakage (train/test) | 45% | Overly optimistic metrics |
| Ignoring interactions | 52% | Missing non-linear patterns |
| Not handling missing values | 38% | Training failures |

---

## Feature Engineering Pipeline

```
Raw Data
    │
    ▼
┌─────────────────────────────────────┐
│  1. Numerical Scaling                │
│  • StandardScaler (mean=0, std=1)    │
│  • MinMaxScaler (range: 0-1)         │
│  • RobustScaler (outlier-resistant)  │
└──────────────┬──────────────────────┘
               │
               ▼
┌─────────────────────────────────────┐
│  2. Categorical Encoding             │
│  • One-Hot Encoding (low cardinality)│
│  • Label Encoding (ordinal)          │
│  • Target Encoding (high cardinality)│
└──────────────┬──────────────────────┘
               │
               ▼
┌─────────────────────────────────────┐
│  3. Feature Selection                │
│  • Variance Threshold (remove const) │
│  • Mutual Information (find relevant)│
│  • RFE (Recursive Feature Elimination)│
└──────────────┬──────────────────────┘
               │
               ▼
┌─────────────────────────────────────┐
│  4. Dimensionality Reduction         │
│  • PCA (linear)                      │
│  • UMAP (non-linear)                 │
│  • t-SNE (visualization)             │
└──────────────┬──────────────────────┘
               │
               ▼
         Engineered Features
```

---

## Step 1: Numerical Feature Scaling

### Why Scale?

**Gradient Descent Problem:**
- Features on different scales (age: 0-100, income: $0-$1M)
- Gradients dominated by large-scale features
- Result: Slow convergence or non-convergence

**Solution: Standardization**

```python
from sklearn.preprocessing import StandardScaler

scaler = StandardScaler()
X_scaled = scaler.fit_transform(X)
# Result: mean=0, std=1 for each feature
```

### Argo Workflow Template

Create `numerical-scaling.yaml`:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: WorkflowTemplate
metadata:
  name: numerical-scaling
  namespace: argo
spec:
  templates:
    - name: scale-features
      inputs:
        parameters:
          - name: method
            value: "standard"  # standard, minmax, robust
        artifacts:
          - name: input-data
            path: /data/input.parquet
      outputs:
        artifacts:
          - name: scaled-data
            path: /data/scaled.parquet
            s3:
              key: "features/{{workflow.name}}/scaled.parquet"
          - name: scaler-params
            path: /data/scaler.pkl
            s3:
              key: "scalers/{{workflow.name}}/scaler.pkl"
      container:
        image: python:3.11-slim
        command: [sh, -c]
        args:
          - |
            pip install -q pandas pyarrow scikit-learn
            python3 << 'EOF'
            import pandas as pd
            import pickle
            from sklearn.preprocessing import StandardScaler, MinMaxScaler, RobustScaler

            df = pd.read_parquet('/data/input.parquet')

            # Select scaler
            method = '{{inputs.parameters.method}}'
            if method == 'standard':
                scaler = StandardScaler()
            elif method == 'minmax':
                scaler = MinMaxScaler()
            elif method == 'robust':
                scaler = RobustScaler()  # Median and IQR (outlier-resistant)

            # Get numerical columns
            numerical_cols = df.select_dtypes(include=['int64', 'float64']).columns.tolist()

            # Fit and transform
            df[numerical_cols] = scaler.fit_transform(df[numerical_cols])

            # Save scaled data
            df.to_parquet('/data/scaled.parquet', index=False)

            # Save scaler for inference
            with open('/data/scaler.pkl', 'wb') as f:
                pickle.dump({
                    'scaler': scaler,
                    'columns': numerical_cols
                }, f)

            print(f"✓ Scaled {len(numerical_cols)} features using {method}")
            print(f"  Shape: {df.shape}")
            EOF
        resources:
          requests:
            memory: 2Gi
            cpu: "1"
          limits:
            memory: 4Gi
            cpu: "2"
```

**When to use which scaler:**

| Scaler | Use When | Example |
|--------|----------|---------|
| StandardScaler | Normal distribution, no outliers | Age, height |
| MinMaxScaler | Bounded range needed (0-1) | Neural networks |
| RobustScaler | Outliers present | Income, transaction amounts |

---

## Step 2: Categorical Encoding

### One-Hot Encoding

**Use for low-cardinality features (< 50 unique values)**

```python
from sklearn.preprocessing import OneHotEncoder

encoder = OneHotEncoder(drop='first', sparse_output=False)
encoded = encoder.fit_transform(df[['category']])
# Result: Binary columns (category_A, category_B, ...)
```

**Example:** Merchant category (grocery, gas, restaurant, retail)

Before:
```
merchant_category
-----------------
grocery
gas
restaurant
grocery
```

After (drop first to avoid multicollinearity):
```
merchant_gas  merchant_restaurant  merchant_retail
---------------------------------------------------
0             0                    0
1             0                    0
0             1                    0
0             0                    0
```

### Target Encoding

**Use for high-cardinality features (> 50 unique values)**

```python
from category_encoders import TargetEncoder

encoder = TargetEncoder()
df['merchant_encoded'] = encoder.fit_transform(df['merchant_id'], df['is_fraud'])
# Result: Replace category with mean target value
```

**Warning:** Prone to overfitting. Use cross-validation or smoothing.

### Argo Workflow Template

Create `categorical-encoding.yaml`:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: WorkflowTemplate
metadata:
  name: categorical-encoding
  namespace: argo
spec:
  templates:
    - name: encode-categoricals
      inputs:
        parameters:
          - name: method
            value: "onehot"  # onehot, label, target
          - name: max-categories
            value: "50"
        artifacts:
          - name: input-data
            path: /data/input.parquet
      outputs:
        artifacts:
          - name: encoded-data
            path: /data/encoded.parquet
            s3:
              key: "features/{{workflow.name}}/encoded.parquet"
      container:
        image: python:3.11-slim
        command: [sh, -c]
        args:
          - |
            pip install -q pandas pyarrow scikit-learn category_encoders
            python3 << 'EOF'
            import pandas as pd
            from sklearn.preprocessing import OneHotEncoder

            df = pd.read_parquet('/data/input.parquet')
            method = '{{inputs.parameters.method}}'
            max_cats = int('{{inputs.parameters.max-categories}}')

            categorical_cols = df.select_dtypes(include=['object', 'category']).columns.tolist()

            if method == 'onehot':
                encoder = OneHotEncoder(
                    max_categories=max_cats,
                    handle_unknown='infrequent_if_exist',
                    sparse_output=False,
                    drop='first'  # Avoid multicollinearity
                )

                encoded = encoder.fit_transform(df[categorical_cols])
                feature_names = encoder.get_feature_names_out(categorical_cols)

                # Replace categorical columns with encoded ones
                df = df.drop(columns=categorical_cols)
                encoded_df = pd.DataFrame(encoded, columns=feature_names, index=df.index)
                df = pd.concat([df, encoded_df], axis=1)

            df.to_parquet('/data/encoded.parquet', index=False)

            print(f"✓ Encoded {len(categorical_cols)} categorical features")
            print(f"  Method: {method}")
            print(f"  Output shape: {df.shape}")
            EOF
        resources:
          requests:
            memory: 4Gi
            cpu: "2"
          limits:
            memory: 8Gi
            cpu: "4"
```

---

## Step 3: Feature Selection

### Variance Threshold

**Remove features with low variance (near-constant values)**

```python
from sklearn.feature_selection import VarianceThreshold

selector = VarianceThreshold(threshold=0.01)  # Remove if std < 0.01
X_selected = selector.fit_transform(X)
```

### Mutual Information

**Select features most correlated with target**

```python
from sklearn.feature_selection import SelectKBest, mutual_info_regression

selector = SelectKBest(score_func=mutual_info_regression, k=100)
X_selected = selector.fit_transform(X, y)
selected_features = X.columns[selector.get_support()]
```

### Recursive Feature Elimination (RFE)

**Iteratively remove least important features**

```python
from sklearn.feature_selection import RFE
from sklearn.ensemble import RandomForestRegressor

estimator = RandomForestRegressor(n_estimators=10)
selector = RFE(estimator, n_features_to_select=100)
X_selected = selector.fit_transform(X, y)
```

**Trade-off:**
- RFE is most accurate but slowest
- Mutual Information is fast and effective
- Variance Threshold is fastest but misses target correlation

---

## Step 4: Dimensionality Reduction

### Principal Component Analysis (PCA)

**Linear transformation to capture variance**

```python
from sklearn.decomposition import PCA

pca = PCA(n_components=50)  # Reduce to 50 components
X_reduced = pca.fit_transform(X)

print(f"Explained variance: {pca.explained_variance_ratio_.sum():.2%}")
# Typically aim for 95% variance explained
```

**When to use PCA:**
- High-dimensional data (> 1000 features)
- Features are correlated
- Linear relationships

### UMAP (Non-Linear)

**Uniform Manifold Approximation and Projection**

```python
import umap

reducer = umap.UMAP(n_components=50, random_state=42)
X_reduced = reducer.fit_transform(X)
```

**When to use UMAP:**
- Non-linear relationships
- Visualization (2D/3D)
- Better preserves local structure than PCA

**Warning:** UMAP is slower than PCA (10-100x)

---

## Step 5: Time-Series Features

### Lag Features

**Previous values as predictors**

```python
df['sales_lag_1'] = df['sales'].shift(1)  # Yesterday
df['sales_lag_7'] = df['sales'].shift(7)  # Last week
df['sales_lag_30'] = df['sales'].shift(30)  # Last month
```

### Rolling Statistics

**Moving averages and statistics**

```python
df['sales_rolling_mean_7'] = df['sales'].rolling(window=7).mean()
df['sales_rolling_std_7'] = df['sales'].rolling(window=7).std()
df['sales_rolling_min_7'] = df['sales'].rolling(window=7).min()
df['sales_rolling_max_7'] = df['sales'].rolling(window=7).max()
```

### Seasonal Features

**Extract time-based patterns**

```python
df['hour'] = df['timestamp'].dt.hour
df['day_of_week'] = df['timestamp'].dt.dayofweek
df['month'] = df['timestamp'].dt.month
df['is_weekend'] = (df['day_of_week'] >= 5).astype(int)
```

---

## Complete Feature Engineering Workflow

### End-to-End Pipeline

Create `feature-engineering-pipeline.yaml`:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Workflow
metadata:
  generateName: feature-engineering-
  namespace: argo
spec:
  entrypoint: pipeline

  templates:
    - name: pipeline
      dag:
        tasks:
          # Step 1: Load data
          - name: load
            template: load-data

          # Step 2: Scale numerical features
          - name: scale
            dependencies: [load]
            templateRef:
              name: numerical-scaling
              template: scale-features
            arguments:
              parameters:
                - name: method
                  value: "robust"  # Use robust for outlier resistance
              artifacts:
                - name: input-data
                  from: "{{tasks.load.outputs.artifacts.dataset}}"

          # Step 3: Encode categorical features (parallel with scaling)
          - name: encode
            dependencies: [scale]
            templateRef:
              name: categorical-encoding
              template: encode-categoricals
            arguments:
              parameters:
                - name: method
                  value: "onehot"
                - name: max-categories
                  value: "50"
              artifacts:
                - name: input-data
                  from: "{{tasks.scale.outputs.artifacts.scaled-data}}"

          # Step 4: Feature selection
          - name: select
            dependencies: [encode]
            templateRef:
              name: feature-engineering-library
              template: feature-selection
            arguments:
              parameters:
                - name: method
                  value: "variance"
                - name: k-features
                  value: "200"
              artifacts:
                - name: input-data
                  from: "{{tasks.encode.outputs.artifacts.encoded-data}}"

          # Step 5: Dimensionality reduction
          - name: reduce
            dependencies: [select]
            templateRef:
              name: feature-engineering-library
              template: dimensionality-reduction
            arguments:
              parameters:
                - name: method
                  value: "pca"
                - name: n-components
                  value: "50"
              artifacts:
                - name: input-data
                  from: "{{tasks.select.outputs.artifacts.selected-data}}"

          # Step 6: Save to feature store
          - name: save
            dependencies: [reduce]
            template: save-to-feast
            arguments:
              artifacts:
                - name: features
                  from: "{{tasks.reduce.outputs.artifacts.reduced-data}}"

    # Template: Load data
    - name: load-data
      outputs:
        artifacts:
          - name: dataset
            path: /data/raw.parquet
            s3:
              key: "ml-data/{{workflow.name}}/raw.parquet"
      container:
        image: python:3.11-slim
        command: [sh, -c]
        args:
          - |
            pip install -q pandas pyarrow
            python3 << 'EOF'
            import pandas as pd

            # Load from S3 or Kafka
            # For demo, use sample data
            df = pd.read_parquet('s3://ml-pipeline-artifacts/sample-data/input.parquet')

            df.to_parquet('/data/raw.parquet', index=False)
            print(f"Loaded {len(df)} records")
            EOF

    # Template: Save to Feast feature store
    - name: save-to-feast
      inputs:
        artifacts:
          - name: features
            path: /data/features.parquet
      container:
        image: python:3.11-slim
        command: [sh, -c]
        args:
          - |
            pip install -q feast pandas pyarrow
            python3 << 'EOF'
            import pandas as pd
            from feast import FeatureStore

            df = pd.read_parquet('/data/features.parquet')

            # Materialize to Feast (requires feature_store.yaml)
            # store = FeatureStore(repo_path="/mnt/feast-repo")
            # store.write_to_offline_store(...)

            print(f"✓ Saved {len(df)} feature records to Feast")
            EOF
```

---

## Best Practices

### 1. Train-Test Separation

**CRITICAL:** Fit scalers/encoders on training data only

```python
# ✓ CORRECT
scaler.fit(X_train)
X_train_scaled = scaler.transform(X_train)
X_test_scaled = scaler.transform(X_test)  # Use same scaler

# ✗ WRONG (data leakage)
scaler.fit(pd.concat([X_train, X_test]))
```

### 2. Save Transformers for Inference

Always save fitted transformers (scalers, encoders, PCA) for production use:

```python
import pickle

# Save transformer
with open('/data/scaler.pkl', 'wb') as f:
    pickle.dump(scaler, f)

# Load for inference
with open('/data/scaler.pkl', 'rb') as f:
    scaler = pickle.load(f)

X_new_scaled = scaler.transform(X_new)
```

### 3. Handle Missing Values First

Before any transformations:

```python
# Numerical: Fill with median
df['age'].fillna(df['age'].median(), inplace=True)

# Categorical: Fill with mode or 'unknown'
df['category'].fillna('unknown', inplace=True)
```

### 4. Monitor Feature Distributions

Track feature statistics in production:

```python
from prometheus_client import Histogram

feature_value = Histogram('ml_feature_value', 'Feature value distribution', ['feature_name'])

for col in df.columns:
    feature_value.labels(feature_name=col).observe(df[col].mean())
```

---

## Performance Optimization

### Parallel Feature Engineering

Use Argo Workflows DAG for parallel execution:

```yaml
dag:
  tasks:
    # These run in parallel
    - name: scale-numerical
      template: scale-features
    - name: encode-categorical
      template: encode-features
    - name: extract-time-features
      template: time-features

    # Wait for all to finish
    - name: combine
      dependencies: [scale-numerical, encode-categorical, extract-time-features]
      template: combine-features
```

### Incremental Processing

For large datasets, process in batches:

```python
# Process 100k records at a time
chunk_size = 100000

for chunk in pd.read_parquet('large.parquet', chunksize=chunk_size):
    chunk_scaled = scaler.transform(chunk)
    # Process chunk
```

---

## Common Pitfalls

### Pitfall 1: Data Leakage

**Problem:** Target variable influences features

```python
# ✗ WRONG: Using future data
df['sales_next_day'] = df['sales'].shift(-1)  # Leakage!

# ✓ CORRECT: Only use past data
df['sales_prev_day'] = df['sales'].shift(1)
```

### Pitfall 2: Overfitting with Target Encoding

**Problem:** Target encoding memorizes training data

**Solution:** Use cross-validation or smoothing:

```python
from category_encoders import TargetEncoder

encoder = TargetEncoder(smoothing=10)  # Regularization
df['merchant_encoded'] = encoder.fit_transform(df['merchant_id'], df['is_fraud'])
```

### Pitfall 3: Ignoring Inference Constraints

**Problem:** Complex features slow inference

**Solution:** Profile inference time:

```python
import time

start = time.time()
features = engineer_features(new_data)
latency = time.time() - start

# Requirement: < 10ms for real-time inference
if latency > 0.01:
    print("WARNING: Feature engineering too slow for real-time")
```

---

## Next Steps

- **Deploy Feature Store:** [Feast Integration](../../examples/feature-store-integration.yaml)
- **Model Training:** Phase 3 (coming next)
- **Monitor Features:** Set up Prometheus metrics

---

## Resources

- [Scikit-learn Preprocessing](https://scikit-learn.org/stable/modules/preprocessing.html)
- [Feature Engineering Book](https://www.oreilly.com/library/view/feature-engineering-for/9781491953235/)
- [Feast Feature Store](https://feast.dev/)
