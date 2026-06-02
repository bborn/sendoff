import { Controller } from "@hotwired/stimulus"

// Auto-dismiss flash/toast messages appended into the container.
export default class extends Controller {
  connect() {
    this.element.querySelectorAll("[data-toast]").forEach((t) => this.schedule(t))
  }

  toastTargetConnected(el) { this.schedule(el) }

  schedule(el) {
    setTimeout(() => {
      el.style.opacity = "0"
      setTimeout(() => el.remove(), 300)
    }, 4000)
  }
}
