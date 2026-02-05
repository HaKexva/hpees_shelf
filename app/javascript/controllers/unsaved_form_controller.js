import { Controller } from "@hotwired/stimulus"

// Warns when leaving a form page with unsaved changes (browser close/refresh or in-app navigation).
export default class extends Controller {
  static values = {
    message: { type: String, default: "確定要離開嗎？您的變更將不會被儲存。" }
  }

  connect() {
    this.dirty = false
    this.boundBeforeUnload = this._beforeUnload.bind(this)
    this.boundBeforeVisit = this._beforeVisit.bind(this)
    this.boundMarkDirty = this._markDirty.bind(this)
    this.boundClearDirty = this._clearDirty.bind(this)

    this.element.addEventListener("input", this.boundMarkDirty)
    this.element.addEventListener("change", this.boundMarkDirty)
    this.element.addEventListener("submit", this.boundClearDirty)
    window.addEventListener("beforeunload", this.boundBeforeUnload)
    document.addEventListener("turbo:before-visit", this.boundBeforeVisit)
  }

  disconnect() {
    this.element.removeEventListener("input", this.boundMarkDirty)
    this.element.removeEventListener("change", this.boundMarkDirty)
    this.element.removeEventListener("submit", this.boundClearDirty)
    window.removeEventListener("beforeunload", this.boundBeforeUnload)
    document.removeEventListener("turbo:before-visit", this.boundBeforeVisit)
  }

  _markDirty() {
    this.dirty = true
  }

  _clearDirty() {
    this.dirty = false
  }

  _beforeUnload(event) {
    if (this.dirty) {
      event.preventDefault()
      event.returnValue = ""
    }
  }

  _beforeVisit(event) {
    if (this.dirty && !window.confirm(this.messageValue)) {
      event.preventDefault()
    }
  }
}
