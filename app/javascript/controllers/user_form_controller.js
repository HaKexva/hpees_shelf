import { Controller } from "@hotwired/stimulus"

// Toggle between single batch-year select (students) and multi-select (admins)
export default class extends Controller {
  static targets = ["adminCheckbox", "primaryBatchRow", "extraBatchRow", "adminEmailRow"]

  connect() {
    this.toggleBatchRows()
  }

  toggleBatchRows() {
    if (!this.hasAdminCheckboxTarget) return
    const checked = this.adminCheckboxTarget.checked
    if (this.hasPrimaryBatchRowTarget) {
      this.primaryBatchRowTarget.classList.toggle("hidden", checked)
      const select = this.primaryBatchRowTarget.querySelector(
        "select[name='user[batch_year_id]']"
      )
      if (select) {
        if (checked) {
          // When switching to admin, keep current 屆數 by syncing it into the multi-select.
          select.removeAttribute("required")
          const currentValue = select.value
          if (currentValue && this.hasExtraBatchRowTarget) {
            const checkbox = this.extraBatchRowTarget.querySelector(
              `input[data-extra-batch-select-target="checkbox"][value="${currentValue}"]`
            )
            if (checkbox && !checkbox.checked) {
              checkbox.checked = true
              checkbox.dispatchEvent(new Event("change", { bubbles: true }))
            }
          }
        } else {
          select.setAttribute("required", "required")
        }
      }
    }
    if (this.hasExtraBatchRowTarget) {
      this.extraBatchRowTarget.classList.toggle("hidden", !checked)
      // 管理員屆數：勾選「管理員」時，自動展開多選面板，方便立即選屆數
      if (checked) {
        const panel = this.extraBatchRowTarget.querySelector(
          "[data-extra-batch-select-target='panel']"
        )
        if (panel) {
          panel.classList.remove("hidden")
        }
      }
    }

    if (this.hasAdminEmailRowTarget) {
      this.adminEmailRowTarget.classList.toggle("hidden", !checked)
    }
  }
}

