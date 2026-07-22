# Changelog

本文件遵循 Keep a Changelog；版本约定见 [f2b-meta RELEASE.md](https://github.com/f2b-dev/f2b-meta/blob/main/RELEASE.md)。

## [Unreleased]

### Added

- `scripts/cube-preflight.sh`：KVM/内存预检与 `--accept`

### Fixed

- `install-all-in-one.sh` 页脚 Cube 预检路径：未定义 `$ROOT` → `${F2B_ROOT}/f2b-infra/scripts/...`

### Changed

- 香港 runbook：`cube-preflight` + Playwright e2e:ui 公网验收说明；install 页脚提示
- 香港 runbook 补充 Fake 全路径 `e2e:bff` 验收命令

## [0.1.0] - 2026-07

- all-in-one compose / install 脚本；cube-single-node 与 ops 文档
