import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [ "startBtn", "stopBtn", "status", "transcript", "reply" ]
  static values = {
    endpoint: String,
    reloadOnSuccess: { type: Boolean, default: true }
  }

  connect () {
    this.mediaRecorder = null
    this.chunks = []
  }

  async start () {
    try {
      const stream = await navigator.mediaDevices.getUserMedia({ audio: true })
      this.chunks = []
      this.mediaRecorder = new MediaRecorder(stream)
      this.mediaRecorder.ondataavailable = (e) => {
        if (e.data.size > 0) this.chunks.push(e.data)
      }
      this.mediaRecorder.start()
      this.statusTarget.textContent = "Идёт запись…"
      this.startBtnTarget.disabled = true
      this.stopBtnTarget.disabled = false
    } catch (err) {
      this.statusTarget.textContent = "Нет доступа к микрофону: " + err.message
    }
  }

  async stop () {
    if (!this.mediaRecorder || this.mediaRecorder.state === "inactive") return

    await new Promise((resolve) => {
      this.mediaRecorder.onstop = resolve
      this.mediaRecorder.stop()
    })
    this.mediaRecorder.stream.getTracks().forEach((t) => t.stop())

    const blob = new Blob(this.chunks, { type: this.chunks[0]?.type || "audio/webm" })
    this.statusTarget.textContent = "Отправка…"
    this.transcriptTarget.textContent = ""
    this.replyTarget.textContent = ""

    const fd = new FormData()
    fd.append("audio", blob, "voice.webm")

    const token = document.querySelector("meta[name='csrf-token']")?.getAttribute("content")
    const res = await fetch(this.endpointValue, {
      method: "POST",
      body: fd,
      headers: { "X-CSRF-Token": token || "" },
      credentials: "same-origin"
    })

    let data = {}
    try {
      data = await res.json()
    } catch (e) {
      this.replyTarget.textContent = "Некорректный ответ сервера"
      this.statusTarget.textContent = "Ошибка"
      this.startBtnTarget.disabled = false
      this.stopBtnTarget.disabled = true
      return
    }

    if (res.status === 410 || data.lead_gone) {
      this.replyTarget.textContent = data.error || "Лид удалён — обновляю страницу…"
      this.statusTarget.textContent = "Нужно обновить страницу"
      this.startBtnTarget.disabled = false
      this.stopBtnTarget.disabled = true
      window.setTimeout(() => { window.location.href = "/" }, 400)
      return
    }

    if (res.status === 404) {
      this.replyTarget.textContent = data.error || "Лид не найден"
      this.statusTarget.textContent = "Ошибка"
      this.startBtnTarget.disabled = false
      this.stopBtnTarget.disabled = true
      window.setTimeout(() => { window.location.href = "/" }, 600)
      return
    }

    this.transcriptTarget.textContent = data.transcript || ""
    const applied = Array.isArray(data.applied) ? data.applied : []
    const appliedLine = applied.length
      ? `\n\n[CRM] Сделано: ${applied.join(", ")}`
      : ""
    const errLine = data.error ? `\n\n[Ошибка] ${data.error}` : ""
    this.replyTarget.textContent =
      (data.assistant_message || data.error || data.hint || "") + appliedLine + errLine

    if (!res.ok) {
      this.statusTarget.textContent = "Ошибка"
      this.startBtnTarget.disabled = false
      this.stopBtnTarget.disabled = true
      return
    }

    if (data.created_lead_id) {
      this.statusTarget.textContent = "Лид создан — открываю карточку…"
      this.startBtnTarget.disabled = false
      this.stopBtnTarget.disabled = true
      window.setTimeout(() => {
        window.location.href = "/?lead_id=" + encodeURIComponent(data.created_lead_id)
      }, 500)
      return
    }

    this.statusTarget.textContent =
      data.success === false
        ? "Частично / ошибка"
        : applied.length > 0 && this.reloadOnSuccessValue
          ? "Готово — обновляю страницу…"
          : "Готово"

    this.startBtnTarget.disabled = false
    this.stopBtnTarget.disabled = true

    if (this.reloadOnSuccessValue && data.success && applied.length > 0) {
      const discard = applied.some((a) => String(a).includes("lead:discarded"))
      window.setTimeout(() => {
        if (discard) {
          window.location.href = "/"
        } else {
          window.location.reload()
        }
      }, 600)
    }
  }
}
