# The page's own import map (GitDiffLive.importmap), drawn by the engine. Turbo
# and Stimulus are the files turbo-rails and stimulus-rails ship.
pin "application", to: "git_diff_live/application.js"
pin "@hotwired/turbo-rails", to: "turbo.min.js"
pin "@hotwired/stimulus", to: "stimulus.min.js"
pin "controllers/changes_controller", to: "git_diff_live/controllers/changes_controller.js"
