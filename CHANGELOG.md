# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/), and this project adheres to [Semantic Versioning](https://semver.org/).

## [0.1.0] - 2026-11-18

### Added

- The changes page: every file that differs between the working tree and a commit, side by side, with the words that changed marked inside each line. Staged, unstaged and untracked work together; renames shown as `old → new`.
- Live reload: the page polls a fingerprint of the diff and redraws only the files that changed, came or went.
- "Whole file" per file, "Compare with" any revision, "Open" in VS Code at the first changed line (WSL aware, other editors through `config.editor_url`).
- `GitDiffLive.configure`: `root`, `enabled`, `poll_interval`, `context`, `stylesheets`, `editor_url`.
