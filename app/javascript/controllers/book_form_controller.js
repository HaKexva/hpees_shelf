import { Controller } from "@hotwired/stimulus"

// Toggles visibility of the teacher dropdown when book source is "老師的書" (owned_by_teacher)
export default class extends Controller {
  static targets = ["sourceSelect", "teacherField"]

  connect() {
    this.toggleTeacherField()
  }

  toggleTeacherField() {
    if (!this.hasSourceSelectTarget || !this.hasTeacherFieldTarget) return
    const isTeacher = this.sourceSelectTarget.value === "owned_by_teacher"
    this.teacherFieldTarget.style.display = isTeacher ? "" : "none"
  }
}
