GitDiffLive::Engine.routes.draw do
  # One file redrawn in place: whole, or back to the lines around its changes.
  get "file", to: "changes#file", as: :file

  # The digest the page polls to learn that the working tree has changed, and
  # the redraw of whatever is no longer what the page holds.
  get "fingerprint", to: "changes#fingerprint", as: :fingerprint
  post "refresh", to: "changes#refresh", as: :refresh

  # Every changed file, side by side.
  root to: "changes#index"
end
