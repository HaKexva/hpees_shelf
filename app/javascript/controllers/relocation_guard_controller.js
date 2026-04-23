import { Controller } from "@hotwired/stimulus"

// Disables "儲存屆數指定" until:
// - the current form state has been saved as a draft, and
// - each grade has exactly one teacher checked.
//
// Any change after saving draft marks the form "dirty" again.
export default class extends Controller {
  static targets = ["commitButton", "hint"]
  static values = {
    draftSaved: Boolean,
    batchYearGradeMap: Object,
    currentUserId: Number,
    superadmin: Boolean
  }

  connect() {
    this.dirty = false
    this.updateGradeTeacherVisibility()
    this.update()
  }

  onChange(event) {
    this.enforceOnlySelfCheck(event)
    this.enforceSingleGradeTeacherCheck(event)
    this.syncTeacherBatchesFromGradeTeacherPick(event)
    this.dirty = true
    this.updateGradeTeacherVisibility()
    this.update()
  }

  update() {
    const draftOk = this.draftSavedValue && !this.dirty
    const gradesOk = this.allGradesHaveExactlyOneTeacher()
    const eligibleOk = this.allCheckedTeachersEligibleForGrade()
    const ok = draftOk && gradesOk && eligibleOk

    if (this.hasCommitButtonTarget) {
      this.commitButtonTarget.disabled = !ok
      this.commitButtonTarget.classList.toggle("opacity-50", !ok)
      this.commitButtonTarget.classList.toggle("cursor-not-allowed", !ok)
    }

    if (this.hasHintTarget) {
      const msgs = []
      if (!this.draftSavedValue) msgs.push("請先按「儲存草稿」。")
      else if (this.dirty) msgs.push("內容已變更，請重新儲存草稿。")
      if (!gradesOk) msgs.push("每個年級需勾選 1 位老師。")
      if (!eligibleOk) msgs.push("負責老師需有任教該年級（下方複選需包含該年級）。")
      this.hintTarget.textContent = msgs.join(" ")
      this.hintTarget.classList.toggle("hidden", ok)
    }
  }

  allGradesHaveExactlyOneTeacher() {
    for (let g = 1; g <= 6; g++) {
      const checked = this.element.querySelectorAll(
        `input[type="checkbox"][name="grade_teacher_ids[${g}]"]:checked`
      )
      if (checked.length !== 1) return false
    }
    return true
  }

  enforceSingleGradeTeacherCheck(event) {
    const el = event?.target
    if (!el) return
    if (el.tagName !== "INPUT") return
    if (el.type !== "checkbox") return
    const name = el.getAttribute("name") || ""
    const m = name.match(/^grade_teacher_ids\[(\d+)\]$/)
    if (!m) return
    if (!el.checked) return
    const grade = m[1]
    this.element
      .querySelectorAll(`input[type="checkbox"][name="grade_teacher_ids[${grade}]"]`)
      .forEach((cb) => {
        if (cb !== el) cb.checked = false
      })
  }

  syncTeacherBatchesFromGradeTeacherPick(event) {
    const el = event?.target
    if (!el) return
    if (el.tagName !== "INPUT") return
    if (el.type !== "checkbox") return
    const name = el.getAttribute("name") || ""
    const m = name.match(/^grade_teacher_ids\[(\d+)\]$/)
    if (!m) return
    if (!el.checked) return

    const grade = Number(m[1] || "0")
    const teacherId = String(el.value || "").trim()
    if (!grade || teacherId === "") return

    if (this.teacherCoversGrade(teacherId, grade)) return

    const select = this.element.querySelector(
      `select[name="teacher_batch_year_ids[${teacherId}][]"]`
    )
    if (!select) return

    const map = this.batchYearGradeMapValue || {}
    const candidateOpt = Array.from(select.options).find(
      (opt) => opt.value && map[String(opt.value)] === grade
    )
    if (!candidateOpt) return

    candidateOpt.selected = true

    const wrapper = select.closest("[data-controller~='extra-batch-select']")
    const cb = wrapper?.querySelector?.(`input[type="checkbox"][value="${candidateOpt.value}"]`)
    if (cb && !cb.checked) {
      cb.checked = true
      cb.dispatchEvent(new Event("change", { bubbles: true }))
    } else {
      select.dispatchEvent(new Event("change", { bubbles: true }))
    }
  }

  enforceOnlySelfCheck(event) {
    const el = event?.target
    if (!el) return
    if (el.tagName !== "INPUT") return
    if (el.type !== "checkbox") return
    const name = el.getAttribute("name") || ""
    const m = name.match(/^grade_teacher_ids\[(\d+)\]$/)
    if (!m) return
    if (this.superadminValue) return
    const teacherId = Number(el.value || "0")
    if (!teacherId) return
    if (teacherId !== this.currentUserIdValue) {
      el.checked = false
      alert("您只能勾選自己的年級負責老師。")
    }
  }

  allCheckedTeachersEligibleForGrade() {
    for (let g = 1; g <= 6; g++) {
      const checked = this.element.querySelector(
        `input[type="checkbox"][name="grade_teacher_ids[${g}]"]:checked`
      )
      if (!checked) continue
      const teacherId = checked.value
      if (!this.teacherCoversGrade(teacherId, g)) return false
    }
    return true
  }

  teacherCoversGrade(teacherId, grade) {
    const select = this.element.querySelector(
      `select[name="teacher_batch_year_ids[${teacherId}][]"]`
    )
    const selectedIds = Array.from(select?.selectedOptions || [])
      .map((o) => o.value)
      .filter((v) => v && String(v).trim() !== "")

    if (selectedIds.length === 0) return false

    const map = this.batchYearGradeMapValue || {}
    const grades = selectedIds
      .map((id) => Number(map[String(id)]))
      .filter((g) => Number.isFinite(g))
    return grades.includes(grade)
  }

  teacherBatchLabelsForGrade(teacherId, grade) {
    const select = this.element.querySelector(
      `select[name="teacher_batch_year_ids[${teacherId}][]"]`
    )
    const map = this.batchYearGradeMapValue || {}
    const selected = Array.from(select?.selectedOptions || []).filter(
      (o) => o.value && String(o.value).trim() !== ""
    )
    return selected
      .filter((o) => Number(map[String(o.value)]) === grade)
      .map((o) => (o.textContent || "").trim())
      .filter((s) => s.length > 0)
  }

  updateGradeTeacherVisibility() {
    const labels = this.element.querySelectorAll("[data-relocation-guard-grade-teacher-label]")
    labels.forEach((label) => {
      const grade = Number(label.getAttribute("data-grade") || "0")
      const teacherId = label.getAttribute("data-teacher-id") || ""
      if (!grade || !teacherId) return
      const batchLabels = this.teacherBatchLabelsForGrade(teacherId, grade)
      const ok = batchLabels.length > 0
      label.classList.toggle("hidden", !ok)
      label.style.display = ok ? "inline-flex" : "none"
      if (!ok) {
        const cb = label.querySelector("input[type='checkbox']")
        if (cb && cb.checked) cb.checked = false
      }
    })
  }
}

