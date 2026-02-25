import { Controller } from "@hotwired/stimulus"

// Controls visibility and click behavior of camera icon buttons.
// Shows on devices with a camera, and opens camera to scan ISBN barcodes.
// Uses BarcodeDetector when available (Chrome/Edge/Android); otherwise just shows camera preview.
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

    // Always open the camera overlay; it will try to auto-detect barcodes when supported.
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
    let stream = null

    const stopAndClose = () => {
      if (stopped) return
      stopped = true
      if (stream) {
        try {
          stream.getTracks().forEach((t) => t.stop())
        } catch (e) {
          console.warn("Failed to stop camera stream", e)
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

    try {
      stream = await navigator.mediaDevices.getUserMedia({ video: { facingMode: "environment" } })
    } catch (e) {
      console.warn("getUserMedia failed", e)
      alert("Unable to open the camera. Please check browser permissions or use the built-in camera app and paste the ISBN.")
      stopAndClose()
      return
    }

    video.srcObject = stream

    // If BarcodeDetector is supported (Chrome, some Android browsers), try to auto-read barcodes.
    if ("BarcodeDetector" in window) {
      let detector = null
      try {
        detector = new window.BarcodeDetector({ formats: ["ean_13", "ean_8"] })
      } catch (e) {
        console.warn("BarcodeDetector construct failed", e)
        detector = null
      }

      if (detector) {
        const loop = async () => {
          if (stopped) return
          const code = await this.detectOnce(detector, video)
          if (code) {
            const digits = code.replace(/\D/g, "")
            if (digits) {
              input.value = digits
              input.dispatchEvent(new Event("input", { bubbles: true }))
              input.dispatchEvent(new Event("change", { bubbles: true }))
            }
            stopAndClose()
            return
          }
          requestAnimationFrame(loop)
        }

        requestAnimationFrame(loop)
      }
    }
    // On browsers without BarcodeDetector (e.g. Safari), we still show the live camera preview
    // so users can align the barcode and then type or paste the ISBN manually.
  }

  async detectOnce(detector, video) {
    if (video.readyState < 2) {
      await new Promise((resolve) => {
        video.onloadeddata = resolve
      })
    }
    try {
      const barcodes = await detector.detect(video)
      if (barcodes && barcodes.length > 0) {
        const raw = barcodes[0].rawValue || ""
        return raw
      }
      return null
    } catch (e) {
      console.warn("BarcodeDetector detect failed", e)
      return null
    }
  }

  findIsbnInput(buttonEl) {
    // Look for a sibling text input in the same group
    const wrapper = buttonEl.closest("div")
    if (!wrapper) return null
    return wrapper.querySelector("input[type='text'], input[type='search'], input[type='tel']")
  }
}


