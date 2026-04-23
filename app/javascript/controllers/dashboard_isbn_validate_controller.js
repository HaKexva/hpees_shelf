import { Controller } from "@hotwired/stimulus"

// Dashboard: on blur, validate ISBN format and check if a library book exists with same ISBN.
export default class extends Controller {
  static targets = ["input", "message", "duplicates"]
  static values = { url: String }

  validate() {
    const raw = this.inputTarget.value.trim()
    if (raw === "") {
      this.clearMessage()
      this.setInputState(null)
      this.renderDuplicates([])
      return
    }
    const url = this.buildValidateUrl(raw)
    this.messageTarget.textContent = "檢查中…"
    this.messageTarget.classList.remove("text-green-600", "text-red-600", "text-gray-500")
    this.messageTarget.classList.add("text-gray-500")
    this.messageTarget.classList.remove("hidden")
    this.setInputState(null)

    fetch(url, { headers: { Accept: "application/json" } })
      .then((res) => res.json())
      .then((data) => {
        const formatOk = data.has_13_digits && data.check_digit_valid
        if (!formatOk) {
          const parts = []
          if (!data.has_13_digits) parts.push("應為 13 碼")
          if (data.has_13_digits && !data.check_digit_valid) parts.push("校驗碼不正確")
          this.showMessage(parts.join("；"), false)
          this.setInputState(false)
          this.renderDuplicates([])
          this.setPendingBookId(null)
          return
        }

        if (!data.book_exists) {
          this.showMessage("格式正確，館內無此書", false)
          this.setInputState(false)
          this.renderDuplicates([])
          this.setPendingBookId(null)
          return
        }

        const allDuplicates = Array.isArray(data.duplicates) ? data.duplicates : []
        const actionType = this.currentActionType()

        // 借書時：只有「唯一一筆且該筆不可借」才提示；總數還有（多筆或有一筆可借）就還可以借
        if (actionType === "checkout" && allDuplicates.length === 1 && !allDuplicates[0].borrowable_for_checkout) {
          this.showMessage("格式正確，此本目前已借出，請稍後再試", false)
          this.setInputState(false)
          this.renderDuplicates([])
          this.setPendingBookId(null)
          return
        }

        this.showMessage("格式正確，館內有書", true)
        this.setInputState(true)

        const borrowable = allDuplicates.filter((b) => b.borrowable_for_checkout)

        if (actionType === "checkout") {
          // If multiple books share this ISBN (e.g. 上下冊), always require the user to pick the exact volume/copy.
          // Even if only one is currently borrowable, scanning should not silently select a different volume.
          if (allDuplicates.length >= 2) {
            this.renderDuplicates(allDuplicates)
            this.setPendingBookId(null)
            return
          }
          if (borrowable.length === 0) {
            this.showMessage("格式正確，此幾本目前皆已借出，請稍後再試", false)
            this.setInputState(false)
            this.renderDuplicates([])
            this.setPendingBookId(null)
            return
          }
          if (borrowable.length === 1) {
            // 可借選項只有一個：隱藏選單，直接帶入該本，避免跳出失誤
            this.renderDuplicates([])
            this.setPendingBookId(borrowable[0].id)
            return
          }
          // 可借選項兩個以上：顯示下拉（只列可借的）
          this.renderDuplicates(borrowable)
          this.setPendingBookId(null)
          return
        }

        // 還書：可顯示多筆冊別
        if (allDuplicates.length >= 2) {
          this.renderDuplicates(allDuplicates)
          this.setPendingBookId(null)
        } else {
          this.renderDuplicates([])
          this.setPendingBookId(null)
        }
      })
      .catch(() => {
        this.showMessage("無法驗證，請稍後再試", false)
        this.setInputState(null)
        this.renderDuplicates([])
      })
  }

  showMessage(text, valid) {
    if (!this.hasMessageTarget) return
    this.messageTarget.textContent = text
    this.messageTarget.classList.remove("text-green-600", "text-red-600", "text-gray-500")
    if (valid === true) this.messageTarget.classList.add("text-green-600")
    else if (valid === false) this.messageTarget.classList.add("text-red-600")
    else this.messageTarget.classList.add("text-gray-500")
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
    this.inputTarget.classList.toggle("border-red-400", valid === false)
    this.inputTarget.classList.toggle("border-green-400", valid === true)
  }

  currentActionType() {
    const form = this.element.closest("form")
    if (!form) return null
    const radio = form.querySelector("input[name='action_type']:checked")
    return radio ? radio.value : null
  }

  // 僅還書時：選完借閱人需重新驗證，讓黃色「選擇冊別」區塊可顯示。借書時不觸發，避免清空已選冊別。
  validateIfReturn() {
    if (this.currentActionType() === "return") this.validate()
  }

