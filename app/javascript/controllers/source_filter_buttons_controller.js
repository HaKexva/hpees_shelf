import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["select", "button"]

  connect() {
    this.syncFromSelect()
  }

  pick(event) {
    event.preventDefault()
    const value = event.currentTarget?.dataset?.value ?? ""
    if (!this.hasSelectTarget) return
    this.selectTarget.value = value
    this.selectTarget.dispatchEvent(new Event("change", { bubbles: true }))
    this.syncFromSelect()
  }

  syncFromSelect() {
    const value = this.hasSelectTarget ? this.selectTarget.value : ""
    this.buttonTargets.forEach((btn) => {
      const active = (btn.dataset.value ?? "") === value
      btn.classList.toggle("bg-gray-900", active)
      btn.classList.toggle("text-white", active)
      btn.classList.toggle("border-gray-900", active)
      btn.classList.toggle("bg-white", !active)
      btn.classList.toggle("text-gray-700", !active)
      btn.classList.toggle("border-gray-300", !active)
    })
  }
}

