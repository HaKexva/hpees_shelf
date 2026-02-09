import { Controller } from "@hotwired/stimulus"

// 表單編輯後延遲自動送出（用於標籤規則等）
export default class extends Controller {
  static values = { delay: { type: Number, default: 2000 } }

  connect() {
    this.timeoutId = null
    this.boundSchedule = this.scheduleSubmit.bind(this)
    this.element.addEventListener("input", this.boundSchedule)
    this.element.addEventListener("change", this.boundSchedule)
    this.element.addEventListener("tag-rules-form:save", this.boundSchedule)
  }

  disconnect() {
    this.element.removeEventListener("input", this.boundSchedule)
    this.element.removeEventListener("change", this.boundSchedule)
    this.element.removeEventListener("tag-rules-form:save", this.boundSchedule)
    if (this.timeoutId) clearTimeout(this.timeoutId)
  }

  scheduleSubmit(event) {
    if (event.target.matches && event.target.matches('button[type="submit"], input[type="submit"], [data-turbo-method]')) return
    if (this.timeoutId) clearTimeout(this.timeoutId)
    const delay = event.type === "tag-rules-form:save" ? 0 : this.delayValue
    this.timeoutId = setTimeout(() => {
      this.timeoutId = null
      const input = document.createElement("input")
      input.type = "hidden"
      input.name = "auto_save"
      input.value = "1"
      this.element.appendChild(input)
      this.element.requestSubmit()
    }, delay)
  }
}
