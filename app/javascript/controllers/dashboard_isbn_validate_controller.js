import { Controller } from "@hotwired/stimulus"

// Dashboard: on blur, validate ISBN format and check if a library book exists with same ISBN.
export default class extends Controller {
  static targets = ["input", "message", "duplicates"]
  static values = { url: String }

  validate() {
    const raw = this.inputTarget.value.trim()
    if (raw === "") {
      this.showMessage("請填寫 ISBN", false)
      this.setInputState(false)
      return
    }
    const url = `${this.urlValue}?isbn=${encodeURIComponent(raw)}`
    this.messageTarget.textContent = "檢查中…"
    this.messageTarget.classList.remove("text-green-600", "text-red-600", "text-gray-500")
    this.messageTarget.classList.add("text-gray-500")
    this.messageTarget.classList.remove("hidden")
    this.setInputState(null)

    fetch(url, { headers: { Accept: "application/json" } })
      .then((res) => res.json())
      .then((data) => {
        const formatOk = data.has_13_digits && data.check_digit_valid
        if (!formatOk) {
          const parts = []
          if (!data.has_13_digits) parts.push("應為 13 碼")
          if (data.has_13_digits && !data.check_digit_valid) parts.push("校驗碼不正確")
          this.showMessage(parts.join("；"), false)
          this.setInputState(false)
          this.renderDuplicates([])
        } else if (data.book_exists) {
          this.showMessage("格式正確，館內有書", true)
          this.setInputState(true)
          this.renderDuplicates(data.duplicates || [])
        } else {
          this.showMessage("格式正確，館內無此書", false)
          this.setInputState(false)
          this.renderDuplicates([])
        }
      })
      .catch(() => {
        this.showMessage("無法驗證，請稍後再試", false)
        this.setInputState(null)
        this.renderDuplicates([])
      })
  }

  showMessage(text, valid) {
    if (!this.hasMessageTarget) return
    this.messageTarget.textContent = text
    this.messageTarget.classList.remove("text-green-600", "text-red-600", "text-gray-500")
    if (valid === true) this.messageTarget.classList.add("text-green-600")
    else if (valid === false) this.messageTarget.classList.add("text-red-600")
    else this.messageTarget.classList.add("text-gray-500")
    this.messageTarget.classList.remove("hidden")
  }

  clearMessage() {
    if (!this.hasMessageTarget) return
    this.messageTarget.textContent = ""
    this.messageTarget.classList.add("hidden")
  }

  setInputState(valid) {
    if (valid === null) {
      this.inputTarget.classList.remove("border-red-400", "border-green-400")
      return
    }
    this.inputTarget.classList.toggle("border-red-400", valid === false)
    this.inputTarget.classList.toggle("border-green-400", valid === true)
  }

  renderDuplicates(duplicates) {
    if (!this.hasDuplicatesTarget) return
    const container = this.duplicatesTarget
    if (!Array.isArray(duplicates) || duplicates.length <= 1) {
      container.innerHTML = ""
      container.classList.add("hidden")
      return
    }

    const itemsHtml = duplicates
      .map((b) => {
        const parts = []
        if (b.batch_label) parts.push(b.batch_label)
        if (b.source_label) parts.push(b.source_label)
        if (b.call_number) parts.push(`登錄號 ${b.call_number}`)
        const meta = parts.length > 0 ? ` — ${parts.join("・")}` : ""
        const volume = b.volume ? ` 冊${b.volume}` : ""
        const edition = b.edition_part ? ` ${b.edition_part}` : ""
        return `<li class="flex justify-between gap-2">
  <span class="truncate">${this.escapeHtml(b.title || "（無書名）")}${edition}${volume}${meta}</span>
</li>`
      })
      .join("")

    container.innerHTML = `
      <div class="mt-2 rounded-md border border-amber-200 bg-amber-50 p-3 text-xs text-amber-900">
        <p class="font-medium mb-1">有 <span class="font-bold">${duplicates.length}</span> 本相同 ISBN，稍後需選冊別：</p>
        <ul class="space-y-0.5">
          ${itemsHtml}
        </ul>
      </div>
    `
    container.classList.remove("hidden")
  }

  escapeHtml(value) {
    if (value == null) return ""
    return String(value)
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;")
      .replace(/'/g, "&#39;")
  }
}
