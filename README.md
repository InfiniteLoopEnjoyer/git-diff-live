# git_diff_live

A live, side-by-side page of your working tree's git changes, for Rails apps in development. Made for reading a session's work before committing it.

- Every changed file on one page: before on the left, after on the right, removed in red, added in green, and the words that changed marked inside each line.
- Staged, unstaged and untracked work together. Renames shown as `old → new`.
- **Live**: the page redraws what changes as you (or an agent) edit, without losing your place.
- "Whole file" per file, compare from any revision (`main`, `HEAD~3`, a SHA) to the working tree or to another revision, and "Open" to jump to the file in your editor.
- **Comments**: a bubble beside a change saying why it was made, written by the agent that made it and committed with the code.

It is a mountable Rails engine with its own layout, stylesheet and JavaScript. Nothing is added to your app's pages, Tailwind build or import map.

## Requirements

- Rails 7.1 or newer with Propshaft, and `git` on the `PATH`.
- [fontawesome_subsetter](https://github.com/optimuspwnius/fontawesome-subsetter) set up in the host app (Font Awesome in `vendor/fontawesome`). The page's icons come from the host's icon font; the engine registers its own views with the subsetter so they are in the build.

Turbo, Stimulus, importmap-rails and Slim come along as dependencies. The host does not have to use them itself.

## Installation

```ruby
# Gemfile
group :development do
  gem "git_diff_live"
end
```

```ruby
# config/routes.rb
mount GitDiffLive::Engine => "/changes" if defined?(GitDiffLive)
```

Start the server and open `/changes`. On its own subdomain instead:

```ruby
if defined?(GitDiffLive)
  constraints subdomain: "dev" do
    mount GitDiffLive::Engine => "/"
  end
end
```

`defined?(GitDiffLive)` keeps the route out of every environment the gem is not bundled in.

## Configuration

Every option has a default; an initializer is optional.

```ruby
# config/initializers/git_diff_live.rb
GitDiffLive.configure do | config |
  config.root          = Rails.root          # the repository to show
  config.enabled       = Rails.env.local?    # anywhere else the engine answers 404
  config.poll_interval = 2                   # seconds between checks; nil turns live reload off
  config.context       = 3                   # unchanged lines drawn around each change
  config.stylesheets   = [ "fontawesome" ]   # the host's icon font stylesheet(s)
  config.editor_url    = nil                 # nil: VS Code. Or "cursor://file%{path}:%{line}"
end if defined?(GitDiffLive)
```

### The page

| URL | |
| --- | --- |
| `/changes` | the working tree against `HEAD` |
| `/changes?base=main` | against any revision git understands |
| `/changes?base=HEAD~1&head=HEAD` | one commit against another: here, the last commit on its own |

A deleted file starts collapsed. A file with more than 1,500 changed lines is drawn when you ask for it.

## Comments

A change can carry a comment: a sentence or two on why it was made, drawn as a bubble in a column beside the code. They are meant to be written by the agent that made the change, while it still knows the reason.

```sh
bundle exec git_diff_live changes          # the changes that have no comment yet, each changed line with its reference
bundle exec git_diff_live comment <<'EOF'  # one comment a line: path, reference, comment
app/models/order.rb:+41 Totals were computed before discounts applied, so a discounted order was invoiced at full price.
app/models/order.rb:-58 Nothing has called `legacy_total` since the invoice rewrite.
app/models/legacy_invoice.rb:file Deleted: invoices are built by `Invoice` since the rewrite.
EOF
```

There are two kinds. A comment on a **line** is drawn beside it: `+41` is line 41 of the file as it is now; `-58` is line 58 of the file as it was. A comment on a **file** (`path:file`) is drawn under the file's heading, for changes that are the whole file: a delete, a move, a binary file. It also shows on one line in the heading while the file is collapsed, as a deleted file is to begin with. `--base <revision>` compares with something other than `HEAD`. `skills/explain-changes/SKILL.md` is the Claude Code skill that drives these two commands at the end of a session: copy it to `.claude/skills/explain-changes/` in the app.

### Where they are kept

In `.git_diff_live/comments.jsonl`, one JSON object a line, in the repository. Commit it with the code it explains.

A comparison shows the comments that file **gained** between its two ends, read off the same `git diff` as the changed files. So a comment written for a commit shows with that commit: in the working tree before it is committed, in `?base=<its parent>&head=<it>` ever after, and in any wider comparison that spans it. Nothing earlier leaks in, and the file itself is never listed as a change.

A comment on a line is anchored to the line's text, not its position. It stays beside its code when lines above come and go, and it is left out once that code has been changed again. The command line removes such a comment the next time it writes, as long as it has not been committed. A comment on a file shows for as long as the file is one of the changes.

The file only grows, at roughly 250 bytes a comment. `.git_diff_live/.gitattributes` gives it git's `union` merge, so two branches that each added comments merge without a conflict.

### Open in the editor

"Open" is a link to the editor's own URL scheme, at the file's first changed line. By default that is VS Code (`vscode://file/…`). When the server runs under WSL the link names the distro (`vscode://vscode-remote/wsl+Ubuntu/…`, from `WSL_DISTRO_NAME`), because a Windows browser cannot open a Linux path as a local file. The browser asks once whether it may open the editor.

## How live reload works

There is no file watcher and no WebSocket. Every `poll_interval` seconds the page asks `GET /fingerprint` for a digest of the diff (one `git diff` and one `git ls-files`). When it is not the one the page was drawn from, the page posts the digest of every file it shows to `POST /refresh`, and the server answers with Turbo Streams for the difference only: the files that changed, came or went, and the counts. Two hundred files are not drawn again because one was saved. A hidden tab does not poll.

## Who can see it

The engine does not ask anyone to sign in: it inherits from `ActionController::Base`, not your `ApplicationController`. What keeps it private is `config.enabled`, which is true only in the development and test environments unless you set it. It shows the source of your working tree to whoever can reach it, so do not enable it on a server other people can reach.

## Claude Code skills

Copy them to `.claude/skills/` in the app.

- `skills/show-changes/SKILL.md` opens the page at the end of a session (`/show-changes`, or `/show-changes main`). Set its URL.
- `skills/explain-changes/SKILL.md` writes the comments (see Comments). The agent runs it by itself when it has finished changing code; a line in the app's `CLAUDE.md` makes that dependable.

## Development

```sh
bundle install
bundle exec rake test   # the engine mounted in a small host app, against a scratch repository
bundle exec rake css    # after changing a class in a view, a helper or the JavaScript
```

The page's stylesheet is built with Tailwind from `tailwind/git_diff_live.css` into `app/assets/builds/git_diff_live.css`, and the built file is what ships. It is committed: run `rake css` and commit the result whenever the classes change.

## License

MIT.
