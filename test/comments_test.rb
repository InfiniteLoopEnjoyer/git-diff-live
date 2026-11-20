require "test_helper"

# Comments written beside the scratch repository's changes: where they are
# kept, which a comparison shows, and where each one goes.
class CommentsTest < ActiveSupport::TestCase

  include ScratchRepository

  setup { @root = build_scratch_repository }

  teardown { remove_scratch_repository }

  test "write: a comment is one line of the store, anchored to the changed line's text" do
    result = write [ "b_modified.rb", :new, 2, "Tax is part\n  of the total now." ]

    assert_empty result.rejected
    assert_equal(
      [ { "path" => "b_modified.rb", "side" => "new", "line" => 2, "code" => "  price * quantity * tax", "comment" => "Tax is part of the total now." } ],
      store_lines.map { JSON.parse(it) }
    )
    assert_equal "comments.jsonl merge=union\n", @root.join(".git_diff_live/.gitattributes").read
  end

  test "write: a removed line is named on the old side" do
    write [ "c_deleted.rb", :old, 1, "Nothing reads this file any more." ]

    assert_equal [ [ :old, 1 ] ], comparison.file("c_deleted.rb").placed_comments.keys
  end

  test "write: a line that is not a changed one is refused, with the nearest that are" do
    result = write [ "a_new_name.rb", :new, 9, "Nine did not change." ], [ "nope.rb", :new, 1, "No such file." ], [ "b_modified.rb", :new, 2, " " ]

    assert_empty result.written
    assert_equal(
      [
        [ "a_new_name.rb:+9", "+9 is not an added line; the nearest are +10" ],
        [ "nope.rb:+1", "nope.rb is not a changed file" ],
        [ "b_modified.rb:+2", "the comment is empty" ]
      ],
      result.rejected
    )
    assert_not @root.join(".git_diff_live").exist?
  end

  test "write: a second comment on the same line takes the first one's place" do
    write [ "b_modified.rb", :new, 2, "First thought." ]
    write [ "b_modified.rb", :new, 2, "Second thought." ]

    assert_equal [ "Second thought." ], comparison.comments.map(&:body)
    assert_equal 1, store_lines.size
  end

  test "write: a comment whose code changed again is taken out, a committed one is kept" do
    write [ "b_modified.rb", :new, 2, "Committed with its change." ]
    scratch_commit "the session's work"

    scratch_write "b_modified.rb", "def total\n  1\nend\n"
    write [ "b_modified.rb", :new, 2, "About the one." ]
    scratch_write "b_modified.rb", "def total\n  2\nend\n"
    result = write [ "b_modified.rb", :new, 2, "About the two." ]

    assert_equal 1, result.removed
    assert_equal [ "Committed with its change.", "About the two." ], store_lines.map { JSON.parse(it)["comment"] }
  end

  test "the store is not one of the changed files, and its comments are on their own files" do
    write [ "b_modified.rb", :new, 2, "Tax is part of the total now." ], [ "e_untracked.rb", :new, 1, "A new file." ]

    assert_equal 6, comparison.files.size
    assert_equal [ "Tax is part of the total now." ], comparison.file("b_modified.rb").comments.map(&:body)
    assert_equal [ "A new file." ], comparison.file("e_untracked.rb").comments.map(&:body)
    assert_empty comparison.file("d_added.rb").comments
  end

  test "a comment follows its line when lines above it come and go" do
    write [ "a_new_name.rb", :new, 10, "Ten is spelled out." ]

    scratch_write "a_new_name.rb", "zero\n#{ (1..20).map { "line #{ it == 10 ? "ten" : it }\n" }.join }"

    assert_equal({ [ :new, 11 ] => [ "Ten is spelled out." ] }, comparison.file("a_new_name.rb").placed_comments.transform_values { it.map(&:body) })
  end

  test "of two changed lines with the same text, a comment goes beside the nearer one" do
    scratch_write "e_untracked.rb", "same\nother\nsame\n"
    write [ "e_untracked.rb", :new, 3, "The second of the two." ]

    assert_equal [ [ :new, 3 ] ], comparison.file("e_untracked.rb").placed_comments.keys
  end

  test "a comment whose line changed again has no place, and its file is drawn without it" do
    write [ "b_modified.rb", :new, 2, "Tax is part of the total now." ]

    scratch_write "b_modified.rb", "def total\n  0\nend\n"

    assert_equal 1, comparison.file("b_modified.rb").comments.size
    assert_empty comparison.file("b_modified.rb").placed_comments
  end

  test "a renamed file keeps the comments written under its old name" do
    scratch_commit "the session's work"
    scratch_write "a_new_name.rb", (1..20).map { "line #{ it == 5 ? "five" : it }\n" }.join
    write [ "a_new_name.rb", :new, 5, "Five is spelled out." ]
    scratch_git "add", "a_new_name.rb"
    scratch_git "mv", "a_new_name.rb", "a_newer_name.rb"

    assert_equal "a_new_name.rb", comparison.comments.sole.path
    assert_equal [ [ :new, 5 ] ], comparison.file("a_newer_name.rb").placed_comments.keys
  end

  test "a comment changes its file's digest and the fingerprint, and no other file's" do
    before, fingerprint = comparison.files.to_h { [ it.path, it.digest ] }, comparison.fingerprint

    write [ "b_modified.rb", :new, 2, "Tax is part of the total now." ]

    after = comparison.files.to_h { [ it.path, it.digest ] }

    assert_equal [ "b_modified.rb" ], after.keys.reject { before[it] == after[it] }
    assert_not_equal fingerprint, comparison.fingerprint
  end

  test "a comparison shows the comments written within it, and no others" do
    write [ "b_modified.rb", :new, 2, "The first commit's." ]
    scratch_commit "first"
    scratch_write "b_modified.rb", "def total\n  price * quantity * tax\nend\n\ndef later\nend\n"
    write [ "b_modified.rb", :new, 5, "The second commit's." ]
    scratch_commit "second"

    assert_equal [ "The first commit's." ], comparison(base: "HEAD~2", head: "HEAD~1").comments.map(&:body)
    assert_equal [ "The second commit's." ], comparison(base: "HEAD~1", head: "HEAD").comments.map(&:body)
    assert_equal [ "The first commit's.", "The second commit's." ], comparison(base: "HEAD~2").comments.map(&:body)
    assert_empty comparison.comments
  end

  test "a line of the store that is not a comment is passed over" do
    write [ "b_modified.rb", :new, 2, "Tax is part of the total now." ]
    @root.join(GitDiffLive::Comments::PATH).write("<<<<<<< HEAD\n{\"path\":1}\n[]\n", mode: "a")

    assert_equal [ "Tax is part of the total now." ], comparison.comments.map(&:body)
  end

  private

  def comparison(**options)
    GitDiffLive::Diff.new(root: @root, **options)
  end

  def write(*notes)
    GitDiffLive::Comments.new(root: @root).write(notes)
  end

  def store_lines
    @root.join(GitDiffLive::Comments::PATH).readlines(chomp: true)
  end

end
