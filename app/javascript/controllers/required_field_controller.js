import { Controller } from "@hotwired/stimulus"

// Simple required-field highlighter: on blur, if empty, turn border red.
// We deliberately do NOT reset to gray on non-empty, so we don't fight
// with other validators (like server-side errors or ISBN format checks).
export default class extends Controller {
  static targets = ["input"]

  blur(event) {
    const el = event.currentTarget
    if (!el) return

    const empty = el.value.trim() === ""
    if (empty) {
      el.classList.add("border-red-400")
      el.classList.remove("border-gray-400")
    }
  }
}

