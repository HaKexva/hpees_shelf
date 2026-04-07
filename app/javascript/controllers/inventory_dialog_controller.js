import { Controller } from "@hotwired/stimulus"

// Opens the inventory PDF export dialog and syncs sort options based on source selection.
export default class extends Controller {
  static targets = ["dialog", "sourceSelect", "sortSelect"]

  open(e) {
    e?.preventDefault()
    const dlg = this.dialogTarget
    if (!dlg) return

    try {
      if (typeof dlg.showModal === "function") {
        dlg.showModal()
      } else {
        dlg.setAttribute("open", "")
      }
    } catch (_err) {
      dlg.setAttribute("open", "")
    }

    this.syncSortOptions()
  }

  close(e) {
    e?.preventDefault()
    const dlg = this.dialogTarget
    if (!dlg) return
    try {
      if (typeof dlg.close === "function") {
        dlg.close()
      } else {
        dlg.removeAttribute("open")
      }
    } catch (_err) {
      dlg.removeAttribute("open")
    }
  }

  closeIfBackdrop(e) {
    const dlg = this.dialogTarget
    if (!dlg) return
    if (e.target === dlg) this.close(e)
  }

  syncSortOptions() {
    if (!this.hasSourceSelectTarget || !this.hasSortSelectTarget) return
    const v = this.sourceSelectTarget.value
    const specific = v && v !== "all" && v !== "teachers_all"

    Array.from(this.sortSelectTarget.options).forEach((opt) => {
      if (opt.value === "source") {
        opt.disabled = specific
        opt.hidden = specific
      }
    })

    if (specific && this.sortSelectTarget.value === "source") {
      this.sortSelectTarget.value = "isbn"
    }
  }
}

