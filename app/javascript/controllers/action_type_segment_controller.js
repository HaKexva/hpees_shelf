import { Controller } from "@hotwired/stimulus"

/** Sliding 借書 / 還書 segment control (pattern from accounting_ruby budgets_kind). */
export default class extends Controller {
  static targets = ["track", "indicator", "button", "radio", "panel"]

  connect() {
    this._onResize = () => this.#positionIndicator()
    window.addEventListener("resize", this._onResize)
    this.sync()
    requestAnimationFrame(() => this.#positionIndicator())
  }

  disconnect() {
    window.removeEventListener("resize", this._onResize)
  }

  pick(event) {
    const value = event.currentTarget?.dataset?.actionTypeValue
    if (!value) return

    this.radioTargets.forEach((radio) => {
      radio.checked = radio.value === value
    })
    this.sync()
  }

  sync() {
    const value = this.#currentValue()

    this.radioTargets.forEach((radio) => {
      if (radio.checked && radio.value !== value) radio.checked = false
    })
    const activeRadio = this.radioTargets.find((r) => r.value === value)
    if (activeRadio) activeRadio.checked = true

    this.buttonTargets.forEach((button) => {
      const active = button.dataset.actionTypeValue === value
      button.setAttribute("aria-pressed", active ? "true" : "false")
      button.classList.toggle("text-white", active)
      button.classList.toggle("text-gray-600", !active)
    })

    if (this.hasPanelTarget) {
      const checkout = value === "checkout"
      this.panelTarget.classList.toggle("bg-blue-50", checkout)
      this.panelTarget.classList.toggle("border-blue-200", checkout)
      this.panelTarget.classList.toggle("bg-emerald-50", !checkout)
      this.panelTarget.classList.toggle("border-emerald-200", !checkout)
      this.panelTarget.classList.toggle("bg-white", false)
      this.panelTarget.classList.toggle("border-gray-100", false)
    }

    if (this.hasIndicatorTarget) {
      const checkout = value === "checkout"
      this.indicatorTarget.classList.toggle("bg-blue-600", checkout)
      this.indicatorTarget.classList.toggle("bg-emerald-600", !checkout)
    }

    this.#positionIndicator()

    const checked = this.radioTargets.find((r) => r.checked)
    if (checked) checked.dispatchEvent(new Event("change", { bubbles: true }))
  }

  #currentValue() {
    const checked = this.radioTargets.find((r) => r.checked)
    return checked?.value === "return" ? "return" : "checkout"
  }

  #positionIndicator() {
    if (!this.hasIndicatorTarget || !this.hasTrackTarget) return

    const value = this.#currentValue()
    const active = this.buttonTargets.find((b) => b.dataset.actionTypeValue === value)
    if (!active) return

    const trackRect = this.trackTarget.getBoundingClientRect()
    const buttonRect = active.getBoundingClientRect()
    const left = buttonRect.left - trackRect.left

    this.indicatorTarget.style.width = `${buttonRect.width}px`
    this.indicatorTarget.style.transform = `translateX(${left}px)`
    this.indicatorTarget.style.opacity = "1"
  }
}
