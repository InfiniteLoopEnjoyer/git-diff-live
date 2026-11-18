# A throwaway git repository in a temp directory for the tests,
# so they never depend on what this repository's own working tree holds.
#
# build_scratch_repository commits four files, then leaves one change of every
# kind uncommitted:
#
#   a_old_name.rb -> a_new_name.rb   renamed (staged), line 10 edited
#   b_modified.rb                    one line edited
#   c_deleted.rb                     deleted
#   d_added.rb                       new, staged
#   e_untracked.rb                   new, untracked
#   logo.png                         binary, changed
#
# The rename sorts first on purpose: the files after it must not inherit its
# old path.
module ScratchRepository
  def build_scratch_repository
    @scratch_root = Pathname.new(Dir.mktmpdir("git_diff_live"))

    scratch_git "init", "--quiet", "--initial-branch=main"
    scratch_write "a_old_name.rb", (1..20).map { "line #{ it }\n" }.join
    scratch_write "b_modified.rb", "def total\n  price * quantity\nend\n"
    scratch_write "c_deleted.rb", "gone\n"
    scratch_write "logo.png", "\x89PNG\0\0first".b
    scratch_commit "base"

    scratch_git "mv", "a_old_name.rb", "a_new_name.rb"
    scratch_write "a_new_name.rb", (1..20).map { "line #{ it == 10 ? "ten" : it }\n" }.join
    scratch_write "b_modified.rb", "def total\n  price * quantity * tax\nend\n"
    @scratch_root.join("c_deleted.rb").delete
    scratch_write "d_added.rb", "staged\n"
    scratch_git "add", "d_added.rb"
    scratch_write "e_untracked.rb", "first\nsecond\n"
    scratch_write "logo.png", "\x89PNG\0\0second".b

    @scratch_root
  end

  def remove_scratch_repository
    FileUtils.remove_entry @scratch_root if @scratch_root&.exist?
  end

  def scratch_write(path, content)
    @scratch_root.join(path).binwrite(content)
  end

  def scratch_commit(message)
    scratch_git "add", "--all"
    scratch_git "-c", "user.name=Test", "-c", "user.email=test@example.com", "-c", "commit.gpgsign=false", "commit", "--quiet", "--message", message
  end

  def scratch_git(*arguments)
    output, status = Open3.capture2e("git", "-C", @scratch_root.to_s, *arguments)
    raise "git #{ arguments.join(" ") } failed: #{ output }" unless status.success?

    output
  end
end
