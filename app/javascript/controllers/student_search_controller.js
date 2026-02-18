import { Controller } from "@hotwired/stimulus"

// Searchable dropdown: type to filter students by name or id_number, pick one.
export default class extends Controller {
  static targets = ["input", "hidden", "list", "item", "emptyHint"]

  static values = {
    placeholder: String
  }

  connect() {
    this.placeholder = this.placeholderValue || "搜尋姓名或學號…"
    this.closeBound = this.close.bind(this)
  }

  open() {
    this.listTarget.classList.remove("hidden")
    this.filter()
    document.addEventListener("click", this.closeBound)
  }

  close(event) {
    if (event && this.element.contains(event.target)) return
    this.listTarget.classList.add("hidden")
    document.removeEventListener("click", this.closeBound)
  }

  filter() {
    const q = (this.inputTarget.value || "").trim().toLowerCase()
    let visible = 0
    this.itemTargets.forEach((el) => {
      const text = (el.dataset.searchText || "").toLowerCase()
      const match = !q || text.includes(q)
      el.classList.toggle("hidden", !match)
      if (match) visible++
    })
    if (this.hasEmptyHintTarget) {
      this.emptyHintTarget.classList.toggle("hidden", visible > 0)
    }
  }

  select(event) {
    const item = event.currentTarget
    const id = item.dataset.userId
    const label = item.dataset.label || ""
    this.hiddenTarget.value = id || ""
    this.inputTarget.value = label
    this.inputTarget.placeholder = this.placeholder
    this.listTarget.classList.add("hidden")
    document.removeEventListener("click", this.closeBound)
  }

  clear() {
    this.hiddenTarget.value = ""
    this.inputTarget.value = ""
    this.inputTarget.placeholder = this.placeholder
    this.filter()
  }
}
