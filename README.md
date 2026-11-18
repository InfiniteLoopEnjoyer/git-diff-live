# git_diff_live

A live, side-by-side page of your working tree's git changes, for Rails apps in development. Made for reading a session's work before committing it.

- Every changed file on one page: before on the left, after on the right, removed in red, added in green, and the words that changed marked inside each line.
- Staged, unstaged and untracked work together. Renames shown as `old → new`.
- **Live**: the page redraws what changes as you (or an agent) edit, without losing your place.
- "Whole file" per file, "Compare with" any revision (`main`, `HEAD~3`, a SHA), and "Open" to jump to the file in your editor.

It is a mountable Rails engine with its own layout, stylesheet and JavaScript. Nothing is added to your app's pages, Tailwind build or import map.

## Requirements

- Rails 7.1 or newer with Propshaft, and `git` on the `PATH`.
- [fontawesome_subsetter](https://github.com/optimuspwnius/fontawesome-subsetter) set up in the host app (Font Awesome in `vendor/fontawesome`). The page's icons come from the host's icon font; the engine registers its own views with the subsetter so they are in the build.

Turbo, Stimulus, importmap-rails and Slim come along as dependencies. The host does not have to use them itself.

## Installation

```ruby
# Gemfile
group :development do
  gem "git_diff_live", github: "InfiniteLoopEnjoyer/git-diff-live"
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

A deleted file starts collapsed. A file with more than 1,500 changed lines is drawn when you ask for it.

### Open in the editor

"Open" is a link to the editor's own URL scheme, at the file's first changed line. By default that is VS Code (`vscode://file/…`). When the server runs under WSL the link names the distro (`vscode://vscode-remote/wsl+Ubuntu/…`, from `WSL_DISTRO_NAME`), because a Windows browser cannot open a Linux path as a local file. The browser asks once whether it may open the editor.

## How live reload works

There is no file watcher and no WebSocket. Every `poll_interval` seconds the page asks `GET /fingerprint` for a digest of the diff (one `git diff` and one `git ls-files`). When it is not the one the page was drawn from, the page posts the digest of every file it shows to `POST /refresh`, and the server answers with Turbo Streams for the difference only: the files that changed, came or went, and the counts. Two hundred files are not drawn again because one was saved. A hidden tab does not poll.

## Who can see it

The engine does not ask anyone to sign in: it inherits from `ActionController::Base`, not your `ApplicationController`. What keeps it private is `config.enabled`, which is true only in the development and test environments unless you set it. It shows the source of your working tree to whoever can reach it, so do not enable it on a server other people can reach.

## Claude Code skill

`skills/show-changes/SKILL.md` is a skill that opens the page at the end of a session (`/show-changes`, or `/show-changes main`). Copy it to `.claude/skills/show-changes/` in the app and set its URL.

## Development

```sh
bundle install
bundle exec rake test   # the engine mounted in a small host app, against a scratch repository
bundle exec rake css    # after changing a class in a view, a helper or the JavaScript
```

The page's stylesheet is built with Tailwind from `tailwind/git_diff_live.css` into `app/assets/builds/git_diff_live.css`, and the built file is what ships. It is committed: run `rake css` and commit the result whenever the classes change.

## License

MIT.
