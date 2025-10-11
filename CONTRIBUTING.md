# Contributing to CNCF MLOps Pipeline

Thank you for your interest in contributing to the CNCF MLOps Pipeline reference architecture!

## Quick Start

1. Fork the repository
2. Create a feature branch: `git checkout -b feature/your-feature`
3. Make your changes following our style guidelines
4. Add tests for your changes
5. Commit: `git commit -m "Add feature: description"`
6. Push: `git push origin feature/your-feature`
7. Open a Pull Request

## Code of Conduct

This project adheres to the [CNCF Code of Conduct](CODE_OF_CONDUCT.md). By participating, you are expected to uphold this code.

## How to Contribute

### Types of Contributions

- **Bug Reports:** [Open an issue](https://github.com/yourusername/cncf-mlops-pipeline/issues/new)
- **Feature Requests:** Propose new CNCF project integrations or optimizations
- **Documentation:** Improve clarity, fix typos, add examples
- **Code:** New training examples, cost optimization techniques, integrations
- **Experience Reports:** Share production deployment learnings

### Before You Start

- Search existing issues to avoid duplicates
- Discuss major changes in an issue first
- Read the architecture docs to understand design decisions

## Development Process

### Branch Naming

- `feature/` - New features
- `fix/` - Bug fixes
- `docs/` - Documentation changes
- `test/` - Test additions

### Commit Messages

```
Add Volcano gang scheduling example for JAX

- Adds distributed JAX training example
- Includes gang scheduling configuration
- Documents common JAX-specific issues

Closes #123
```

Use imperative mood, wrap at 72 characters, reference issues.

## Style Guidelines

### YAML Manifests

```yaml
# ABOUTME: Brief description of manifest purpose
# ABOUTME: Additional context if needed
apiVersion: v1
kind: Pod
metadata:
  name: example-pod
  labels:
    app: training
spec:
  containers:
  - name: trainer
    resources:
      limits:
        nvidia.com/gpu: 2  # Always set GPU limits
```

### Python Scripts

- Use type hints
- Add docstrings (Google style)
- Include `ABOUTME:` comments at file start
- Follow PEP 8

### Shell Scripts

- Use `#!/usr/bin/env bash`
- Set `set -euo pipefail`
- Add `ABOUTME:` comments
- Provide colored output for user feedback

## Testing Requirements

All contributions must include tests:

```bash
# Validate YAML
kubectl apply --dry-run=client -f your-manifest.yaml

# Run integration tests
./tests/integration/test-your-feature.sh
```

## Pull Request Process

1. Ensure all tests pass
2. Update documentation as needed
3. Add yourself to ACKNOWLEDGMENTS.md
4. Request review from maintainers
5. Address review feedback
6. Maintainer will merge once approved

## Community

- **Slack:** #mlops-cncf-tutorial on CNCF Slack
- **GitHub Discussions:** Ask questions, share ideas
- **Monthly Community Call:** First Thursday, 9:00 AM PT

## License

By contributing, you agree that your contributions will be licensed under the Apache License 2.0.

## Recognition

Contributors are recognized in:
- ACKNOWLEDGMENTS.md
- GitHub contributor graph
- KubeCon presentations (if applicable)

**Thank you for helping make CNCF MLOps accessible to everyone!**
