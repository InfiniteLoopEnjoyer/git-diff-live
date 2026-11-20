require "test_helper"
require "git_diff_live/cli"
require "stringio"

# The command line an agent writes comments with, run in the scratch repository.
class CliTest < ActiveSupport::TestCase

  include ScratchRepository

  setup { @root = build_scratch_repository }

  teardown { remove_scratch_repository }

  test "changes: lists every change that has no comment, each changed line with its reference" do
    status, output = run_cli "changes"

    assert_equal 0, status
    assert_includes output, <<~TEXT
      b_modified.rb (modified)
        @@ -1,3 +1,3 @@
        -2    |   price * quantity
        +2    |   price * quantity * tax

    TEXT
    assert_includes output, "a_new_name.rb (renamed from a_old_name.rb)\n  @@ -7,7 +7,7 @@ line 6\n  -10   | line 10\n  +10   | line ten\n\n"
    assert_includes output, "c_deleted.rb (deleted)\n  @@ -1 +0,0 @@\n  -1    | gone\n\n"
    assert_includes output, "e_untracked.rb (added)\n  @@ -0,0 +1,2 @@\n  +1    | first\n  +2    | second\n\n"
    assert_includes output, "logo.png (modified)\n  Binary, no lines to comment on. Comment on the file: logo.png:file\n\n"
    assert_match(/^6 changes without a comment\.$/, output)
  end

  test "changes: a comment on the file is enough for a binary file, a moved one and a deleted one, not for an edited one" do
    scratch_git "checkout", "--quiet", "HEAD", "--", "b_modified.rb"
    scratch_git "mv", "b_modified.rb", "b_moved.rb"

    _, output = run_cli "changes"
    assert_includes output, "b_moved.rb (renamed from b_modified.rb)\n  Content unchanged, no lines to comment on. Comment on the file: b_moved.rb:file\n\n"

    status, = run_cli "comment", input: <<~TEXT
      logo.png:file The new logo.
      b_moved.rb:file Moved beside the code that calls it.
      c_deleted.rb:file Nothing reads this file any more.
      a_new_name.rb:file Renamed to match its class.
    TEXT
    assert_equal 0, status

    _, output = run_cli "changes"
    assert_not_includes output, "logo.png"
    assert_not_includes output, "b_moved.rb"
    assert_not_includes output, "c_deleted.rb"
    assert_includes output, "a_new_name.rb (renamed from a_old_name.rb)\n  file has: Renamed to match its class.\n  @@ -7,7 +7,7 @@ line 6\n"
    assert_match(/^3 changes without a comment\.$/, output)

    _, output = run_cli "changes", "--all", "c_deleted.rb"
    assert_includes output, "c_deleted.rb (deleted)\n  file has: Nothing reads this file any more.\n  @@ -1 +0,0 @@\n  -1    | gone\n"
  end

  test "changes: a hunk is one change, the unchanged lines between its runs shown without a reference" do
    scratch_write "a_new_name.rb", (1..20).map { "line #{ [ 10, 12 ].include?(it) ? "changed" : it }\n" }.join
    run_cli "comment", "a_new_name.rb:+12", "Twelve changed with ten."

    _, output = run_cli "changes", "--all", "a_new_name.rb"

    assert_includes output, "  -10   | line 10\n  +10   | line changed\n        | line 11\n  -12   | line 12\n  +12   | line changed\n  +12 has: Twelve changed with ten.\n"
    assert_match(/^Every change has a comment\.$/, output)
  end

  test "changes: a commented change is left out, and listed with its comment by --all" do
    run_cli "comment", "b_modified.rb:+2", "Tax is part of the total now."

    _, output = run_cli "changes"
    assert_not_includes output, "b_modified.rb"
    assert_match(/^5 changes without a comment\.$/, output)

    _, output = run_cli "changes", "--all"
    assert_includes output, "  +2    |   price * quantity * tax\n  +2 has: Tax is part of the total now.\n"
  end

  test "changes: narrowed to the paths given, and a long change is cut short unless --full" do
    scratch_write "e_untracked.rb", (1..20).map { "row #{ it }\n" }.join

    _, output = run_cli "changes", "e_untracked.rb"
    assert_not_includes output, "b_modified.rb"
    assert_includes output, "  +8    | row 8\n  ...    | 12 more, to +20\n"

    _, output = run_cli "changes", "--full", "e_untracked.rb"
    assert_includes output, "  +20   | row 20\n"

    scratch_write "e_untracked.rb", "#{ "x" * 200 }\n"
    _, output = run_cli "changes", "e_untracked.rb"
    assert_includes output, "  +1    | #{ "x" * 160 }...\n"
  end

  test "comment: writes every line of standard input, on either side" do
    status, output = run_cli "comment", input: <<~TEXT
      b_modified.rb:+2 Tax is part of the total now.

      c_deleted.rb:-1  Nothing reads this file any more.
    TEXT

    assert_equal 0, status
    assert_equal "2 comments written to .git_diff_live/comments.jsonl.\n", output
    assert_equal [ [ "b_modified.rb", :new, 2 ], [ "c_deleted.rb", :old, 1 ] ], comparison.comments.map { [ it.path, it.side, it.line ] }
  end

  test "comment: writes what it can and says what it could not" do
    status, output, error = run_cli "comment", input: "b_modified.rb:+2 Tax is part of the total now.\nb_modified.rb:+3 Not a change.\nb_modified.rb no line\n"

    assert_equal 1, status
    assert_equal "1 comment written to .git_diff_live/comments.jsonl.\n", output
    assert_includes error, "Not written: b_modified.rb:+3: +3 is not an added line; the nearest are +2\n"
    assert_includes error, "Not written: b_modified.rb: not a reference"

    status, _, error = run_cli "comment", "logo.png:+1", "The new logo."
    assert_equal 1, status
    assert_includes error, "Not written: logo.png:+1: +1 is not an added line; the file has none (logo.png:file comments on the file)\n"

    status, _, error = run_cli "comment", "nope.rb:file", "No such file."
    assert_equal 1, status
    assert_includes error, "Not written: nope.rb:file: nope.rb is not a changed file\n"
  end

  test "comment: against an earlier base, committed work is commented too" do
    scratch_commit "the session's work"

    status, = run_cli "comment", "--base", "HEAD~1", "b_modified.rb:+2", "Tax is part of the total now."

    assert_equal 0, status
    assert_equal [ [ :new, 2 ] ], comparison(base: "HEAD~1").file("b_modified.rb").placed_comments.keys
  end

  test "an unknown command prints the usage, an unknown base says so" do
    status, output = run_cli "nope"
    assert_equal 1, status
    assert_includes output, "Usage: git_diff_live changes"

    status, _, error = run_cli "changes", "--base", "no-such-branch"
    assert_equal 1, status
    assert_includes error, "does not name a commit"
  end

  private

  def run_cli(*arguments, input: "")
    output, error = StringIO.new, StringIO.new
    status = GitDiffLive::CLI.new(root: @root, input: StringIO.new(input), output: output, error: error).run(arguments)

    [ status, output.string, error.string ]
  end

  def comparison(**options)
    GitDiffLive::Diff.new(root: @root, **options)
  end

end
