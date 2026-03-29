import { Controller } from "@hotwired/stimulus"

// Вопрос по базе знаний → POST /knowledge/query (JSON).
export default class extends Controller {
  static targets = ["question", "answer", "sources", "status"]
  static values = { queryUrl: String }

  async ask (event) {
    event.preventDefault()
    const q = this.questionTarget.value.trim()
    if (!q) return

    this.statusTarget.textContent = "Запрос…"
    if (this.hasAnswerTarget) this.answerTarget.textContent = ""
    if (this.hasSourcesTarget) this.sourcesTarget.innerHTML = ""

    const token = document.querySelector("meta[name='csrf-token']")?.getAttribute("content")
    const res = await fetch(this.queryUrlValue, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Accept: "application/json",
        "X-CSRF-Token": token || ""
      },
      body: JSON.stringify({ question: q })
    })

    let data = {}
    try {
      data = await res.json()
    } catch {
      this.statusTarget.textContent = "Ошибка разбора ответа"
      return
    }

    if (data.error && !data.answer) {
      this.statusTarget.textContent = data.error
      return
    }

    this.statusTarget.textContent = data.grounded ? "Ответ по базе знаний" : "Нет релевантного контекста"
    if (this.hasAnswerTarget) {
      this.answerTarget.textContent = data.answer || ""
    }

    if (this.hasSourcesTarget && Array.isArray(data.sources) && data.sources.length) {
      const ul = document.createElement("ul")
      ul.className = "rag-sources-list"
      data.sources.forEach((s) => {
        const li = document.createElement("li")
        li.textContent = `${s.document_title} (score ${s.score}) — ${s.excerpt}`
        ul.appendChild(li)
      })
      this.sourcesTarget.appendChild(ul)
    }
  }
}
