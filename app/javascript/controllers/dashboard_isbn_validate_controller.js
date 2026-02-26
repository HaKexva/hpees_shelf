import { Controller } from "@hotwired/stimulus"

// Dashboard: on blur, validate ISBN format and check if a library book exists with same ISBN.
export default class extends Controller {
  static targets = ["input", "message"]
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

    fetch(url, { headers: { "Accept": "application/json" } })
      .then((res) => res.json())
      .then((data) => {
        const formatOk = data.has_13_digits && data.check_digit_valid
        if (!formatOk) {
          const parts = []
          if (!data.has_13_digits) parts.push("應為 13 碼")
          if (data.has_13_digits && !data.check_digit_valid) parts.push("校驗碼不正確")
          this.showMessage(parts.join("；"), false)
          this.setInputState(false)
        } else if (data.book_exists) {
          this.showMessage("格式正確，館內有書", true)
          this.setInputState(true)
        } else {
          this.showMessage("格式正確，館內無此書", false)
          this.setInputState(false)
        }
      })
      .catch(() => {
        this.showMessage("無法驗證，請稍後再試", false)
        this.setInputState(null)
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
}
