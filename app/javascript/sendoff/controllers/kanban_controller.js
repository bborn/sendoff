import { Controller } from "@hotwired/stimulus"
import Sortable from "sortablejs"

// Pipeline kanban: SortableJS drag-drop between stage columns, PATCH to
// move_pipeline_entry_path on drop (reverting on a 422), plus client-side
// text filtering of cards and a "show duds" toggle.
export default class extends Controller {
  static targets = ["list", "card", "search", "column", "dudsToggle"]
  static values = { moveUrl: String }

  connect() {
    this.sortables = this.listTargets.map((list) =>
      Sortable.create(list, {
        group: "pipeline",
        animation: 150,
        ghostClass: "drag-ghost",
        onEnd: (evt) => this.onDrop(evt)
      })
    )

    if (this.hasSearchTarget && this.searchTarget.value) {
      this.filter()
    }
  }

  disconnect() {
    if (this.sortables) {
      this.sortables.forEach((s) => s.destroy())
      this.sortables = null
    }
  }

  // Persist a card move to the new column's stage. Revert the DOM on failure.
  onDrop(evt) {
    const card = evt.item
    const list = evt.to
    const stage = list.dataset.stage
    const id = card.dataset.pipelineEntryId
    if (!id || !stage) return

    const url = this.moveUrlValue.replace("__ID__", id)

    fetch(url, {
      method: "PATCH",
      headers: {
        "Content-Type": "application/json",
        "X-CSRF-Token": this.csrfToken(),
        "Accept": "application/json"
      },
      body: JSON.stringify({ stage })
    })
      .then((response) => {
        if (!response.ok) this.revert(evt)
      })
      .catch(() => this.revert(evt))
  }

  // Return the card to its original column/position.
  revert(evt) {
    const { from, item, oldIndex } = evt
    const reference = from.children[oldIndex] || null
    from.insertBefore(item, reference)
  }

  // Client-side filter of cards by the search input value.
  filter() {
    const term = (this.hasSearchTarget ? this.searchTarget.value : "").trim().toLowerCase()
    this.cardTargets.forEach((card) => {
      const haystack = card.dataset.search || ""
      card.hidden = term.length > 0 && !haystack.includes(term)
    })
  }

  // Toggle visibility of the dud column without a round-trip. Reloads with the
  // server-side toggle so the column is present when shown.
  toggleDuds(event) {
    event.preventDefault()
    const url = new URL(window.location.href)
    if (url.searchParams.has("duds")) {
      url.searchParams.delete("duds")
    } else {
      url.searchParams.set("duds", "1")
    }
    window.location.href = url.toString()
  }

  csrfToken() {
    const el = document.querySelector("meta[name='csrf-token']")
    return el ? el.content : ""
  }
}
