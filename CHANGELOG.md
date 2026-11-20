# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/), and this project adheres to [Semantic Versioning](https://semver.org/).

## [0.3.0] - 2026-11-20

### Added

- Comments on a file as a whole (`git_diff_live comment path:file ...`), drawn under the file's heading and, while the file is collapsed, on one line in it. For a deleted, moved or binary file, which has no line of its own to comment on.
- `git_diff_live changes` lists a file with no changed lines (moved, binary) as a change to comment on, and names what a renamed file was renamed from.

## [0.2.0] - 2026-11-20

### Added

- Comments: a bubble beside a change saying why it was made. Written with the new `git_diff_live` command (`changes`, `comment`), kept in `.git_diff_live/comments.jsonl` and committed with the code; a comparison shows the comments written within it.
- `skills/explain-changes`: the Claude Code skill an agent writes the comments with.
- Compare two commits: `?base=HEAD~1&head=HEAD`, the "to" field beside "From".

### Changed

- The "Compare with" field is now "From", with "to" beside it.

## [0.1.0] - 2026-11-18

### Added

- The changes page: every file that differs between the working tree and a commit, side by side, with the words that changed marked inside each line. Staged, unstaged and untracked work together; renames shown as `old → new`.
- Live reload: the page polls a fingerprint of the diff and redraws only the files that changed, came or went.
- "Whole file" per file, "Compare with" any revision, "Open" in VS Code at the first changed line (WSL aware, other editors through `config.editor_url`).
- `GitDiffLive.configure`: `root`, `enabled`, `poll_interval`, `context`, `stylesheets`, `editor_url`.
