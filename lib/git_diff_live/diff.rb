require "digest"
require "open3"
require "pathname"

module GitDiffLive

  # A repository's working tree compared with a commit, as side-by-side rows:
  # what the changes page draws. Git computes the diff, renames and binary files
  # included; this class only reads its output. Staged and unstaged changes are
  # shown together, and untracked files are listed as added.
  #
  #   diff = GitDiffLive::Diff.new(root: Rails.root, base: "HEAD")
  #   diff.files.each do | file |
  #     file.status       # :modified, :added, :deleted, :renamed, :copied or :unmerged
  #     file.hunks.each do | hunk |
  #       hunk.rows.each { | row | row.old&.number; row.new&.segments }
  #     end
  #   end
  #
  # +context+ is the number of unchanged lines kept around each change;
  # WHOLE_FILE keeps them all, so a file comes back complete.
  #
  # Plain Ruby: it needs git on the PATH and nothing from Rails.
  class Diff

    # Raised for a +base+ that does not name a commit.
    class UnknownRevision < StandardError; end

    # Raised when git itself fails.
    class GitError < StandardError; end

    DEFAULT_CONTEXT = 3

    # More context lines than any file has.
    WHOLE_FILE = 1_000_000

    # A file with more changed lines than this is not drawn until asked for.
    LARGE_FILE = 1_500

    # An untracked file bigger than this (1 MB) is listed without its contents.
    MAX_UNTRACKED_BYTES = 1_048_576

    # Two paired lines with more tokens between them than this (as a product) are
    # not compared word by word.
    MAX_TOKEN_PRODUCT = 20_000

    STATUSES = { "M" => :modified, "T" => :modified, "A" => :added, "D" => :deleted, "R" => :renamed, "C" => :copied, "U" => :unmerged }.freeze

    # One side of a row: its line number in that version of the file, its kind
    # (:context, :removed or :added) and its text as [ text, changed ] segments,
    # where a changed segment is the part of a paired line that differs.
    Line = Data.define(:number, :kind, :segments)

    # A row of the comparison. +old+ is nil beside an added line, +new+ is nil
    # beside a removed one.
    Row = Data.define(:old, :new)

    # A run of rows, headed by git's "@@ -12,7 +12,9 @@ def create" line.
    Hunk = Data.define(:heading, :rows)

    # One file of the comparison. The patch is parsed on first use, so listing
    # many files to show one costs little.
    class ChangedFile

      attr_reader :status, :path, :old_path

      def initialize(status:, path:, old_path: nil, patch: "", untracked: false, unreadable: false)
        @status     = status
        @path       = path
        @old_path   = old_path
        @patch      = patch
        @untracked  = untracked
        @unreadable = unreadable
      end

      def untracked?
        @untracked
      end

      # Drawn complete, every unchanged line included (Diff#whole).
      def whole?
        @whole == true
      end

      # What this file's change is, in twelve characters: the page holds one
      # per file it shows and sends them back when the tree changes, so only
      # the files that are no longer the same are drawn again.
      def digest
        @digest ||= Digest::SHA1.hexdigest([ status, old_path, @unreadable, @patch ].join("\0"))[0, 12]
      end

      # This file as the whole-file version of +file+: it stands in for it on
      # the page, so it answers with its digest. The two patches differ only in
      # how much unchanged text surrounds the same change.
      def as_whole_of(file)
        @whole  = true
        @digest = file.digest
        self
      end

      # Git could not show a text diff (an image, a font, a PDF), or the file is
      # an untracked one too big to read.
      def binary?
        @unreadable || @patch.match?(/^(Binary files .* differ|GIT binary patch)$/)
      end

      def hunks
        @hunks ||= parse
      end

      # Counted off the patch itself, not the parsed rows: the list of files
      # shows every file's counts, and should not have to parse every file.
      def additions
        @additions ||= body.scan(/^\+/).size
      end

      def deletions
        @deletions ||= body.scan(/^-/).size
      end

      # Renamed or re-moded with no change to the content.
      def unchanged_content?
        !binary? && hunks.empty?
      end

      def large?
        additions + deletions > LARGE_FILE
      end

      # Where the first change sits in the file as it is now: the line an editor
      # should open it at. A removal has no line of its own there, so it counts
      # as the line after the one above it.
      def first_changed_line
        hunks.each do | hunk |
          above = nil

          hunk.rows.each do | row |
            return row.new&.number || above.to_i + 1 if row.old&.kind == :removed || row.new&.kind == :added

            above = row.new.number
          end
        end

        1
      end

      # A stable id for the file's element on the page.
      def dom_id
        self.class.dom_id(path)
      end

      def self.dom_id(path)
        "file-#{ Digest::SHA1.hexdigest(path)[0, 12] }"
      end

      private

      # The patch from its first hunk on: the lines above it (index, ---, +++)
      # are not changes.
      def body
        @patch[/^@@ .*/m].to_s
      end

      # Reads the hunks out of the unified patch. A change is a run of "-" lines
      # followed by a run of "+" lines: they are paired off in order, first
      # removed with first added, and whatever is left over stands alone.
      def parse
        hunks = []
        removed, added = [], []
        old_number = new_number = 0

        flush = lambda do
          hunks.last.rows.concat(pair(removed, added)) if hunks.any?
          removed, added = [], []
        end

        @patch.each_line(chomp: true) do | line |
          if (header = line.match(/\A@@ -(\d+)(?:,\d+)? \+(\d+)(?:,\d+)? @@/))
            flush.call
            hunks << Hunk.new(heading: line, rows: [])
            old_number, new_number = header[1].to_i, header[2].to_i
          elsif hunks.empty?
            # The lines above the first hunk: index, mode, rename from / to, ---, +++.
            next
          elsif line.start_with?("-")
            removed << [ old_number, line[1..] ]
            old_number += 1
          elsif line.start_with?("+")
            added << [ new_number, line[1..] ]
            new_number += 1
          elsif line.start_with?("\\")
            # "\ No newline at end of file" belongs to the line above it.
            next
          else
            flush.call
            text = [ [ line[1..].to_s, false ] ]
            hunks.last.rows << Row.new(old: Line.new(number: old_number, kind: :context, segments: text), new: Line.new(number: new_number, kind: :context, segments: text))
            old_number += 1
            new_number += 1
          end
        end

        flush.call
        hunks
      end

      def pair(removed, added)
        Array.new([ removed.size, added.size ].max) do | index |
          old_number, old_text = removed[index]
          new_number, new_text = added[index]

          old_segments, new_segments =
            if old_text && new_text
              Diff.segments(old_text, new_text)
            else
              [ [ [ old_text, false ] ], [ [ new_text, false ] ] ]
            end

          Row.new(
            old: (Line.new(number: old_number, kind: :removed, segments: old_segments) if old_text),
            new: (Line.new(number: new_number, kind: :added, segments: new_segments) if new_text)
          )
        end
      end

    end

    attr_reader :base, :context, :root

    def initialize(root: Dir.pwd, base: "HEAD", context: DEFAULT_CONTEXT)
      @root    = Pathname.new(root)
      @base    = base.to_s
      @context = context
    end

    # The commit the working tree is compared with, as a full SHA. +base+ comes
    # from the query string: it has to look like a revision (so it can never be
    # read as an option) and has to name a commit.
    def base_sha
      @base_sha ||= begin
        raise UnknownRevision, "#{ base.inspect } is not a revision" unless base.match?(/\A[\w.\/~^@{}][\w.\/~^@{}-]*\z/)

        sha, status = git("rev-parse", "--verify", "--quiet", "--end-of-options", "#{ base }^{commit}", allow_failure: true)
        raise UnknownRevision, "#{ base.inspect } does not name a commit" unless status.success?

        sha.strip
      end
    end

    def branch
      @branch ||= git("rev-parse", "--abbrev-ref", "HEAD").first.strip
    end

    # Every changed file, tracked or not, by path.
    def files
      @files ||= (tracked_files + untracked_files).sort_by(&:path)
    end

    def file(path)
      files.find { it.path == path }
    end

    # +file+ again with every unchanged line, for drawing it whole. One more
    # git call, made the first time a whole file is asked for.
    def whole(file)
      @complete ||= self.class.new(root: root, base: base, context: WHOLE_FILE)

      @complete.file(file.path)&.as_whole_of(file) || file
    end

    # A digest that changes whenever the page would: the commit compared with,
    # the patch of every tracked change, and the size and modification time of
    # every untracked file. The page polls it to know when to redraw itself.
    def fingerprint
      Digest::SHA1.hexdigest([ base_sha, tracked_output, *untracked_paths.flat_map { | path | [ path, *stamp(path) ] } ].join("\0"))
    end

    # Marks what differs between a removed line and the added line it is paired
    # with, word by word. Returns the two lines as [ text, changed ] segments.
    # Lines with too little in common come back unmarked: the whole row is
    # already coloured, and marking every word of it says nothing more.
    def self.segments(old_text, new_text)
      old_tokens, new_tokens = [ old_text, new_text ].map { it.scan(/\w+|\s+|[^\w\s]/) }

      shortest = [ old_tokens.size, new_tokens.size ].min
      prefix = 0
      prefix += 1 while prefix < shortest && old_tokens[prefix] == new_tokens[prefix]
      suffix = 0
      suffix += 1 while suffix < shortest - prefix && old_tokens[-1 - suffix] == new_tokens[-1 - suffix]

      old_middle = old_tokens[prefix, old_tokens.size - prefix - suffix]
      new_middle = new_tokens[prefix, new_tokens.size - prefix - suffix]

      old_changed, new_changed =
        if old_middle.size * new_middle.size > MAX_TOKEN_PRODUCT
          [ Array.new(old_middle.size, true), Array.new(new_middle.size, true) ]
        else
          common_subsequence(old_middle, new_middle)
        end

      old_flags = Array.new(prefix, false) + old_changed + Array.new(suffix, false)
      new_flags = Array.new(prefix, false) + new_changed + Array.new(suffix, false)

      if alike?(old_tokens, old_flags) && alike?(new_tokens, new_flags)
        [ join(old_tokens, old_flags), join(new_tokens, new_flags) ]
      else
        [ [ [ old_text, false ] ], [ [ new_text, false ] ] ]
      end
    end

    # Which tokens of each list fall outside their longest common subsequence.
    def self.common_subsequence(old_tokens, new_tokens)
      lengths = Array.new(old_tokens.size + 1) { Array.new(new_tokens.size + 1, 0) }

      (old_tokens.size - 1).downto(0) do | i |
        (new_tokens.size - 1).downto(0) do | j |
          lengths[i][j] = old_tokens[i] == new_tokens[j] ? lengths[i + 1][j + 1] + 1 : [ lengths[i + 1][j], lengths[i][j + 1] ].max
        end
      end

      old_changed = Array.new(old_tokens.size, true)
      new_changed = Array.new(new_tokens.size, true)
      i = j = 0

      while i < old_tokens.size && j < new_tokens.size
        if old_tokens[i] == new_tokens[j]
          old_changed[i] = new_changed[j] = false
          i += 1
          j += 1
        elsif lengths[i + 1][j] >= lengths[i][j + 1]
          i += 1
        else
          j += 1
        end
      end

      [ old_changed, new_changed ]
    end

    # At least a third of the line's visible characters are unchanged.
    def self.alike?(tokens, flags)
      visible   = tokens.each_index.reject { tokens[it].match?(/\A\s+\z/) }
      unchanged = visible.reject { flags[it] }.sum { tokens[it].size }

      unchanged * 3 >= visible.sum { tokens[it].size } && unchanged.positive?
    end

    # Tokens to segments. A space left unchanged between two changed words is
    # marked with them, so a rewritten phrase reads as one stretch.
    def self.join(tokens, flags)
      flags = flags.each_with_index.map do | changed, index |
        changed || (tokens[index].match?(/\A\s+\z/) && index.positive? && flags[index - 1] && flags[index + 1] == true)
      end

      tokens.zip(flags).chunk_while { | (_, a), (_, b) | a == b }.map { | run | [ run.sum("") { it.first }, run.first.last ] }
    end

    private_class_method :common_subsequence, :alike?, :join

    private

    # One git call gives the file list and the patches from the same snapshot:
    # NUL-separated raw records (exact paths, whatever characters they hold),
    # an empty record, then the patch, one "diff --git" block per record in the
    # same order.
    def tracked_output
      @tracked_output ||= git("diff", "--patch-with-raw", "-z", "--no-color", "--no-ext-diff", "--no-textconv", "--find-renames", "--unified=#{ context }", base_sha, "--").first
    end

    def tracked_files
      return [] if tracked_output.empty?

      raw, patch = tracked_output.split("\0\0", 2)
      fields  = raw.split("\0")
      records = []

      while (meta = fields.shift)
        letter   = meta.split(" ").last[0]
        # A rename or copy record carries two paths, the old one first. The nil matters: the variable outlives the iteration.
        old_path = [ "R", "C" ].include?(letter) ? fields.shift : nil

        records << { status: STATUSES.fetch(letter, :modified), path: fields.shift, old_path: old_path }
      end

      patches = patch.to_s.split(/^(?=diff --(?:git|cc|combined) )/)
      raise GitError, "git listed #{ records.size } files but sent #{ patches.size } patches" unless records.size == patches.size

      records.zip(patches).map { | record, patch | ChangedFile.new(**record, patch: patch) }
    end

    def untracked_paths
      @untracked_paths ||= git("ls-files", "--others", "--exclude-standard", "-z").first.split("\0")
    end

    def untracked_files
      untracked_paths.map do | path |
        full_path = root.join(path)
        content   = full_path.binread if full_path.file? && full_path.size <= MAX_UNTRACKED_BYTES

        if content.nil? || content.include?("\0")
          ChangedFile.new(status: :added, path: path, untracked: true, unreadable: true)
        else
          lines = content.force_encoding(Encoding::UTF_8).scrub.lines(chomp: true)
          patch = "@@ -0,0 +1,#{ lines.size } @@\n#{ lines.map { "+#{ it }\n" }.join }"

          ChangedFile.new(status: :added, path: path, untracked: true, patch: lines.any? ? patch : "")
        end
      end
    end

    # A file's size and modification time, or nothing if it has just gone.
    def stamp(path)
      stat = root.join(path).stat

      [ stat.size, stat.mtime.to_f ]
    rescue SystemCallError
      []
    end

    # Runs git in the repository, never through a shell, and without taking the
    # index lock (a page load must not get in the way of a commit in progress).
    def git(*arguments, allow_failure: false)
      output, error, status = Open3.capture3({ "GIT_OPTIONAL_LOCKS" => "0" }, "git", "-C", root.to_s, *arguments)
      raise GitError, (error.empty? ? "git #{ arguments.first } failed" : error) unless status.success? || allow_failure

      [ output.force_encoding(Encoding::UTF_8).scrub, status ]
    end

  end

end
