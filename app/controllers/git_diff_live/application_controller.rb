module GitDiffLive

  # Base controller of the engine. It inherits from ActionController::Base, not
  # the host's ApplicationController, so the host's sign-in and callbacks do
  # not apply: nobody signs in to read a diff of their own working tree.
  #
  # What keeps the page private is that it only answers where it is enabled
  # (Configuration#enabled?: the development and test environments unless the
  # host says otherwise). A mount that reaches production by mistake serves
  # nothing but 404s.
  class ApplicationController < ActionController::Base

    layout "git_diff_live/application"

    protect_from_forgery with: :exception

    before_action :refuse_unless_enabled

    private

    def refuse_unless_enabled
      raise ActionController::RoutingError, "Not Found" unless GitDiffLive.configuration.enabled?
    end

  end

end
