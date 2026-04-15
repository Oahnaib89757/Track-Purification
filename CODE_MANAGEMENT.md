# CODE MANAGEMENT STANDARD

This is the single reference for daily code version management in this repository.

## 1. Repository Roles

- Active stable pipeline:
  - `process_tracks_for_labeling one criteria.py`
  - `filter_uav_by_manual_labels.py`
  - `check_uav_hit_rate.py`
  - `MATLAB/Track_DBSCAN_6s.m`
- Active experiment pipeline:
  - `MATLAB/Track_DBSCAN_2s.m`
- Historical scripts:
  - `legacy/`

Rule:
- New development should not add root-level versioned scripts such as `*_vXX.*`.
- Use branches + commits for iteration, not filename proliferation.

## 2. Branch Policy

- `main`: integration branch.
- `stable/baseline`: protected stable baseline branch.
- `experiment/heatmap-2s`: active experiment branch for 2s-cycle improvements.
- `feature/*`: scoped feature work.
- `fix/*`: scoped bug-fix work.
- `docs/*`: docs-only work.

Merge policy:
- `feature/heatmap-*` -> `experiment/heatmap-2s` first.
- `experiment/heatmap-2s` -> `main` only after validation.
- `fix/stable-*` -> `stable/baseline`, then sync to `main`.

## 3. Daily Workflow

### 3.1 Start work

```powershell
git checkout main
git pull
git checkout -b feature/<topic>
```

### 3.2 Commit

```powershell
git add .
git commit -m "feat(scope): summary"
```

### 3.3 Push

```powershell
git push -u origin feature/<topic>
```

### 3.4 Merge

```powershell
git checkout main
git pull
git merge feature/<topic>
git push
```

## 4. Cross-Computer Workflow

On a new computer:

```powershell
git clone https://github.com/Oahnaib89757/Track-Purification.git
cd Track-Purification
git checkout main
git pull
```

Before each work block: `git pull`  
After each work block: `git add .` + `git commit` + `git push`

## 5. Data Handling Rule

- This repo is code-management only.
- Raw data, processed data, and large artifacts must stay out of Git.
- Use private storage paths and keep `.gitignore` updated.

## 6. Release and Tags

- Stable releases: tag from `stable/baseline` using `v1.x.y-stable`.
- Experiment checkpoints: `exp-heatmap-YYYYMMDD`.

