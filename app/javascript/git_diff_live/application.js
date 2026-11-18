// The changes page's JavaScript: Turbo (the page redraws itself by morphing)
// and the one Stimulus controller on it.
import "@hotwired/turbo-rails"
import { Application } from "@hotwired/stimulus"
import ChangesController from "controllers/changes_controller"

const application = Application.start()

application.register("changes", ChangesController)
