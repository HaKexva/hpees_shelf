import { Controller } from "@hotwired/stimulus"

// 單選時依選中 radio 顯示對應內聯列；複選時依勾選的 checkbox 顯示對應內聯列（手動輸入 / 選單等）
export default class extends Controller {
  static targets = [ "sourceRadio", "sourceCheckbox", "inlineRow" ]

  connect() {
    this.toggleInlineRows()
  }

  toggleInlineRows() {
    let selectedValues = []
    if (this.hasSourceRadioTarget && this.sourceRadioTargets.length > 0) {
      const checked = this.sourceRadioTargets.find((r) => r.checked)
      if (checked) selectedValues = [ checked.value ]
    }
    if (selectedValues.length === 0 && this.hasSourceCheckboxTarget && this.sourceCheckboxTargets.length > 0) {
      selectedValues = this.sourceCheckboxTargets.filter((c) => c.checked).map((c) => c.value)
    }
    if (this.hasInlineRowTarget) {
      this.inlineRowTargets.forEach((row) => {
        const rowTag = row.dataset.bookFormInlineRowValue
        const isVisible = selectedValues.includes(rowTag)
        row.classList.toggle("hidden", !isVisible)
        const input = row.querySelector("input, select")
        if (input) input.disabled = !isVisible
      })
    }
  }
}
