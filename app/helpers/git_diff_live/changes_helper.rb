module GitDiffLive

  # The cells and links of the changes page. Its colours are fixed and dark
  # (tailwind/git_diff_live.css); every class named here is compiled into the
  # gem's stylesheet by `rake css`.
  module ChangesHelper

    BUTTON = "inline-flex items-center gap-2 px-3 py-1 rounded border border-edge bg-raised text-fg whitespace-nowrap cursor-pointer hover:border-accent"

    LINK = "text-accent hover:text-accent-hover whitespace-nowrap"

    # The line-number cell of one side of a row, by the line's kind.
    NUMBER_CLASSES = {
      context: "text-fg-muted",
      removed: "bg-red-950 text-red-300",
      added:   "bg-emerald-950 text-emerald-300"
    }.freeze

    # The code cell.
    CODE_CLASSES = {
      context: "",
      removed: "bg-red-950/50",
      added:   "bg-emerald-950/50"
    }.freeze

    # The part of a paired line that differs from its partner.
    MARK_CLASSES = {
      removed: "rounded-xs bg-red-800",
      added:   "rounded-xs bg-emerald-800"
    }.freeze

    def change_button_classes
      BUTTON
    end

    def change_link_classes
      LINK
    end

    def change_number_classes(line)
      NUMBER_CLASSES.fetch(line.kind)
    end

    def change_code_classes(line)
      CODE_CLASSES.fetch(line.kind)
    end

    # A line's text, the changed stretches marked. Built here and not in the
    # template so no whitespace gets between the pieces: the cell is
    # whitespace-pre-wrap and would show it.
    def change_code(line)
      safe_join(line.segments.map { | text, changed | changed ? tag.span(text, class: MARK_CLASSES.fetch(line.kind)) : text })
    end

    # The status glyph beside a file's name. Each icon is a literal icon(:fas, :name)
    # call so fontawesome_subsetter finds it.
    def change_status_icon(file)
      case file.status
      when :added    then tag.span(icon(:fas, :plus), class: "text-emerald-400", title: file.untracked? ? "Added (untracked)" : "Added")
      when :deleted  then tag.span(icon(:fas, :minus), class: "text-red-400", title: "Deleted")
      when :renamed  then tag.span(icon(:fas, :right_left), class: "text-sky-400", title: "Renamed")
      when :copied   then tag.span(icon(:fas, :right_left), class: "text-sky-400", title: "Copied")
      when :unmerged then tag.span(icon(:fas, :ban), class: "text-amber-400", title: "Unmerged")
      else                tag.span(icon(:fas, :pen), class: "text-amber-400", title: "Modified")
      end
    end

    # "+12 −3", each number in its colour, zeros left out.
    def change_counts(additions, deletions)
      safe_join([
        (tag.span("+#{ number_with_delimiter additions }", class: "text-emerald-400") if additions.positive?),
        (tag.span("−#{ number_with_delimiter deletions }", class: "text-red-400") if deletions.positive?)
      ].compact, " ")
    end

    # The query that keeps a link on the commit the page is comparing with.
    def change_base_params
      { base: params[:base].presence }.compact
    end

    # A link the browser hands to an editor, which opens the file at that line.
    # By default VS Code. A server running under WSL names its distro so the
    # link reaches the Remote - WSL window: a Windows browser cannot open a
    # Linux path as a local file.
    def change_editor_url(path, line)
      escaped = path.to_s.split("/").map { ERB::Util.url_encode(it) }.join("/")

      if (template = GitDiffLive.configuration.editor_url)
        format(template, path: escaped, line: line)
      else
        distro = ENV["WSL_DISTRO_NAME"]

        "#{ distro.present? ? "vscode://vscode-remote/wsl+#{ distro }" : "vscode://file" }#{ escaped }:#{ line }"
      end
    end

  end

end
