---
name: show-changes
description: Open the live side-by-side page of everything changed in the working tree, for reading a session's work before committing it.
disable-model-invocation: true
---

# Show Changes

The changes page (the `git_diff_live` gem, development only) draws every file that differs between the working tree and a **base** commit: old on the left, new on the right, removed in red, added in green. Staged, unstaged and untracked work all show, and the page keeps itself up to date as files change. This skill puts that page in front of the user. The page is the deliverable; the reading is theirs.

Set `PAGE` below to where this app mounts the engine.

    PAGE=https://localhost:3000/changes

## 1. Pick the base

- An argument was given (`/show-changes main`, `/show-changes HEAD~3`): that is the base.
- This session made commits: the base is the parent of the first of them (`git rev-parse <first-session-commit>^`), so committed and uncommitted work show together.
- Otherwise the base is `HEAD`: the uncommitted work.

Done when you hold one revision.

## 2. Make sure the page answers

```sh
curl -sk -o /dev/null -w "%{http_code}" "$PAGE?base=<base>"
```

Leave `?base=` off for `HEAD`.

- `200`: done.
- `404` with a one-line body: it says what is wrong with the base. Correct the base and repeat.
- No answer: the server is down. Start it in the background the way this app is started, then repeat until `200`.

## 3. Hand over the link

Reply with the URL as a link, the branch and base it compares, and, when step 2 started the server, that it is now running in the background.
