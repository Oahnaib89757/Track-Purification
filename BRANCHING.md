# BRANCHING

This file defines the project branch map for Track-Purification.

## Canonical Branches

- `main`
  - Role: integration branch for reviewed changes.
  - Constraint: should stay runnable and understandable.

- `stable/baseline`
  - Role: frozen stable baseline.
  - Stable files:
    - `process_tracks_for_labeling one criteria.py`
    - `filter_uav_by_manual_labels.py`
    - `check_uav_hit_rate.py`
    - `MATLAB/Track_DBSCAN_6s.m`
  - Allowed changes: targeted fixes and docs updates.

- `experiment/heatmap-2s`
  - Role: active experiment line for 2s-cycle filtering and heatmap improvements.
  - Allowed changes: threshold tuning, feature fusion, diagnostics, ablation code.
  - Not release-ready by default.

## Code Layout Contract

- Root contains active code and management docs.
- Historical scripts should be moved to `legacy/`.
- `VERSION_MAP.md` is the source of truth for active vs historical ownership.

## Task Branch Policy

- New feature from experiment branch:
  - `feature/heatmap-<topic>`
- Stable bug fix from stable branch:
  - `fix/stable-<topic>`
- Docs-only update:
  - `docs/<topic>`

## Merge Policy

- `feature/heatmap-*` -> `experiment/heatmap-2s` first.
- `experiment/heatmap-2s` -> `main` only after validation.
- `fix/stable-*` -> `stable/baseline` first, then sync to `main`.

## Tag Policy

- Stable milestones:
  - `v1.x.y-stable` on `stable/baseline`
- Experiment snapshots:
  - `exp-heatmap-YYYYMMDD`

