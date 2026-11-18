require "test_helper"

class VersionTest < ActiveSupport::TestCase

  test "has a version" do
    assert_match(/\A\d+\.\d+\.\d+\z/, GitDiffLive::VERSION)
  end

end
