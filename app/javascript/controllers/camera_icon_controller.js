import { Controller } from "@hotwired/stimulus"

// Controls visibility and click behavior of camera icon buttons.
// Shows on touch/mobile devices with camera API, and opens camera to scan ISBN barcodes.
export default class extends Controller {
  static targets = ["button"]

  connect() {
    // Start hidden; we’ll unhide only if we detect a real camera device.
    this.buttonTargets.forEach((el) => el.classList.add("hidden"))
    this.#init()
  }

  async open(event) {
    event.preventDefault()
    const input = this.#findIsbnInput(event.currentTarget)
    if (!input) return

    // Always open the camera overlay; it will use BarcodeDetector when available.
    await this.#scanWithCameraOverlay(input)
  }

  async #init() {
    const show = await this.#hasVideoInput()
    this.buttonTargets.forEach((el) => {
      el.classList.toggle("hidden", !show)
    })
  }

  async #hasVideoInput() {
    if (
      typeof navigator === "undefined" ||
      !navigator.mediaDevices ||
      typeof navigator.mediaDevices.enumerateDevices !== "function"
    ) {
      return false
    }

    try {
      const devices = await navigator.mediaDevices.enumerateDevices()
      // Show icon on any device that reports at least one video input (front or back camera / webcam).
      return devices.some((d) => d.kind === "videoinput")
    } catch (e) {
      console.warn("Unable to enumerate media devices", e)
      return false
    }
  }

  async #scanWithBarcodeDetector(input) {
    // ISBN-13 實際上是以 EAN-13 條碼格式編碼，這裡不用額外的 isbn_13 格式。
    const detector = new window.BarcodeDetector({ formats: ["ean_13", "ean_8"] })
    const stream = await navigator.mediaDevices.getUserMedia({ video: { facingMode: "environment" } })
    const video = document.createElement("video")
    video.srcObject = stream
    await video.play()

    const result = await this.#detectOnce(detector, video)

    stream.getTracks().forEach((t) => t.stop())
    video.remove()

    if (result) {
      input.value = result
      input.dispatchEvent(new Event("input", { bubbles: true }))
      input.dispatchEvent(new Event("change", { bubbles: true }))
    }
  }

  async #scanWithCameraOverlay(input) {
    const overlay = document.createElement("div")
    overlay.className =
      "fixed inset-0 z-[100] flex flex-col items-center justify-center bg-black/80 text-white"

    const video = document.createElement("video")
    video.autoplay = true
    video.playsInline = true
    video.className = "w-full max-w-md rounded-lg border border-white/20"

    const hint = document.createElement("p")
    hint.className = "mt-4 text-sm text-center px-4"
    hint.textContent = "請將書本條碼置於畫面中央，偵測到後會自動填入 ISBN。"

    const closeBtn = document.createElement("button")
    closeBtn.className =
      "mt-4 inline-flex items-center justify-center rounded-full px-4 py-2 bg-white text-black text-sm font-medium"
    closeBtn.type = "button"
    closeBtn.textContent = "關閉"

    overlay.appendChild(video)
    overlay.appendChild(hint)
    overlay.appendChild(closeBtn)
    document.body.appendChild(overlay)

    let stopped = false
    let stream = null

    const stopAndClose = () => {
      if (stopped) return
      stopped = true
      if (stream) {
        stream.getTracks().forEach((t) => t.stop())
      }
      overlay.remove()
    }

    closeBtn.addEventListener("click", (e) => {
      e.preventDefault()
      e.stopPropagation()
      stopAndClose()
    })

    document.addEventListener(
      "keydown",
      (e) => {
        if (e.key === "Escape") stopAndClose()
      },
      { once: true }
    )

    try {
      stream = await navigator.mediaDevices.getUserMedia({ video: { facingMode: "environment" } })
    } catch (e) {
      console.warn("getUserMedia failed", e)
      alert("無法開啟相機，請確認瀏覽器權限或改用內建相機 App 掃描後貼上。")
      stopAndClose()
      return
    }

    video.srcObject = stream

    let detector = null
    if ("BarcodeDetector" in window) {
      try {
        detector = new window.BarcodeDetector({ formats: ["ean_13", "ean_8"] })
      } catch (e) {
        console.warn("BarcodeDetector construct failed", e)
        detector = null
      }
    }

    const loop = async () => {
      if (stopped) return
      if (detector) {
        const code = await this.#detectOnce(detector, video)
        if (code) {
          input.value = code
          input.dispatchEvent(new Event("input", { bubbles: true }))
          input.dispatchEvent(new Event("change", { bubbles: true }))
          stopAndClose()
          return
        }
      }
      requestAnimationFrame(loop)
    }

    requestAnimationFrame(loop)
  }

  async #detectOnce(detector, video) {
    if (video.readyState < 2) {
      await new Promise((resolve) => {
        video.onloadeddata = resolve
      })
    }
    const bitmap = await createImageBitmap(video)
    try {
      const barcodes = await detector.detect(bitmap)
      if (barcodes && barcodes.length > 0) {
        const raw = barcodes[0].rawValue || ""
        return raw.replace(/\D/g, "")
      }
      return null
    } finally {
      bitmap.close && bitmap.close()
    }
  }

  #findIsbnInput(buttonEl) {
    // Look for a sibling text input in the same group
    const wrapper = buttonEl.closest("div")
    if (!wrapper) return null
    return wrapper.querySelector("input[type='text'], input[type='search'], input[type='tel']")
  }
}


