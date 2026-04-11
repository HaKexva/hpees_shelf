import { Controller } from "@hotwired/stimulus"

// Auto-removes a success flash after a delay (borrow/return scan UX). Use only on notice elements, not alerts.
export default class extends Controller {
  static values = {
    delay: { type: Number, default: 3000 }
  }

  connect() {
    this.timeoutId = window.setTimeout(() => {
      this.element.remove()
    }, this.delayValue)
  }

  disconnect() {
    if (this.timeoutId) window.clearTimeout(this.timeoutId)
  }
}
