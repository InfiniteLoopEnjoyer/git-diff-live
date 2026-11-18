ENV["RAILS_ENV"] = "test"

require "minitest/autorun"
require "fileutils"
require "logger"
require "tmpdir"

require "rails"
require "action_controller/railtie"
require "action_view/railtie"
require "propshaft"
require "git_diff_live"

require_relative "support/scratch_repository"

# The smallest host app that can mount the engine: no database, no host
# layout, and an empty fontawesome.css standing in for the icon font the
# host would build (test/dummy/app/assets/builds).
class Dummy < Rails::Application

  config.root = File.expand_path("dummy", __dir__)
  config.eager_load = false
  config.secret_key_base = "test"
  config.hosts.clear
  config.logger = Logger.new(nil)
  config.action_controller.allow_forgery_protection = false

  routes.append do
    mount GitDiffLive::Engine => "/changes"
  end

end

Dummy.initialize!

require "rails/test_help"
