import { Controller } from "@hotwired/stimulus"

// Toggles visibility of fields that depend on book source
export default class extends Controller {
  static targets = ["sourceSelect", "teacherField", "callNumberField", "totalField"]

  connect() {
    this.toggleFields()
  }

  toggleFields() {
    if (!this.hasSourceSelectTarget) return
    const isTeacher = this.sourceSelectTarget.value === "owned_by_teacher"
    const isLibrary = this.sourceSelectTarget.value === "owned_by_library"

    if (this.hasTeacherFieldTarget) {
      this.teacherFieldTarget.style.display = isTeacher ? "" : "none"
    }

    if (this.hasCallNumberFieldTarget) {
      this.callNumberFieldTarget.style.display = isLibrary ? "" : "none"
    }

    // 圖書館館藏：總數固定為 1，不需要顯示欄位
    if (this.hasTotalFieldTarget) {
      this.totalFieldTarget.style.display = isLibrary ? "none" : ""
    }
  }
}
