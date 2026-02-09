import { Controller } from "@hotwired/stimulus"

// 標籤規則表單：新增/刪除組別、新增/刪除選項皆在表單內操作，並觸發自動儲存
export default class extends Controller {
  static targets = ["groupsContainer", "groupTemplate", "optionRowTemplate"]

  connect() {
    this.element.addEventListener("submit", this._reindexBeforeSubmit.bind(this), { capture: true })
  }

  disconnect() {
    this.element.removeEventListener("submit", this._reindexBeforeSubmit.bind(this), { capture: true })
  }

  _reindexBeforeSubmit() {
    const container = this.groupsContainerTarget
    const groups = container.querySelectorAll(".tag-rule-group")
    groups.forEach((group, newGi) => {
      const oldGi = group.getAttribute("data-group-index")
      if (oldGi === null) return
      const groupPrefix = "groups[" + oldGi + "]"
      const newPrefix = "groups[" + newGi + "]"
      group.setAttribute("data-group-index", String(newGi))
      group.querySelectorAll("[data-group-index]").forEach((el) => el.setAttribute("data-group-index", String(newGi)))
      group.querySelectorAll("input, select").forEach((el) => {
        const n = el.getAttribute("name")
        if (n && n.startsWith(groupPrefix)) {
          el.setAttribute("name", newPrefix + n.slice(groupPrefix.length))
        }
      })
      const tbody = group.querySelector("tbody")
      if (!tbody) return
      const rows = Array.from(tbody.querySelectorAll("tr"))
      rows.forEach((row, newOi) => {
        const first = row.querySelector('input[name*="[options]["], select[name*="[options]["]')
        if (!first || !first.name) return
        const m = first.name.match(/\[options\]\[(\d+)\]/)
        if (!m) return
        const oldOi = m[1]
        if (oldOi === String(newOi)) return
        row.querySelectorAll("input, select").forEach((el) => {
          const n = el.getAttribute("name")
          if (n && n.includes("[options][" + oldOi + "]")) {
            el.setAttribute("name", n.replace("[options][" + oldOi + "]", "[options][" + newOi + "]"))
          }
        })
      })
    })
  }

  addGroup(event) {
    event.preventDefault()
    event.stopPropagation()
    event.stopImmediatePropagation()
    const container = this.groupsContainerTarget
    const template = this.groupTemplateTarget
    const groups = container.querySelectorAll(".tag-rule-group")
    const indices = Array.from(groups).map((el) => parseInt(el.getAttribute("data-group-index"), 10)).filter((n) => !Number.isNaN(n))
    const nextIndex = indices.length === 0 ? 0 : Math.max(...indices) + 1
    const clone = template.content.cloneNode(true)
    this._replaceInNode(clone, "__GI__", nextIndex)
    container.appendChild(clone)
    this._reindexBeforeSubmit()
    this._triggerAutoSave()
  }

  deleteGroup(event) {
    event.preventDefault()
    const btn = event.currentTarget
    if (!window.confirm("確定要刪除此組別？")) return
    const group = btn.closest(".tag-rule-group")
    if (group) group.remove()
    this._reindexBeforeSubmit()
    this._triggerAutoSave()
  }

  addOption(event) {
    event.preventDefault()
    event.stopPropagation()
    event.stopImmediatePropagation()
    const btn = event.currentTarget
    const group = btn.closest(".tag-rule-group")
    if (!group || !this.hasOptionRowTemplateTarget) return
    const gi = parseInt(btn.getAttribute("data-group-index"), 10)
    if (Number.isNaN(gi) || gi < 0) return
    const table = group.querySelector("table")
    const tbody = table ? (table.tBodies[0] || table.querySelector("tbody")) : null
    if (!tbody) return
    const optionIndices = Array.from(tbody.querySelectorAll("tr")).map((row) => {
      const input = row.querySelector('input[name*="[options]["]')
      if (!input || !input.name) return -1
      const m = input.name.match(/\[options\]\[(\d+)\]/)
      return m ? parseInt(m[1], 10) : -1
    }).filter((n) => n >= 0)
    const nextOi = optionIndices.length === 0 ? 0 : Math.max(...optionIndices) + 1
    const clone = this.optionRowTemplateTarget.content.cloneNode(true)
    this._replaceInNode(clone, "__GI__", gi)
    this._replaceInNode(clone, "__OI__", nextOi)
    tbody.appendChild(clone)
    this._reindexBeforeSubmit()
    this._triggerAutoSave()
  }

  deleteOption(event) {
    event.preventDefault()
    const btn = event.currentTarget
    const row = btn.closest("tr")
    if (row && window.confirm("確定刪除此選項？")) {
      row.remove()
      this._reindexBeforeSubmit()
      this._triggerAutoSave()
    }
  }

  _replaceInNode(node, search, value) {
    const str = String(value)
    if (node.nodeType === Node.TEXT_NODE) {
      node.textContent = node.textContent.replaceAll(search, str)
      return
    }
    if (node.nodeType === Node.ELEMENT_NODE) {
      if (node.hasAttribute?.("name")) node.setAttribute("name", node.getAttribute("name").replaceAll(search, str))
      if (node.hasAttribute?.("id")) node.setAttribute("id", node.getAttribute("id").replaceAll(search, str))
      if (node.hasAttribute?.("data-group-index")) node.setAttribute("data-group-index", str)
      node.childNodes?.forEach((child) => this._replaceInNode(child, search, value))
    }
  }

  _triggerAutoSave() {
    this.element.dispatchEvent(new Event("tag-rules-form:save", { bubbles: true }))
  }
}
