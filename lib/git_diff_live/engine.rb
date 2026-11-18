# Gems a host app's Bundler.require does not load for us: they are this gem's
# dependencies, not lines of the host's Gemfile.
require "fontawesome_subsetter"
require "importmap-rails"
require "slim"
require "stimulus-rails"
require "turbo-rails"

module GitDiffLive

  # The mountable engine. It brings its own layout, stylesheet (prebuilt, in
  # app/assets/builds) and import map, so the host only mounts it:
  #
  #   mount GitDiffLive::Engine => "/changes" if Rails.env.development?
  #
  # The one thing it takes from the host is the Font Awesome icon font, through
  # fontawesome_subsetter.
  class Engine < ::Rails::Engine

    isolate_namespace GitDiffLive

    # The page's JavaScript is served as it is written, through the host's
    # asset pipeline. (app/assets/builds is on the asset paths already, as
    # every engine's app/assets/* is.)
    initializer "git_diff_live.assets" do | app |
      app.config.assets.paths << root.join("app/javascript") if app.config.respond_to?(:assets)
    end

    initializer "git_diff_live.importmap" do
      GitDiffLive.importmap.draw root.join("config/importmap.rb")
    end

    # fontawesome_subsetter builds the icon font from the icon(:fas, :name)
    # calls it finds in the host's views; these are the engine's, so its icons
    # are in the font too. After the host's initializers, in case one of them
    # sets scan_globs.
    initializer "git_diff_live.icons" do | app |
      app.config.after_initialize do
        FontawesomeSubsetter.configuration.scan_globs |= [ root.join("app/views/**/*.slim").to_s, root.join("app/helpers/**/*.rb").to_s ]
      end
    end

  end

end