  buildValidateUrl(rawIsbn) {
    const form = this.element.closest("form")
    const params = new URLSearchParams()
    params.append("isbn", rawIsbn)

    if (form) {
      const hiddenUser    = form.querySelector("input[name='user_id']")
      const userSelect    = form.querySelector("select[name='user_id']")
      const idNumberInput = form.querySelector("input[name='id_number']")
      const actionType    = this.currentActionType()

      // 優先使用 hidden user_id（由 student-search controller 設定），
      // 再退而求其次使用任何 select 或學號欄位。
      if (hiddenUser && hiddenUser.value && hiddenUser.value !== "") {
        params.append("user_id", hiddenUser.value)
      } else if (userSelect && userSelect.value) {
        params.append("user_id", userSelect.value)
      } else if (idNumberInput && idNumberInput.value.trim() !== "") {
        params.append("id_number", idNumberInput.value.trim())
      }

      if (actionType) {
        params.append("action_type", actionType)
      }
    }

    return `${this.urlValue}?${params.toString()}`
  }

  setPendingBookId(id) {
    const form = this.element.closest("form")
    if (!form) return
    const hidden = form.querySelector("input[name='pending_book_id'][type='hidden']")
    if (id != null && id !== "") {
      // 單一選項：用 hidden 帶入
      if (!hidden) {
        const el = document.createElement("input")
        el.type = "hidden"
        el.name = "pending_book_id"
        form.appendChild(el)
        el.value = id
      } else {
        hidden.value = id
      }
    } else {
      // 多選項：由下拉選單提供值，移除 hidden 避免覆蓋使用者選擇
      if (hidden) hidden.remove()
    }
  }

  renderDuplicates(duplicates) {
    if (!this.hasDuplicatesTarget) return
    const container = this.duplicatesTarget
    const actionType = this.currentActionType()

    // 還書時：必須先選擇「借閱人」，才顯示重複書籍下拉
    if (actionType === "return") {
      const form = this.element.closest("form")
      if (form) {
        const hiddenUser    = form.querySelector("input[name='user_id']")
        const userSelect    = form.querySelector("select[name='user_id']")
        const idNumberInput = form.querySelector("input[name='id_number']")
        const hasUser =
          (hiddenUser && hiddenUser.value && hiddenUser.value !== "") ||
          (userSelect && userSelect.value && userSelect.value !== "") ||
          (idNumberInput && idNumberInput.value.trim() !== "")
        if (!hasUser) {
          container.innerHTML = ""
          container.classList.add("hidden")
          return
        }
      }
    }

    if (!Array.isArray(duplicates) || duplicates.length <= 1) {
      container.innerHTML = ""
      container.classList.add("hidden")
      return
    }

    container.innerHTML = `
      <div class="mt-2 rounded-md border border-amber-200 bg-amber-50 p-3 text-xs text-amber-900">
        <p class="font-medium mb-1">找到 <span class="font-bold">${duplicates.length}</span> 本符合此 ISBN（可能是上下冊或多冊），請先選擇冊別：</p>
        <label class="block text-xs font-medium text-gray-700 mb-1" for="inline_pending_book_select">選擇書籍（冊別）</label>
        <select
          id="inline_pending_book_select"
          name="pending_book_id"
          class="block w-full shadow-sm rounded-lg border border-gray-300 px-3 py-2 text-sm bg-white"
          required
        >
          <option value="">請選擇</option>
          ${duplicates
            .map((b) => {
              const parts = []
              if (b.batch_label) parts.push(b.batch_label)
              if (b.source_label) parts.push(b.source_label)
              if (b.call_number) parts.push(`登錄號 ${b.call_number}`)
              const meta = parts.length > 0 ? ` — ${parts.join("・")}` : ""
              const volume = b.volume ? ` 冊${b.volume}` : ""
              const edition = b.edition_part ? ` ${b.edition_part}` : ""
              // 借書時才顯示「可借 X 本」資訊；還書時不需要
              const copyInfo =
                actionType === "checkout" && typeof b.available_copies === "number"
                  ? `（可借 ${b.available_copies} 本）`
                  : actionType === "checkout" && b.borrowable_for_checkout
                    ? "（可借）"
                    : ""
              const label = `${this.escapeHtml(b.title || "（無書名）")}${edition}${volume}${meta} ${copyInfo}`
              return `<option value="${b.id}">${label}</option>`
            })
            .join("")}
        </select>
        <p class="mt-1 text-[11px] text-gray-500">選擇冊別後，再輸入借閱人並按下送出。</p>
      </div>
    `
    container.classList.remove("hidden")
  }

  escapeHtml(value) {
    if (value == null) return ""
    return String(value)
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;")
      .replace(/'/g, "&#39;")
  }
}
