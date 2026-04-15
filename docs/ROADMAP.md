# ROADMAP

This roadmap tracks the code-management and research milestones for Track-Purification.

## M0 Repository Setup (Done)

- Initialize repository and push baseline code to GitHub.
- Add governance docs:
  - `README.md`
  - `CODE_MANAGEMENT.md`
  - `BRANCHING.md`
  - `VERSION_MAP.md`
  - `CONTRIBUTING.md`
  - `RELEASE.md`
- Create canonical branches:
  - `main`
  - `stable/baseline`
  - `experiment/heatmap-2s`

## M1 Baseline Reproducibility

Goal:
- Make baseline scripts runnable in a clean environment.

Tasks:
- Unify path configuration (remove machine-specific absolute paths).
- Add lightweight run instructions for:
  - `process_tracks_for_labeling one criteria.py`
  - `filter_uav_by_manual_labels.py`
  - `check_uav_hit_rate.py`
  - `MATLAB/Track_DBSCAN_6s.m`
- Add a minimal reproducibility checklist in docs.

Exit criteria:
- Team member can run baseline flow with local data path updates only.

## M2 Data/Code Boundary Hardening

Goal:
- Keep repository clean and code-focused.

Tasks:
- Refine `.gitignore` as new artifact types appear.
- Add a data directory contract in docs:
  - expected local raw data locations
  - expected local output locations
- Add simple pre-commit checks (optional later).

Exit criteria:
- No accidental large data commits.

## M3 Heatmap-Oriented Experiment Line (2s)

Goal:
- Stabilize `MATLAB/Track_DBSCAN_2s.m` experiment branch and define measurable baselines.

Tasks:
- Parameter registry for 2s experiments.
- Experiment log format for each run (config + result summary).
- Side-by-side baseline comparison:
  - 6s baseline
  - 2s experimental

Exit criteria:
- At least one reproducible experiment report with comparison table.

## M4 Research Packaging

Goal:
- Convert engineering outputs into paper-ready material.

Tasks:
- Define metrics table template.
- Define figure list template:
  - flow diagram
  - heatmap comparison
  - error/failure cases
- Freeze a stable snapshot tag for manuscript drafting.

Exit criteria:
- Docs and code state can directly support paper writing.

## Working Rules

- Use branches for all changes (`feature/*`, `fix/*`, `docs/*`).
- Keep `main` always reviewable and runnable.
- Do not version by filename proliferation.
- Keep large data out of git.

