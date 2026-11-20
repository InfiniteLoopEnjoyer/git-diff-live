require "optparse"

require_relative "diff"

module GitDiffLive

  # The command line (exe/git_diff_live): how an agent writes the comments the
  # changes page draws beside each change. Plain Ruby, no Rails: it runs in the
  # repository it is called from.
  #
  #   git_diff_live changes                 # the changes that have no comment yet
  #   git_diff_live comment <<'EOF'         # one comment a line: reference, then the comment
  #   app/models/user.rb:+12 Why this line was added.
  #   app/models/user.rb:-30 Why that one was removed.
  #   app/models/guest.rb:file Why this file was deleted.
  #   EOF
  #
  # A reference names a changed line (+12 is line 12 of the file as it is now,
  # -30 is line 30 of the file as it was at the base) or, with "file", the
  # changed file as a whole.
  class CLI

    USAGE = <<~TEXT
      Usage: git_diff_live changes [--all] [--full] [--base REVISION] [PATH ...]
             git_diff_live comment [--base REVISION] [REFERENCE COMMENT]

      changes   Lists the working tree's changes that have no comment yet, hunk by
                hunk, every changed line with its reference. --all lists the
                commented ones too, with their comments. --full prints long
                changes complete.
      comment   Writes comments to #{ Comments::PATH }. Give one as two
                arguments, or any number on standard input, one a line:

                  app/models/user.rb:+12 Why this line was added.
                  app/models/user.rb:-30 Why this line was removed.
                  app/models/guest.rb:file Why this file was deleted.

                +12 is line 12 of the file now; -30 is line 30 of the file at the
                base. The page draws the comment beside that line. "file" is the
                file as a whole (a delete, a move, a binary file): the page draws
                the comment under the file's heading.

      --base    The commit the working tree is compared with. Default: HEAD.
    TEXT

    # A long run of changed lines is cut to this many a side, and a long line
    # to this many characters, unless --full is given.
    SHOWN_LINES = 8

    SHOWN_WIDTH = 160

    # "app/models/user.rb:+12 Why this line was added.", or ":file" for the
    # file as a whole. The path may hold spaces.
    LINE = /\A(?<path>.+?):(?:(?<sign>[+-])(?<line>\d+)|file)(?:\s+(?<body>.*))?\z/

    def initialize(root: Dir.pwd, input: $stdin, output: $stdout, error: $stderr)
      @root   = root
      @input  = input
      @output = output
      @error  = error
    end

    # Runs one command and returns the exit status.
    def run(arguments)
      arguments = arguments.dup
      options   = { base: "HEAD" }

      OptionParser.new do | parser |
        parser.on("--all") { options[:all] = true }
        parser.on("--full") { options[:full] = true }
        parser.on("--base REVISION") { options[:base] = it }
      end.parse!(arguments)

      case arguments.shift
      when "changes" then changes(arguments, **options)
      when "comment" then comment(arguments, **options)
      else
        @output.puts USAGE
        1
      end
    rescue OptionParser::ParseError, Diff::UnknownRevision, Diff::GitError => error
      @error.puts error.message.strip
      1
    end

    private

    # A change is a hunk: the changed lines git drew together, a comment on
    # any of them being its comment. That is the page's unit too, each hunk
    # under its own heading. A file with no hunk (moved, binary) is one change,
    # and so is a file added or deleted once it has a comment on the file.
    def changes(paths, base:, all: false, full: false)
      files = Diff.new(root: @root, base: base).files.reject { it.status == :unmerged }
      files = files.select { | file | paths.any? { file.path == it || file.path.start_with?("#{ it.chomp("/") }/") } } if paths.any?
      left  = 0

      files.each do | file |
        covered = file.whole_change? && file.file_comments.any?
        hunks   = file.hunks.map { | hunk | [ hunk, hunk.rows.flat_map { file.comments_beside(it) } ] }
        open    = covered ? [] : hunks.select { it.last.empty? }
        bare    = file.hunks.empty? && !covered
        left   += open.size + (bare ? 1 : 0)

        next unless all || bare || open.any?

        @output.puts "#{ file.path } (#{ file.status }#{ " from #{ file.old_path }" if file.old_path })"
        file.file_comments.each { @output.puts "  file has: #{ it.body }" }

        @output.puts "  #{ file.binary? ? "Binary" : "Content unchanged" }, no lines to comment on. Comment on the file: #{ file.path }:file" if bare
        @output.puts if file.hunks.empty?

        (all ? hunks : open).each do | hunk, comments |
          @output.puts "  #{ hunk.heading }"
          print_hunk hunk, full
          comments.each { @output.puts "  #{ it.reference.delete_prefix("#{ it.path }:") } has: #{ it.body }" }
          @output.puts
        end
      end

      @output.puts left.zero? ? "Every change has a comment." : "#{ left } #{ left == 1 ? "change" : "changes" } without a comment."
      0
    end

    # The hunk's changed lines, removed before added as in a patch, and the
    # unchanged lines between two runs of them (not those around the hunk).
    def print_hunk(hunk, full)
      runs = hunk.rows.chunk_while { | above, below | above.changed? == below.changed? }.to_a
      runs.shift unless runs.first.first.changed?
      runs.pop unless runs.last.first.changed?

      runs.each do | rows |
        if rows.first.changed?
          print_lines rows.filter_map(&:old), "-", full
          print_lines rows.filter_map(&:new), "+", full
        else
          print_lines rows.map(&:new), nil, true
        end
      end
    end

    def print_lines(lines, sign, full)
      shown = full ? lines : lines.first(SHOWN_LINES)

      shown.each do | line |
        text = full || line.text.size <= SHOWN_WIDTH ? line.text : "#{ line.text[0, SHOWN_WIDTH] }..."

        @output.puts "  #{ (sign ? "#{ sign }#{ line.number }" : "").ljust(6) }| #{ text }".rstrip
      end

      @output.puts "  ...    | #{ lines.size - shown.size } more, to #{ sign }#{ lines.last.number }" if shown.size < lines.size
    end

    def comment(arguments, base:, **)
      given = arguments.any? ? [ arguments.join(" ") ] : @input.each_line(chomp: true).reject { it.strip.empty? }
      notes, unread = [], []

      given.each do | line |
        if (match = LINE.match(line.strip))
          notes << [ match[:path], { "-" => :old, "+" => :new, nil => :file }.fetch(match[:sign]), match[:line]&.to_i, match[:body] ]
        else
          unread << [ line.strip[/\A\S+/], "not a reference: write path:+LINE for an added line, path:-LINE for a removed one, path:file for the file" ]
        end
      end

      result   = Comments.new(root: @root, base: base).write(notes)
      rejected = unread + result.rejected

      @output.puts "#{ result.written.size } #{ result.written.size == 1 ? "comment" : "comments" } written to #{ Comments::PATH }."
      @output.puts "#{ result.removed } earlier #{ result.removed == 1 ? "comment" : "comments" } removed: the code changed again." if result.removed.positive?
      rejected.each { | reference, reason | @error.puts "Not written: #{ reference }: #{ reason }" }

      rejected.empty? ? 0 : 1
    end

  end

end
