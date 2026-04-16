import { Controller } from "@hotwired/stimulus"

const MIN_ROWS = 3

// 預設至少三列；僅當「每一列」都填滿（姓名＋屆數）時才新增下一列空白；離開某一列且該列已清空（blur）時刪除該列，總列數不得少於 3。
export default class extends Controller {
  static targets = ["tbody"]

  connect() {
    this.ensureMinimumRows()
  }

  handleInput() {
    this.maybeAppendWhenAllRowsComplete()
  }

  handleFocusOut(event) {
    const target = event.target
    const tr = target.closest?.("tr.new-personnel-row")
    if (!tr || !this.tbodyTarget.contains(tr)) return

    const next = event.relatedTarget
    if (next && tr.contains(next)) return

    const rows = Array.from(this.tbodyTarget.querySelectorAll("tr.new-personnel-row"))
    if (rows.length > MIN_ROWS && this.rowIsEmpty(tr)) {
      tr.remove()
    }
    this.ensureMinimumRows()
  }

  maybeAppendWhenAllRowsComplete() {
    const tbody = this.tbodyTarget
    const rows = Array.from(tbody.querySelectorAll("tr.new-personnel-row"))
    if (rows.length === 0) return
    if (!rows.every((r) => this.rowIsComplete(r))) return
    this.appendEmptyRow()
  }

  rowIsComplete(tr) {
    const nameInput = tr.querySelector("input[name='new_personnel[][name]']")
    const batchSelect = tr.querySelector("select[name='new_personnel[][batch_year_ids][]']")
    const name = nameInput?.value?.trim() ?? ""
    const selected = Array.from(batchSelect?.selectedOptions || []).map((o) => o.value).filter((v) => v.trim().length > 0)
    return name.length > 0 && selected.length > 0
  }

  rowIsEmpty(tr) {
    const nameInput = tr.querySelector("input[name='new_personnel[][name]']")
    const batchSelect = tr.querySelector("select[name='new_personnel[][batch_year_ids][]']")
    const name = nameInput?.value?.trim() ?? ""
    const selected = Array.from(batchSelect?.selectedOptions || []).map((o) => o.value).filter((v) => v.trim().length > 0)
    return name.length === 0 && selected.length === 0
  }

  ensureMinimumRows() {
    const tbody = this.tbodyTarget
    while (tbody.querySelectorAll("tr.new-personnel-row").length < MIN_ROWS) {
      this.appendEmptyRow()
    }
  }

  appendEmptyRow() {
    const tbody = this.tbodyTarget
    const templateRow = tbody.querySelector("tr.new-personnel-row")
    if (!templateRow) return

    const clone = templateRow.cloneNode(true)
    clone.querySelectorAll("input").forEach((input) => {
      input.value = ""
    })
    clone.querySelectorAll("select").forEach((select) => {
      select.selectedIndex = 0
    })
    tbody.appendChild(clone)
  }
}
