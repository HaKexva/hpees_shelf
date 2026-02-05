import { Controller } from "@hotwired/stimulus"

// Toggle between single batch-year select (students) and multi-select (admins)
export default class extends Controller {
  static targets = ["adminCheckbox", "primaryBatchRow", "extraBatchRow"]

  connect() {
    this.toggleBatchRows()
  }

  toggleBatchRows() {
    if (!this.hasAdminCheckboxTarget) return
    const checked = this.adminCheckboxTarget.checked
    if (this.hasPrimaryBatchRowTarget) {
      this.primaryBatchRowTarget.classList.toggle("hidden", checked)
    }
    if (this.hasExtraBatchRowTarget) {
      this.extraBatchRowTarget.classList.toggle("hidden", !checked)
      if (!checked) {
        const select = this.extraBatchRowTarget.querySelector("select")
        if (select) {
          Array.from(select.options).forEach((opt) => {
            opt.selected = false
          })
        }
      }
    }
  }
}

