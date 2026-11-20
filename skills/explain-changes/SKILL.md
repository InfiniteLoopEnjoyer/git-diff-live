---
name: explain-changes
description: Write a one or two sentence comment beside every code change in the working tree saying why it was made. The changes page (git_diff_live) draws each as a bubble next to its code, and they are committed with it. Use when you have finished changing code in a session, before your closing summary, and again after any follow-up change.
---

# Explain Changes

The changes page (the `git_diff_live` gem) draws a comment bubble beside a change when one has been written for it. The reader is the person reviewing your work: the diff shows them what changed, the comment tells them why. You write the comments, from what you know of this session, with the gem's command line. They are kept in `.git_diff_live/comments.jsonl` and committed with the code, so the same comments show whenever that commit is compared later.

Write them when the work is finished and the diff has stopped moving. A comment is anchored to its line's text: when that code changes again the comment is dropped, and step 1 lists the change as uncommented again.

Run the commands the way this app runs Bundler.

## 1. List the changes that have no comment

```sh
bundle exec git_diff_live changes
```

Each change is a run of changed lines, and each line carries its reference: `+12` is line 12 of the file as it is now, `-30` is line 30 of the file as it was. A long change is cut short; `--full` prints it whole, and a path narrows the list to a file or folder.

If this session made commits, compare with the commit before the first of them, here and in step 2: `--base <revision>`.

Done when you have the list.

## 2. Write one comment for each change

```sh
bundle exec git_diff_live comment <<'EOF'
app/models/order.rb:+41 Totals were computed before discounts applied, so a discounted order was invoiced at full price.
app/models/order.rb:-58 Nothing has called `legacy_total` since the invoice rewrite.
app/views/orders/_row.html.slim:+7 The status column was unreadable in dark mode: `text-fg-muted` instead of a fixed gray.
EOF
```

One comment a line: the file's path, a colon, the reference, a space, the comment.

- **Say why, not what.** The diff already shows what changed. Give the reason: the request, bug, constraint or decision behind it, or what would go wrong without it.
- **One or two sentences**, plain text. Backticks set a name as code.
- **Anchor on the first line of the change.** The added line (`+`) when the change has one; a removal with nothing added takes its first removed line (`-`).
- **A long addition gets a comment for each part with its own reason**: each method of a new class, each section of a new view. `+N` is the line's number in the file as it is now, so read it off the file.
- **A change repeated across files** (a rename, a moved helper) gets the same few words each time.
- **Only what you know.** A change you did not make and cannot explain stays without a comment. A guess reads exactly like a reason.

A reference that is not a changed line is refused and the nearest changed lines are named; the rest of the batch is still written. A second comment on the same line replaces the first.

## 3. Check

Run step 1 again. Done when it prints `Every change has a comment.`, or lists only changes you chose to leave.

Do not edit `.git_diff_live/comments.jsonl` by hand, and include it in the commit that carries the code.
