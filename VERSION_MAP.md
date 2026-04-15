# VERSION MAP

## Active

- `process_tracks_for_labeling one criteria.py`
  - Status: stable
  - Purpose: split tracks with GPS matching and export `Tracks_*.txt`

- `filter_uav_by_manual_labels.py`
  - Status: stable
  - Purpose: keep only manually labeled UAV batches

- `check_uav_hit_rate.py`
  - Status: stable
  - Purpose: hit-rate verification and recovery check

- `MATLAB/Track_DBSCAN_6s.m`
  - Status: stable baseline
  - Purpose: 6s-cycle clutter filtering + visualization

- `MATLAB/Track_DBSCAN_2s.m`
  - Status: experimental
  - Purpose: 2s-cycle filtering + heatmap-oriented experiments

## Historical

Historical scripts should be archived under `legacy/` once replaced.

## Rules

- Do not develop against archived scripts directly in `main`.
- If historical logic is needed, port selectively via a feature branch.
- Update this file whenever active ownership changes.

