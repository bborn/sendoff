import { Controller } from "@hotwired/stimulus"

// Drives the draft review <dialog>. Opens as soon as the partial lands in the
// Turbo Frame, closes on the Close/Cancel buttons, a backdrop click, or when
// the frame is emptied by a Turbo Stream (send/schedule/discard).
export default class extends Controller {
  connect() {
    this.dialog = this.element
    if (typeof this.dialog.showModal === "function" && !this.dialog.open) {
      this.dialog.showModal()
    }
    this.onBackdrop = this.onBackdrop.bind(this)
    this.dialog.addEventListener("click", this.onBackdrop)
  }

  disconnect() {
    this.dialog.removeEventListener("click", this.onBackdrop)
    if (this.dialog.open) this.dialog.close()
  }

  close(event) {
    if (event) event.preventDefault()
    if (this.dialog.open) this.dialog.close()
    // Empty the frame so re-opening the same draft re-fetches a fresh modal.
    const frame = this.dialog.closest("turbo-frame")
    if (frame) frame.innerHTML = ""
  }

  // A click whose target is the <dialog> itself (not its children) is a click
  // on the backdrop region.
  onBackdrop(event) {
    if (event.target === this.dialog) this.close(event)
  }
}
