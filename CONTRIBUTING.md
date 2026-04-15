# CONTRIBUTING

## Scope

This repository is for **code and documentation management** only.
Large datasets and generated artifacts must not be committed.

## Before You Start

1. Pull latest `main`.
2. Create a task branch (`feature/*`, `fix/*`, or `docs/*`).
3. Confirm `.gitignore` excludes your local large files.

## Commit Convention

Use concise conventional messages:

- `feat(scope): ...`
- `fix(scope): ...`
- `docs(scope): ...`
- `refactor(scope): ...`

Examples:

- `feat(heatmap): add density score normalization`
- `fix(parser): handle empty plotInfo safely`
- `docs(workflow): update branching policy`

## Pull Request Checklist

- Code runs locally (or clearly documents runtime prerequisites).
- No raw data, processed data, or logs are included.
- Relevant docs are updated (`VERSION_MAP`, `CODE_MANAGEMENT`, etc.).
- Changes are focused and scoped.

## Data Rule (Strict)

Do not push:

- raw data (`.dat`, `.csv`)
- processed tracks (`Tracks_*.txt`)
- binaries / model artifacts (`.mat`, `.npy`, `.npz`, etc.)
- screenshots and generated plots unless specifically needed for docs

