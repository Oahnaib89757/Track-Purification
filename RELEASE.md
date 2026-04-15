# RELEASE

## Release Types

- Stable release:
  - From `stable/baseline`
  - Tag format: `v1.x.y-stable`

- Experiment checkpoint:
  - From `experiment/heatmap-2s`
  - Tag format: `exp-heatmap-YYYYMMDD`

## Stable Release Steps

```powershell
git checkout stable/baseline
git pull
git tag -a v1.0.0-stable -m "baseline stable release"
git push origin v1.0.0-stable
```

Then merge forward:

```powershell
git checkout main
git pull
git merge stable/baseline
git push
```

## Experiment Checkpoint Steps

```powershell
git checkout experiment/heatmap-2s
git pull
git tag -a exp-heatmap-20260415 -m "heatmap checkpoint"
git push origin exp-heatmap-20260415
```

## Release Gate

Before any stable tag:

- Core scripts are runnable.
- Docs are up to date.
- No large data files are tracked.
- Open issues for known limitations are documented.

