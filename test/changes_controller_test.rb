require "test_helper"

# The engine mounted at /changes in the dummy app (test_helper), reading a
# scratch repository.
class ChangesControllerTest < ActionDispatch::IntegrationTest

  include ScratchRepository

  setup do
    @root = build_scratch_repository
    @configuration = GitDiffLive.configuration
    GitDiffLive.configuration = GitDiffLive::Configuration.new.tap { it.root = @root }
  end

  teardown do
    GitDiffLive.configuration = @configuration
    remove_scratch_repository
  end

  test "smoke: the page lists every changed file" do
    get "/changes"

    assert_response :success
    assert_select "details", 6
    assert_select "nav a", 6
    assert_select "summary", text: /a_old_name\.rb.*a_new_name\.rb/m
  end

  test "the page links the host's icon font, its own stylesheet and its own import map" do
    get "/changes"

    assert_select "link[rel=stylesheet][href*='fontawesome']"
    assert_select "link[rel=stylesheet][href*='git_diff_live']"
    assert_select "script[type=importmap]", text: /git_diff_live\/application.*turbo\.min.*stimulus\.min.*changes_controller/m
    assert_select "i.fas.fa-code-compare"
  end

  test "the stylesheets it serves are there" do
    get "/changes"

    css_select("link[rel=stylesheet], link[rel=modulepreload]").each do | link |
      get link["href"]

      assert_response :success, link["href"]
    end
  end

  test "a changed line is drawn on both sides, the difference marked" do
    get "/changes"

    assert_select "details##{ changed_file("b_modified.rb").dom_id }" do
      assert_select "div.bg-red-950\\/50", text: "price * quantity"
      assert_select "div.bg-emerald-950\\/50", text: "price * quantity * tax"
      assert_select "div.bg-emerald-950\\/50 span.bg-emerald-800", text: "* tax"
    end

    # assert_select compares stripped text; the indentation has to reach the page as written.
    assert_includes response.body, ">  price * quantity</div>"
  end

  test "a deleted file starts closed and the others open" do
    get "/changes"

    assert_select "details##{ changed_file("c_deleted.rb").dom_id }:not([open])"
    assert_select "details[open]", 5
  end

  test "file: the whole file replaces the file's section as a turbo stream" do
    file = changed_file("a_new_name.rb")

    get "/changes/file", params: { path: file.path, whole: 1 }, as: :turbo_stream

    assert_response :success
    assert_equal "text/vnd.turbo-stream.html", response.media_type
    assert_select "turbo-stream[action=replace][target=#{ file.dom_id }]" do
      assert_select "template details[open][data-whole=true][data-digest=?]", file.digest
      assert_select "template summary a[data-turbo-stream][href=?]", "/changes/file?path=a_new_name.rb", text: /Changes only/
      # Twenty lines on each side: number and text, 80 cells.
      assert_select "template .grid > div", 80
    end
  end

  test "file: without whole, only the lines around the change come back" do
    file = changed_file("a_new_name.rb")

    get "/changes/file", params: { path: file.path }, as: :turbo_stream

    assert_response :success
    assert_select "template details:not([data-whole])"
    assert_select "template summary a[href=?]", "/changes/file?path=a_new_name.rb&whole=1", text: /Whole file/
    # The hunk heading, then lines 7 to 13: seven rows of four cells.
    assert_select "template .grid > div", 29
  end

  test "file: an unknown path, or one outside the changes, is not found" do
    get "/changes/file", params: { path: "nope.rb" }, as: :turbo_stream
    assert_response :not_found

    get "/changes/file", params: { path: "../../etc/passwd" }, as: :turbo_stream
    assert_response :not_found
  end

  test "only a file with both sides offers its whole file" do
    get "/changes"

    assert_select "summary a", text: /Whole file/, count: 2
  end

  test "every file still on disk opens in the editor at its first change" do
    get "/changes"

    assert_select "summary a[href^='vscode://']", text: /Open/, count: 5
    assert_select "details##{ changed_file("c_deleted.rb").dom_id } summary a[href^='vscode://']", 0
    assert_select "details##{ changed_file("a_new_name.rb").dom_id } summary a[href$=?]", "#{ @root }/a_new_name.rb:10"
  end

  test "the editor link reaches the WSL window when the server runs under WSL, a local file otherwise" do
    distro = ENV["WSL_DISTRO_NAME"]

    ENV["WSL_DISTRO_NAME"] = "Ubuntu-24.04"
    get "/changes"
    assert_select "a[href=?]", "vscode://vscode-remote/wsl+Ubuntu-24.04#{ @root }/b_modified.rb:2"

    ENV.delete("WSL_DISTRO_NAME")
    get "/changes"
    assert_select "a[href=?]", "vscode://file#{ @root }/b_modified.rb:2"
  ensure
    ENV["WSL_DISTRO_NAME"] = distro
  end

  test "the editor link follows the configured editor" do
    GitDiffLive.configuration.editor_url = "cursor://file%{path}:%{line}"

    get "/changes"

    assert_select "a[href=?]", "cursor://file#{ @root }/b_modified.rb:2"
  end

  test "compares with the commit asked for and keeps it on the page's links" do
    scratch_commit "the session's work"

    get "/changes"
    assert_select "details", 0
    assert_match "Nothing has changed", response.body

    get "/changes", params: { base: "HEAD~1" }
    assert_select "details", 6
    assert_select "summary a[href*='base=HEAD~1']", text: /Whole file/
    assert_select "[data-changes-fingerprint-url-value=?]", "/changes/fingerprint?base=HEAD~1"
    assert_select "[data-changes-refresh-url-value=?]", "/changes/refresh?base=HEAD~1"
  end

  test "an unknown base is not found" do
    get "/changes", params: { base: "no-such-branch" }

    assert_response :not_found
    assert_match "does not name a commit", response.body
  end

  test "a base that reads as an option is refused" do
    get "/changes", params: { base: "--output=/tmp/leak" }

    assert_response :not_found
    assert_match "is not a revision", response.body
  end

  test "live: the page carries the fingerprint it was drawn from, where to ask for the next, and each file's digest" do
    get "/changes"

    assert_select "#changes_summary[data-changes-target=summary][data-fingerprint=?]", GitDiffLive::Diff.new(root: @root).fingerprint
    assert_select "[data-controller=changes][data-changes-fingerprint-url-value=?]", "/changes/fingerprint"
    assert_select "[data-changes-refresh-url-value=?]", "/changes/refresh"
    assert_select "[data-changes-interval-value=?]", "2000"
    assert_select "[data-changes-target=status]", text: /Live/
    assert_select "details[data-changes-target=file][data-path='b_modified.rb'][data-digest=?]", changed_file("b_modified.rb").digest
    assert_select "#changes_empty.hidden"
  end

  test "live: the fingerprint answers the page's own, until the tree changes" do
    get "/changes"
    drawn = css_select("#changes_summary").first["data-fingerprint"]

    get "/changes/fingerprint"
    assert_response :success
    assert_equal drawn, response.body

    scratch_write "b_modified.rb", "def total\n  0\nend\n"

    get "/changes/fingerprint"
    assert_not_equal drawn, response.body
  end

  test "refresh: a page that holds everything is sent no file, only the counts and the list" do
    post "/changes/refresh", params: held, as: :turbo_stream

    assert_response :success
    assert_equal "text/vnd.turbo-stream.html", response.media_type
    assert_select "template details", 0
    assert_select "turbo-stream[action=replace][method=morph][target=changes_summary] template [data-fingerprint=?]", GitDiffLive::Diff.new(root: @root).fingerprint
    assert_select "turbo-stream[action=replace][method=morph][target=changes_nav] template a", 6
    assert_select "turbo-stream[action=replace][target=changes_empty] template .hidden"
  end

  test "refresh: only the file that changed is drawn again, morphed in place" do
    page = held

    scratch_write "b_modified.rb", "def total\n  0\nend\n"
    post "/changes/refresh", params: page, as: :turbo_stream

    assert_select "template details", 1
    assert_select "turbo-stream[action=replace][method=morph][target=#{ changed_file("b_modified.rb").dom_id }] template details[data-digest=?]", changed_file("b_modified.rb").digest
    assert_not_equal page[:digests][page[:paths].index("b_modified.rb")], changed_file("b_modified.rb").digest
  end

  test "refresh: a file drawn whole comes back whole, a large one shown comes back shown" do
    page = held.merge(whole: [ "a_new_name.rb" ], shown: [ "b_modified.rb" ])

    scratch_write "a_new_name.rb", (1..20).map { "line #{ it == 10 ? "TEN" : it }\n" }.join
    scratch_write "b_modified.rb", "def total\n  0\nend\n"
    post "/changes/refresh", params: page, as: :turbo_stream

    assert_select "turbo-stream[target=#{ changed_file("a_new_name.rb").dom_id }] template details[data-whole=true] .grid > div", 80
    assert_select "turbo-stream[target=#{ changed_file("b_modified.rb").dom_id }] template details[data-shown=true]:not([data-whole])"
  end

  test "refresh: a new file goes in front of the file after it, the last one at the end" do
    page = held

    scratch_write "b_between.rb", "new\n"
    scratch_write "z_last.rb", "new\n"
    post "/changes/refresh", params: page, as: :turbo_stream

    assert_select "turbo-stream[action=before][target=#{ changed_file("b_modified.rb").dom_id }] template details[data-path='b_between.rb']"
    assert_select "turbo-stream[action=append][target=changed_files] template details[data-path='z_last.rb']"
    assert_select "turbo-stream[target=changes_nav] template a", 8
  end

  test "refresh: two new files in a row each go in front of the one after" do
    page = held

    scratch_write "y_first.rb", "new\n"
    scratch_write "z_second.rb", "new\n"
    post "/changes/refresh", params: page, as: :turbo_stream

    streams = css_select("turbo-stream").map { [ it["action"], it["target"] ] }

    # z goes on the end first, so it is there for y to go in front of.
    assert_operator streams.index([ "append", "changed_files" ]), :<, streams.index([ "before", GitDiffLive::Diff::ChangedFile.dom_id("z_second.rb") ])
  end

  test "refresh: a file no longer changed is removed, and the last one leaves the empty message" do
    page = held

    scratch_commit "the session's work"
    post "/changes/refresh", params: page, as: :turbo_stream

    assert_select "turbo-stream[action=remove]", 6
    assert_select "turbo-stream[action=remove][target=#{ GitDiffLive::Diff::ChangedFile.dom_id("b_modified.rb") }]"
    assert_select "turbo-stream[target=changes_empty] template :not(.hidden)", text: /Nothing has changed/
    assert_select "template details", 0
  end

  test "refresh: a page that holds nothing is sent everything" do
    post "/changes/refresh", as: :turbo_stream

    assert_select "template details", 6
  end

  test "refresh: keeps to the commit asked for" do
    scratch_commit "the session's work"

    post "/changes/refresh?base=HEAD~1", as: :turbo_stream

    assert_select "template details", 6
    assert_select "turbo-stream[target=changes_summary] template", text: /HEAD~1/
  end

  test "live: no interval, no polling and no marker" do
    GitDiffLive.configuration.poll_interval = nil

    get "/changes"

    assert_select "[data-changes-interval-value=?]", "0"
    assert_select "[data-changes-target=status]", 0
  end

  test "answers nothing where it is not enabled" do
    GitDiffLive.configuration.enabled = false

    get "/changes"
    assert_response :not_found

    get "/changes/fingerprint"
    assert_response :not_found

    post "/changes/refresh", as: :turbo_stream
    assert_response :not_found
  end

  test "is enabled in development and test, and nowhere else unless told" do
    configuration = GitDiffLive::Configuration.new

    environment = Rails.env

    assert configuration.enabled?

    Rails.env = "production"
    assert_not configuration.enabled?

    configuration.enabled = true
    assert configuration.enabled?
  ensure
    Rails.env = environment
  end

  private

  # What a page that has just been drawn holds: every file's path and digest, in step.
  def held
    files = GitDiffLive::Diff.new(root: @root).files

    { paths: files.map(&:path), digests: files.map(&:digest) }
  end

  def changed_file(path)
    GitDiffLive::Diff.new(root: @root).file(path)
  end

end
