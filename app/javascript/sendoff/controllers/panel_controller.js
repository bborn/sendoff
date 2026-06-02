import { Controller } from "@hotwired/stimulus"

// Minimal slide-in panel controller. The Leads screen renders lead detail as a
// full page, so this is a graceful open/close handler for any `.panel` element
// (e.g. an optional slide-in). All actions no-op safely when the panel is
// absent, so wiring it up never throws.
//
// Usage:
//   <div data-controller="panel">
//     <button data-action="panel#open">Open</button>
//     <aside class="panel" data-panel-target="panel" hidden>…
//       <button data-action="panel#close">×</button>
//     </aside>
//   </div>
export default class extends Controller {
  static targets = ["panel"]

  connect() {
    this._onKeydown = (e) => { if (e.key === "Escape") this.close() }
    document.addEventListener("keydown", this._onKeydown)
  }

  disconnect() {
    document.removeEventListener("keydown", this._onKeydown)
  }

  open(event) {
    if (event) event.preventDefault()
    const panel = this._panel()
    if (panel) panel.hidden = false
  }

  close(event) {
    if (event) event.preventDefault()
    const panel = this._panel()
    if (panel) panel.hidden = true
  }

  _panel() {
    return this.hasPanelTarget ? this.panelTarget : this.element.querySelector(".panel")
  }
}
