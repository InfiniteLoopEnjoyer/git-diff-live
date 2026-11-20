require "json"
require "pathname"

module GitDiffLive

  # Why one change was made: a sentence or two beside a changed line, or under
  # a file's heading. There are two kinds, told apart by +side+.
  #
  # A comment on a line is anchored to the line it was written about, not to a
  # position: +side+ says which version of the file the line is in (:new for an
  # added line, :old for a removed one), +code+ is the line's text, and +line+
  # is the number it had when the comment was written. The page puts the
  # comment beside the changed line with that text, the nearest to +line+ when
  # there are several, so it stays with its code when lines above it come and
  # go, and is left out once that code has been changed again.
  #
  # A comment on a file (+side+ :file, no +line+ or +code+) is about the file
  # as a whole: why it was deleted, moved or added, or what changed in a binary
  # one, which has no lines to point at. It shows for as long as the file is
  # one of the changes.
  Comment = Data.define(:path, :side, :line, :code, :body) do

    # A line of the store, or nil for one that is not a comment (hand-edited,
    # half-written, a merge marker).
    def self.parse(json)
      fields = JSON.parse(json)

      return unless fields.is_a?(Hash) && fields.values_at("path", "comment").all?(String)

      if fields["side"] == "file"
        new(path: fields["path"], side: :file, line: nil, code: nil, body: fields["comment"])
      elsif [ "old", "new" ].include?(fields["side"]) && fields["code"].is_a?(String) && fields["line"].is_a?(Integer)
        new(path: fields["path"], side: fields["side"].to_sym, line: fields["line"], code: fields["code"], body: fields["comment"])
      end
    rescue JSON::ParserError
      nil
    end

    def file?
      side == :file
    end

    # A comment on a file is stored without the line and code it does not have.
    def to_json(*)
      JSON.generate({ path: path, side: side, line: line, code: code, comment: body }.compact)
    end

    # "app/models/user.rb:+12", or "app/models/user.rb:file": how the command
    # line names what the comment is about.
    def reference
      "#{ path }:#{ { old: "-", new: "+", file: "file" }.fetch(side) }#{ line }"
    end

  end

  # The comments of a repository: one JSON object per line of
  # .git_diff_live/comments.jsonl, committed with the code they explain.
  #
  # Nothing reads that file to draw the page. A comparison shows the comments
  # the file *gained* between its two ends (Comments.added, off the same git
  # diff that lists the changed files), so a comment written for one commit is
  # shown with that commit, in the working tree before it is committed and in
  # any later comparison that spans it. The file only grows; what is in it from
  # before the comparison is history and is left alone.
  #
  # This class is the writing side, used by the command line (GitDiffLive::CLI):
  #
  #   comments = GitDiffLive::Comments.new(root: Dir.pwd)
  #   comments.write([
  #     [ "app/models/user.rb", :new, 12, "Why this line is here." ],
  #     [ "app/models/guest.rb", :file, nil, "Why this file is gone." ]
  #   ])
  class Comments

    DIRECTORY = ".git_diff_live"

    PATH = "#{ DIRECTORY }/comments.jsonl"

    # Two branches that each added comments merge without a conflict: git keeps
    # both sets of lines.
    ATTRIBUTES = "comments.jsonl merge=union\n"

    # What write did: the comments it wrote, the ones it could not place (each
    # with the reason), and how many earlier ones it took out.
    Result = Data.define(:written, :rejected, :removed)

    # Is +path+ part of the store? The page does not list those files as changes.
    def self.store?(path)
      path.start_with?("#{ DIRECTORY }/")
    end

    # The comments +file+ (the store, as a Diff::ChangedFile) gained in its
    # comparison. A line that was only moved is on both sides and is not new.
    def self.added(file)
      rows    = file.hunks.flat_map(&:rows)
      removed = rows.filter_map { it.old.text if it.old&.kind == :removed }

      (rows.filter_map { it.new.text if it.new&.kind == :added } - removed).filter_map { Comment.parse(it) }
    end

    attr_reader :diff

    def initialize(root:, base: "HEAD")
      @root = Pathname.new(root)
      @diff = Diff.new(root: root, base: base)
    end

    # Adds comments, each given as [ path, side, line, body ]: a changed line
    # of the working tree, or a changed file (side :file, no line). A comment
    # for a line or file that has one already replaces it. Comments written
    # since the base that no longer explain anything on the page are taken out
    # on the way: a line's when its code has changed again, a file's when the
    # file is no longer one of the changes.
    def write(notes)
      written, rejected = [], []

      notes.each do | path, side, number, body |
        comment = anchored(Comment.new(path: path, side: side, line: number, code: nil, body: body.to_s.split.join(" ")))

        if comment.is_a?(String)
          rejected << [ "#{ path }:#{ { old: "-", new: "+", file: "file" }.fetch(side) }#{ number }", comment ]
        else
          written.reject! { it.path == path && it.side == side && it.line == number }
          written << comment
        end
      end

      placed = @diff.files.flat_map do | file |
        [ [ [ file.path, :file, nil ], file.file_comments ], *file.placed_comments.map { | (side, number), comments | [ [ file.path, side, number ], comments ] } ]
      end.to_h

      stale    = @diff.comments - placed.values.flatten
      replaced = written.flat_map { placed.fetch([ it.path, it.side, it.line ], []) }
      outdated = stale | replaced

      if written.any? || outdated.any?
        kept = lines.reject { | line | Comment.parse(line).then { it && outdated.include?(it) } }

        save(kept + written.map(&:to_json))
      end

      Result.new(written: written, rejected: rejected, removed: stale.size)
    end

    private

    # +comment+ ready to store, a line's with the text of the changed line it
    # is to sit beside; or what is wrong with it, as a sentence.
    def anchored(comment)
      file = @diff.file(comment.path)

      return "#{ comment.path } is not a changed file" if file.nil?
      return "the comment is empty" if comment.body.empty?
      return comment if comment.file?

      changed = file.changed_lines(comment.side)
      line    = changed.find { it.number == comment.line }

      return comment.with(code: line.text) if line

      sign = comment.side == :old ? "-" : "+"
      near = changed.map(&:number).min_by(5) { (it - comment.line).abs }.sort.map { "#{ sign }#{ it }" }

      "#{ sign }#{ comment.line } is not #{ comment.side == :old ? "a removed" : "an added" } line#{ near.any? ? "; the nearest are #{ near.join(", ") }" : "; the file has none (#{ comment.path }:file comments on the file)" }"
    end

    def lines
      file = @root.join(PATH)

      file.file? ? file.readlines(chomp: true).reject(&:empty?) : []
    end

    def save(lines)
      @root.join(DIRECTORY).mkpath
      @root.join(DIRECTORY, ".gitattributes").then { it.write(ATTRIBUTES) unless it.exist? }
      @root.join(PATH).write(lines.map { "#{ it }\n" }.join)
    end

  end

end
