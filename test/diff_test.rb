require "test_helper"

class DiffTest < ActiveSupport::TestCase

  include ScratchRepository

  setup do
    @root = build_scratch_repository
    @diff = GitDiffLive::Diff.new(root: @root)
  end

  teardown { remove_scratch_repository }

  test "lists every changed file by path with its status" do
    assert_equal(
      { "a_new_name.rb" => :renamed, "b_modified.rb" => :modified, "c_deleted.rb" => :deleted, "d_added.rb" => :added, "e_untracked.rb" => :added, "logo.png" => :modified },
      @diff.files.to_h { [ it.path, it.status ] }
    )
  end

  test "a renamed file knows its old path, and the files after it have none" do
    assert_equal "a_old_name.rb", @diff.file("a_new_name.rb").old_path

    assert_equal [ nil ], @diff.files.reject { it.path == "a_new_name.rb" }.map(&:old_path).uniq
  end

  test "a changed line is one row, removed on the left and added on the right" do
    file = @diff.file("b_modified.rb")
    row  = file.hunks.sole.rows.find { it.old.kind == :removed }

    assert_equal [ 1, 1 ], [ file.additions, file.deletions ]
    assert_equal [ 2, 2 ], [ row.old.number, row.new.number ]
    assert_equal :added, row.new.kind
    assert_equal "  price * quantity", row.old.segments.sum("") { it.first }
    assert_equal "  price * quantity * tax", row.new.segments.sum("") { it.first }
  end

  test "only the words that differ between the paired lines are marked" do
    row = @diff.file("b_modified.rb").hunks.sole.rows.find { it.old.kind == :removed }

    assert_empty row.old.segments.select(&:last)
    assert_equal [ " * tax" ], row.new.segments.select(&:last).map(&:first)
  end

  test "unchanged lines around a change are context rows numbered on both sides" do
    rows = @diff.file("b_modified.rb").hunks.sole.rows

    assert_equal [ :context, :removed, :context ], rows.map { it.old.kind }
    assert_equal [ 1, 2, 3 ], rows.map { it.new.number }
  end

  test "keeps three lines of context by default and the whole file on request" do
    assert_equal (7..13).to_a, @diff.file("a_new_name.rb").hunks.sole.rows.map { it.new.number }

    whole = GitDiffLive::Diff.new(root: @root, context: GitDiffLive::Diff::WHOLE_FILE).file("a_new_name.rb")

    assert_equal (1..20).to_a, whole.hunks.sole.rows.map { it.new.number }
    assert_equal [ 1, 1 ], [ whole.additions, whole.deletions ]
  end

  test "the first changed line is where an editor should open the file" do
    assert_equal 10, @diff.file("a_new_name.rb").first_changed_line
    assert_equal 2, @diff.file("b_modified.rb").first_changed_line
    assert_equal 1, @diff.file("e_untracked.rb").first_changed_line
    assert_equal 1, @diff.file("logo.png").first_changed_line
  end

  test "the first changed line of a removal is the line after the one above it" do
    scratch_write "b_modified.rb", "def total\nend\n"

    assert_equal 2, GitDiffLive::Diff.new(root: @root).file("b_modified.rb").first_changed_line
  end

  test "whole: the file again with every unchanged line, standing in for the one it was asked with" do
    file  = @diff.file("a_new_name.rb")
    whole = @diff.whole(file)

    assert_not file.whole?
    assert whole.whole?
    assert_equal (1..20).to_a, whole.hunks.sole.rows.map { it.new.number }
    assert_equal file.digest, whole.digest
    assert_equal [ 1, 1 ], [ whole.additions, whole.deletions ]
  end

  test "the digest of a file holds until that file changes, whatever else does" do
    before = @diff.files.to_h { [ it.path, it.digest ] }

    scratch_write "b_modified.rb", "def total\n  0\nend\n"
    scratch_write "e_untracked.rb", "first\nsecond\nthird\n"

    after   = GitDiffLive::Diff.new(root: @root).files.to_h { [ it.path, it.digest ] }
    changed = after.keys.reject { before[it] == after[it] }

    assert_equal [ "b_modified.rb", "e_untracked.rb" ], changed
    assert_equal 6, before.values.uniq.size
  end

  test "the counts are the rows': counted off the patch, not the parsed file" do
    @diff.files.each do | file |
      assert_equal file.hunks.sum { | hunk | hunk.rows.count { it.new&.kind == :added } }, file.additions, file.path
      assert_equal file.hunks.sum { | hunk | hunk.rows.count { it.old&.kind == :removed } }, file.deletions, file.path
    end
  end

  test "counts a removed line that begins with dashes and an added one that begins with pluses" do
    scratch_write "b_modified.rb", "def total\n  price * quantity\nend\n"
    scratch_commit "back to the start"
    scratch_write "b_modified.rb", "-- def total\n++ price * quantity\nend\n"

    file = GitDiffLive::Diff.new(root: @root).file("b_modified.rb")

    assert_equal [ 2, 2 ], [ file.additions, file.deletions ]
  end

  test "the fingerprint holds while nothing changes" do
    assert_equal @diff.fingerprint, GitDiffLive::Diff.new(root: @root).fingerprint
  end

  test "the fingerprint changes with a tracked file, an untracked file, and the base" do
    before = @diff.fingerprint

    scratch_write "b_modified.rb", "def total\n  price * quantity * tax * 2\nend\n"
    tracked = GitDiffLive::Diff.new(root: @root).fingerprint

    scratch_write "e_untracked.rb", "first\nsecond\nthird\n"
    untracked = GitDiffLive::Diff.new(root: @root).fingerprint

    scratch_commit "the session's work"
    committed = GitDiffLive::Diff.new(root: @root).fingerprint

    assert_equal 4, [ before, tracked, untracked, committed ].uniq.size
  end

  test "a deleted file has only a left side" do
    file = @diff.file("c_deleted.rb")
    rows = file.hunks.sole.rows

    assert_equal [ 0, 1 ], [ file.additions, file.deletions ]
    assert_equal [ "gone" ], rows.map { it.old.segments.sole.first }
    assert_equal [ nil ], rows.map(&:new)
  end

  test "an added file has only a right side" do
    file = @diff.file("d_added.rb")

    assert_not file.untracked?
    assert_equal [ nil ], file.hunks.sole.rows.map(&:old)
    assert_equal [ 1, 0 ], [ file.additions, file.deletions ]
  end

  test "an untracked file is listed as added, with its lines" do
    file = @diff.file("e_untracked.rb")

    assert file.untracked?
    assert_equal :added, file.status
    assert_equal [ [ 1, "first" ], [ 2, "second" ] ], file.hunks.sole.rows.map { [ it.new.number, it.new.segments.sole.first ] }
  end

  test "a binary file is listed without rows" do
    file = @diff.file("logo.png")

    assert file.binary?
    assert_empty file.hunks
  end

  test "an untracked binary file is listed without rows" do
    scratch_write "f_untracked.png", "\x89PNG\0\0new".b

    file = GitDiffLive::Diff.new(root: @root).file("f_untracked.png")

    assert file.binary?
    assert_empty file.hunks
  end

  test "a file moved without a change has no rows" do
    scratch_git "checkout", "--quiet", "HEAD", "--", "b_modified.rb"
    scratch_git "mv", "b_modified.rb", "b_moved.rb"

    file = GitDiffLive::Diff.new(root: @root).file("b_moved.rb")

    assert_equal :renamed, file.status
    assert file.unchanged_content?
  end

  test "compares with an earlier commit, so committed work still shows" do
    scratch_commit "the session's work"

    assert_empty GitDiffLive::Diff.new(root: @root).files
    assert_equal 6, GitDiffLive::Diff.new(root: @root, base: "HEAD~1").files.size
  end

  test "resolves the base to its commit" do
    assert_equal scratch_git("rev-parse", "HEAD").strip, @diff.base_sha
    assert_equal "main", @diff.branch
  end

  test "refuses a base that does not name a commit" do
    assert_raises(GitDiffLive::Diff::UnknownRevision) { GitDiffLive::Diff.new(root: @root, base: "no-such-branch").files }
  end

  test "refuses a base that reads as an option" do
    assert_raises(GitDiffLive::Diff::UnknownRevision) { GitDiffLive::Diff.new(root: @root, base: "--output=#{ @root.join("leak") }").files }
    assert_raises(GitDiffLive::Diff::UnknownRevision) { GitDiffLive::Diff.new(root: @root, base: "HEAD --stat").files }

    assert_not @root.join("leak").exist?
  end

  test "an unknown path finds no file" do
    assert_nil @diff.file("nope.rb")
  end

  test "segments: marks an inserted argument and leaves the other line unmarked" do
    old_segments, new_segments = GitDiffLive::Diff.segments("  foo(bar, baz)", "  foo(bar, qux, baz)")

    assert_equal [ [ "  foo(bar, baz)", false ] ], old_segments
    assert_equal [ [ "  foo(bar, ", false ], [ "qux, ", true ], [ "baz)", false ] ], new_segments
  end

  test "segments: marks a renamed word on both lines" do
    old_segments, new_segments = GitDiffLive::Diff.segments("belongs_to :certified_inventory, optional: true", "belongs_to :inventory, optional: true")

    assert_equal [ "certified_inventory" ], old_segments.select(&:last).map(&:first)
    assert_equal [ "inventory" ], new_segments.select(&:last).map(&:first)
  end

  test "segments: lines with little in common are left unmarked" do
    old_segments, new_segments = GitDiffLive::Diff.segments("completely different", "nothing shared at all here")

    assert_equal [ [ "completely different", false ] ], old_segments
    assert_equal [ [ "nothing shared at all here", false ] ], new_segments
  end

end
