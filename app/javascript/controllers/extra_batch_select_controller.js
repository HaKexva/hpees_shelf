import { Controller } from "@hotwired/stimulus"

// 美化「（管理員）可額外連結的屆數」多選下拉
// - 使用隱藏的 <select multiple> 作為實際提交的欄位
// - 外層顯示摘要（已選幾個）與可展開的 checkbox 清單
export default class extends Controller {
  static targets = ["select", "panel", "summary", "checkbox"]

  connect() {
    this.updateSummary()
  }

  togglePanel() {
    if (!this.hasPanelTarget) return
    const hidden = this.panelTarget.classList.contains("hidden")
    this.panelTarget.classList.toggle("hidden", !hidden)
  }

  closePanel() {
    if (!this.hasPanelTarget) return
    this.panelTarget.classList.add("hidden")
  }

  toggleOption(event) {
    const checkbox = event.currentTarget
    const value = checkbox.value
    if (!this.hasSelectTarget) return

    Array.from(this.selectTarget.options).forEach((opt) => {
      if (opt.value === value) {
        opt.selected = checkbox.checked
      }
    })

    this.updateSummary()
  }

  clearAll() {
    if (this.hasSelectTarget) {
      Array.from(this.selectTarget.options).forEach((opt) => {
        opt.selected = false
      })
    }
    if (this.hasCheckboxTarget) {
      this.checkboxTargets.forEach((cb) => {
        cb.checked = false
      })
    }
    this.updateSummary()
  }

  updateSummary() {
    if (!this.hasSelectTarget || !this.hasSummaryTarget) return
    const selectedOptions = Array.from(this.selectTarget.options).filter(
      (opt) => opt.selected && opt.value
    )
    const count = selectedOptions.length

    if (count === 0) {
      this.summaryTarget.textContent = "尚未選擇屆數"
    } else {
      this.summaryTarget.textContent = `已選擇 ${count} 個屆數`
    }
  }
}

