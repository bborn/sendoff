import { Controller } from "@hotwired/stimulus"

// Copy a value to the clipboard. Usage:
//   <button data-controller="clipboard" data-clipboard-text-value="x@y.com"
//           data-action="clipboard#copy">Copy</button>
export default class extends Controller {
  static values = { text: String }

  copy(event) {
    event.preventDefault()
    navigator.clipboard.writeText(this.textValue).then(() => {
      const el = event.currentTarget
      const original = el.textContent
      el.textContent = "Copied"
      setTimeout(() => { el.textContent = original }, 1200)
    })
  }
}
