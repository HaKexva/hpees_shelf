import { Controller } from "@hotwired/stimulus"

// Validates ISBN-13 on blur (13 digits and check digit).
// Does NOT force any particular dash pattern, because different countries/publishers
// use different groupings. We only validate digits and leave formatting to the user.
export default class extends Controller {
  static targets = ["input", "message"]

  connect() {
    if (this.inputTarget.value.trim() !== "") this.validate()
  }

  validate() {
    const raw = this.inputTarget.value.trim()
    const digits = raw.replace(/\D/g, "")

    if (digits === "") {
      this.showMessage("請填寫 ISBN", false)
      this.setInputState(false)
      return
    }

    // Always normalize input value to pure digits (auto-delete all dashes/spaces/symbols)
    this.inputTarget.value = digits

    const valid = this.validIsbn13(digits)
    this.showMessage(valid ? "格式正確" : "應為 13 碼且校驗碼正確", valid)
    this.setInputState(valid)
  }

  validIsbn13(raw) {
    const digits = raw.replace(/\D/g, "").split("")
    if (digits.length !== 13) return false
    const weights = [1, 3, 1, 3, 1, 3, 1, 3, 1, 3, 1, 3]
    let sum = 0
    for (let i = 0; i < 12; i++) sum += parseInt(digits[i], 10) * weights[i]
    const check = (10 - (sum % 10)) % 10
    return check === parseInt(digits[12], 10)
  }

  showMessage(text, valid) {
    if (!this.hasMessageTarget) return
    this.messageTarget.textContent = text
    this.messageTarget.classList.toggle("text-green-600", valid === true)
    this.messageTarget.classList.toggle("text-red-600", valid === false)
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
    this.inputTarget.classList.toggle("border-red-400", !valid)
    this.inputTarget.classList.toggle("border-green-400", valid)
  }
}
