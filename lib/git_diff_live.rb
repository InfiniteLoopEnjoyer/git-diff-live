require_relative "git_diff_live/version"
require_relative "git_diff_live/diff"
require_relative "git_diff_live/comments"

# A live, side-by-side page of the working tree's git changes, as a mountable
# Rails engine.
#
# == Quick Start
#
#   # Gemfile
#   gem "git_diff_live", group: :development
#
#   # config/routes.rb
#   mount GitDiffLive::Engine => "/changes" if Rails.env.development?
#
# See Configuration for the options, and Comments for the comments drawn
# beside the changes.
module GitDiffLive

  class << self

    attr_writer :configuration

    # Returns the current configuration, initializing with defaults if needed.
    def configuration
      @configuration ||= Configuration.new
    end

    # Yields the current Configuration for modification.
    #
    #   GitDiffLive.configure do | config |
    #     config.poll_interval = 5
    #   end
    def configure
      yield(configuration)
    end

    # The engine's own import map (config/importmap.rb), kept apart from the
    # host's so the page loads the same JavaScript in every app.
    def importmap
      @importmap ||= Importmap::Map.new
    end

  end

  # Holds all configuration options.
  #
  # == Attributes
  #
  # [root]           The repository to show. Default: +Rails.root+.
  # [enabled]        Whether the page answers at all; anything else is a 404.
  #                  Default: only in the development and test environments.
  # [poll_interval]  Seconds between the page's checks for new changes. +nil+
  #                  or 0 turns live reload off. Default: 2.
  # [context]        Unchanged lines drawn around each change. Default: 3.
  # [stylesheets]    The host's stylesheets the page links before its own: the
  #                  icon font. Default: <tt>["fontawesome"]</tt>, the file
  #                  fontawesome_subsetter builds.
  # [editor_url]     Where a file's "Open" link goes, as a format string given
  #                  +path+ (absolute, URL-escaped) and +line+. Default: +nil+,
  #                  which opens VS Code, through its Remote - WSL window when
  #                  the server runs under WSL. For another editor:
  #                  <tt>"cursor://file%{path}:%{line}"</tt>.
  class Configuration

    attr_accessor :poll_interval, :context, :stylesheets, :editor_url

    attr_writer :root, :enabled

    def initialize
      @poll_interval = 2
      @context       = Diff::DEFAULT_CONTEXT
      @stylesheets   = [ "fontawesome" ]
    end

    def root
      @root || Rails.root
    end

    def enabled?
      @enabled.nil? ? Rails.env.local? : @enabled
    end

  end

end

require_relative "git_diff_live/engine" if defined?(Rails)
