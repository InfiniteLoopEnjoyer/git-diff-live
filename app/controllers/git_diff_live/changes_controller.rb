module GitDiffLive

  # The changes page: every file that differs between the working tree and a
  # commit, old on the left and new on the right (GitDiffLive::Diff).
  #
  # +base+ is the commit to compare with, HEAD unless given: any revision git
  # understands (a SHA, a branch, HEAD~3). +head+ is the commit to compare
  # with it instead of the working tree: base=HEAD~1&head=HEAD is the last
  # commit on its own.
  #
  # Beside each change goes the comment written about it, if there is one
  # (GitDiffLive::Comments).
  #
  # == Live reload
  #
  # The page is drawn once (index) and then kept up to date in pieces. Every
  # few seconds it asks for the diff's fingerprint; when that is no longer the
  # one it holds, it posts the digest of every file it shows to refresh, which
  # answers with Turbo Streams for the difference only: the files that
  # changed, came or went, and the counts. A page of two hundred files is not
  # drawn again because one of them was saved.
  class ChangesController < ApplicationController

    rescue_from Diff::UnknownRevision, with: :unknown_revision

    before_action :set_diff

    # GET / — all changed files, each with the lines around its changes.
    def index
      @files = @diff.files
    end

    # GET /file?path= — one file, redrawn in place as a Turbo Stream: the
    # "Whole file", "Changes only" and "Show them" links. +whole+ draws the
    # complete file, +show+ draws it although it is large.
    def file
      @file = @diff.file(params[:path].to_s)

      return head :not_found if @file.nil?

      @file  = @diff.whole(@file) if params[:whole].present?
      @shown = params[:show].present?
    end

    # GET /fingerprint — the digest of the diff as it is now.
    def fingerprint
      render plain: @diff.fingerprint
    end

    # POST /refresh — what the page holds (paths and digests, in step; whole
    # and shown name the files it draws whole, or draws although large), and
    # back come the streams that bring it up to date.
    def refresh
      @files = @diff.files
      @held  = Array(params[:paths]).map(&:to_s).zip(Array(params[:digests]).map(&:to_s)).to_h
      @whole = Array(params[:whole]).map(&:to_s)
      @shown = Array(params[:shown]).map(&:to_s)
      @gone  = @held.keys - @files.map(&:path)
    end

    private

    def set_diff
      @diff = Diff.new(root: GitDiffLive.configuration.root, base: params[:base].presence || "HEAD", head: params[:head].presence, context: GitDiffLive.configuration.context)
    end

    def unknown_revision(error)
      render plain: error.message, status: :not_found
    end

  end

end
