require_relative "lib/git_diff_live/version"

Gem::Specification.new do | spec |
  spec.name          = "git_diff_live"
  spec.version       = GitDiffLive::VERSION
  spec.authors       = [ "Tayden Miller" ]

  spec.summary       = "A live, side-by-side page of your working tree's git changes, for Rails apps in development."
  spec.description   = "A mountable Rails engine that draws every file changed in the working tree against a commit, " \
                        "old on the left and new on the right, and redraws itself as you edit. Made for reading a " \
                        "session's work before committing it."
  spec.homepage      = "https://github.com/InfiniteLoopEnjoyer/git-diff-live"
  spec.license       = "MIT"
  spec.metadata["homepage_uri"]    = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"]   = "#{ spec.homepage }/blob/main/CHANGELOG.md"
  spec.required_ruby_version = ">= 3.4"

  spec.files = Dir[
    "app/**/*",
    "config/**/*",
    "lib/**/*",
    "CHANGELOG.md",
    "LICENSE.txt",
    "README.md"
  ]

  spec.require_paths = [ "lib" ]

  spec.add_dependency "railties", ">= 7.1"
  spec.add_dependency "actionpack", ">= 7.1"
  spec.add_dependency "fontawesome_subsetter", ">= 0.1.9"
  spec.add_dependency "importmap-rails", ">= 2.0"
  spec.add_dependency "slim", ">= 5.0"
  spec.add_dependency "stimulus-rails", ">= 1.3"
  spec.add_dependency "turbo-rails", ">= 2.0"
end
