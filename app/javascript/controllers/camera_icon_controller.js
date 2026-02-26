import { Controller } from "@hotwired/stimulus"
import { BrowserMultiFormatReader, BarcodeFormat, DecodeHintType } from "@zxing/browser"

// Controls visibility and click behavior of camera icon buttons.
// Shows on devices with a camera, and opens camera to scan ISBN barcodes.
// Uses ZXing (BrowserMultiFormatReader) so it works on Safari & Chrome (only requires getUserMedia).
export default class extends Controller {
  static targets = ["button"]

  connect() {
    // Start hidden; we’ll unhide only if we detect a real camera device.
    this.buttonTargets.forEach((el) => el.classList.add("hidden"))
    this.init()
  }

  async open(event) {
    event.preventDefault()
    const input = this.findIsbnInput(event.currentTarget)
    if (!input) return

    // Always open the camera overlay and let ZXing handle barcode decoding.
    await this.scanWithCameraOverlay(input)
  }

  async init() {
    const show = await this.hasVideoInput()
    this.buttonTargets.forEach((el) => {
      el.classList.toggle("hidden", !show)
    })
  }

  async hasVideoInput() {
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

  async scanWithCameraOverlay(input) {
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
    let controlsRef = null
    let readerRef = null

    const stopAndClose = () => {
      if (stopped) return
      stopped = true
      if (controlsRef) {
        try {
          controlsRef.stop()
        } catch (e) {
          console.warn("Failed to stop ZXing controls", e)
        }
      }
      if (readerRef) {
        try {
          readerRef.reset()
        } catch (e) {
          console.warn("Failed to reset ZXing reader", e)
        }
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

    const hints = new Map()
    hints.set(DecodeHintType.POSSIBLE_FORMATS, [BarcodeFormat.EAN_13, BarcodeFormat.EAN_8])
    const reader = new BrowserMultiFormatReader(hints)
    readerRef = reader

    try {
      await reader.decodeFromVideoDevice(
        null,
        video,
        (result, err, controls) => {
          if (stopped) {
            controls.stop()
            return
          }
          controlsRef = controls
          if (!result) return

          const raw = result.getText ? result.getText() : result.text
          const digits = (raw || "").replace(/\D/g, "")
          if (digits) {
            input.value = digits
            input.dispatchEvent(new Event("input", { bubbles: true }))
            input.dispatchEvent(new Event("change", { bubbles: true }))
          }
          stopAndClose()
        }
      )
    } catch (e) {
      console.warn("ZXing decodeFromVideoDevice failed", e)
      alert("Unable to start barcode scanner on this browser. Please use the built-in camera app and paste the ISBN.")
      stopAndClose()
    }
  }

  findIsbnInput(buttonEl) {
    // Look for a sibling text input in the same group
    const wrapper = buttonEl.closest("div")
    if (!wrapper) return null
    return wrapper.querySelector("input[type='text'], input[type='search'], input[type='tel']")
  }
}


