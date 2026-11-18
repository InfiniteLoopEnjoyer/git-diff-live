/*

The changes page (git_diff_live/changes/index).

Live reload: every interval it asks the server for the diff's fingerprint.
When that is no longer the one the page was drawn from (the summary carries
it), it posts what the page holds, each file's path and digest and whether it
is drawn whole or shown although large, and renders the Turbo Streams that
come back: only the files that changed, came or went, and the counts. A
hidden tab does not poll; it catches up when it is shown again.

Each file is a <details>, so opening and closing one needs no JavaScript. This
controller opens or closes them all, and keeps a file the way the reader left
it when a refresh morphs it (the server always draws a file open, or closed if
it was deleted).

USAGE:

div data-controller="changes" data-changes-fingerprint-url-value="/changes/fingerprint" data-changes-refresh-url-value="/changes/refresh" data-changes-interval-value="2000" data-action="turbo:before-morph-attribute->changes#keepOpenState"
  div data-changes-target="summary" data-fingerprint="3f2a…"
  span data-changes-target="status"
  button data-action="changes#expand"
  button data-action="changes#collapse"
  details data-changes-target="file" data-path="app/models/user.rb" data-digest="9c1e…" data-whole="true" data-shown="true"

*/

import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"

export default class extends Controller {

  static targets = [ "file", "status", "summary" ]

  static values = { fingerprintUrl: String, refreshUrl: String, interval: Number }

  connect() {
    if (this.intervalValue <= 0) return

    this.poll  = this.poll.bind(this)
    this.timer = setInterval(this.poll, this.intervalValue)

    document.addEventListener("visibilitychange", this.poll)
  }

  disconnect() {
    clearInterval(this.timer)

    document.removeEventListener("visibilitychange", this.poll)
  }

  async poll() {
    if (document.hidden || this.polling) return

    this.polling = true

    try {
      const response = await fetch(this.fingerprintUrlValue, { headers: { Accept: "text/plain" } })

      this.connected = response.ok

      if (response.ok && (await response.text()) !== this.summaryTarget.dataset.fingerprint)
        await this.refresh()
    } catch {
      // The server is restarting or gone; the next tick tries again.
      this.connected = false
    } finally {
      this.polling = false
    }
  }

  // The summary in the answer carries the new fingerprint, so a refresh that
  // fails leaves the old one in place and the next tick tries again.
  async refresh() {
    const held = new FormData()

    this.fileTargets.forEach(file => {
      held.append("paths[]", file.dataset.path)
      held.append("digests[]", file.dataset.digest)

      if (file.dataset.whole) held.append("whole[]", file.dataset.path)
      if (file.dataset.shown) held.append("shown[]", file.dataset.path)
    })

    const response = await fetch(this.refreshUrlValue, {
      method:  "POST",
      headers: { Accept: "text/vnd.turbo-stream.html", "X-CSRF-Token": document.querySelector("meta[name=csrf-token]")?.content },
      body:    held
    })

    if (response.ok)
      Turbo.renderStreamMessage(await response.text())
  }

  // The live marker dims while the server does not answer.
  set connected(connected) {
    if (this.hasStatusTarget)
      this.statusTarget.classList.toggle("opacity-30", !connected)
  }

  keepOpenState(event) {
    if (event.detail.attributeName === "open")
      event.preventDefault()
  }

  expand() {
    this.fileTargets.forEach(file => file.open = true)
  }

  collapse() {
    this.fileTargets.forEach(file => file.open = false)
  }

}
