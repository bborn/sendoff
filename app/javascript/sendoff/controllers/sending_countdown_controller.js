import { Controller } from "@hotwired/stimulus"

// A 60s "sending…" countdown bar with an Undo/abort link. The hold window mirrors
// the Sender's 60s DeliverJob delay. If no abort endpoint is wired (data-sending-
// countdown-abort-url-value is blank), the link is hidden and the bar is purely
// cosmetic — it never throws.
export default class extends Controller {
  static targets = ["bar", "label", "undo"]
  static values = {
    seconds: { type: Number, default: 60 },
    abortUrl: { type: String, default: "" }
  }

  connect() {
    this.remaining = this.secondsValue
    if (this.hasUndoTarget && !this.abortUrlValue) {
      this.undoTarget.hidden = true
    }
    this.render()
    this.timer = setInterval(() => this.tick(), 1000)
  }

  disconnect() {
    if (this.timer) clearInterval(this.timer)
  }

  tick() {
    this.remaining -= 1
    if (this.remaining <= 0) {
      this.remaining = 0
      clearInterval(this.timer)
    }
    this.render()
  }

  render() {
    if (this.hasBarTarget) {
      const pct = Math.max(0, (this.remaining / this.secondsValue) * 100)
      this.barTarget.style.width = `${pct}%`
    }
    if (this.hasLabelTarget) {
      this.labelTarget.textContent = `Sending in ${this.remaining}s`
    }
  }

  // Best-effort abort. Submits to the abort URL if present; otherwise no-op so
  // the link never errors.
  abort(event) {
    if (event) event.preventDefault()
    if (!this.abortUrlValue) return
    clearInterval(this.timer)
    const form = document.createElement("form")
    form.method = "post"
    form.action = this.abortUrlValue
    const token = document.querySelector('meta[name="csrf-token"]')
    if (token) {
      const input = document.createElement("input")
      input.type = "hidden"
      input.name = "authenticity_token"
      input.value = token.content
      form.appendChild(input)
    }
    document.body.appendChild(form)
    form.requestSubmit ? form.requestSubmit() : form.submit()
  }
}
