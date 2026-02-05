import { Controller } from "@hotwired/stimulus"

// 選「老師的書」時才顯示名字欄位
export default class extends Controller {
  static targets = ["teacherRadio", "teacherNameRow", "teacherNameInput"]

  connect() {
    this.toggleTeacherName()
  }

  toggleTeacherName() {
    if (!this.hasTeacherRadioTarget || !this.hasTeacherNameRowTarget) return
    const checked = this.teacherRadioTarget.checked
    this.teacherNameRowTarget.classList.toggle("hidden", !checked)
    if (this.hasTeacherNameInputTarget) {
      this.teacherNameInputTarget.disabled = !checked
      if (!checked) this.teacherNameInputTarget.value = ""
    }
  }
}
