/**
 * Минимальный HTTP-сервис: POST /v1/fetch { url, waitUntil }
 * Защита: ALLOWED_HOSTS (обязательно непустой в production), Bearer FETCH_TOKEN.
 * См. playwright-worker/README.md
 */
import http from "http";
import { chromium } from "playwright";

const PORT = Number(process.env.PORT || 3001);
const TOKEN = (process.env.FETCH_TOKEN || "").trim();
const allowed = new Set(
  (process.env.ALLOWED_HOSTS || "")
    .split(",")
    .map((s) => s.trim().toLowerCase())
    .filter(Boolean)
);

function hostAllowed(hostname) {
  if (allowed.size === 0) return false;
  return allowed.has(hostname.toLowerCase());
}

async function handle(req, res) {
  if (req.method !== "POST" || req.url !== "/v1/fetch") {
    res.writeHead(req.method === "GET" && req.url === "/health" ? 200 : 404, {
      "Content-Type": "application/json",
    });
    if (req.method === "GET" && req.url === "/health") {
      res.end(JSON.stringify({ ok: true, service: "playwright-fetch" }));
    } else {
      res.end();
    }
    return;
  }

  const auth = req.headers.authorization || "";
  if (TOKEN && auth !== `Bearer ${TOKEN}`) {
    res.writeHead(401, { "Content-Type": "application/json; charset=utf-8" });
    res.end(JSON.stringify({ ok: false, error: "unauthorized" }));
    return;
  }

  let body = "";
  for await (const chunk of req) body += chunk;

  let json;
  try {
    json = JSON.parse(body || "{}");
  } catch {
    res.writeHead(400, { "Content-Type": "application/json; charset=utf-8" });
    res.end(JSON.stringify({ ok: false, error: "invalid_json" }));
    return;
  }

  const urlStr = json.url;
  if (!urlStr || typeof urlStr !== "string") {
    res.writeHead(400, { "Content-Type": "application/json; charset=utf-8" });
    res.end(JSON.stringify({ ok: false, error: "url_required" }));
    return;
  }

  let u;
  try {
    u = new URL(urlStr);
  } catch {
    res.writeHead(400, { "Content-Type": "application/json; charset=utf-8" });
    res.end(JSON.stringify({ ok: false, error: "invalid_url" }));
    return;
  }

  if (u.protocol !== "https:" && u.protocol !== "http:") {
    res.writeHead(400, { "Content-Type": "application/json; charset=utf-8" });
    res.end(JSON.stringify({ ok: false, error: "only_http_https" }));
    return;
  }

  if (!hostAllowed(u.hostname)) {
    res.writeHead(403, { "Content-Type": "application/json; charset=utf-8" });
    res.end(JSON.stringify({ ok: false, error: "host_not_allowed" }));
    return;
  }

  const waitUntil = json.waitUntil === "domcontentloaded" ? "domcontentloaded" : "load";
  const timeout = Math.min(Number(json.timeout) || 60000, 120000);

  const browser = await chromium.launch({ headless: true });
  try {
    const page = await browser.newPage();
    const resp = await page.goto(urlStr, { waitUntil, timeout });
    const title = await page.title();
    const textContent = await page.evaluate(
      () => document.body?.innerText?.slice(0, 500_000) || ""
    );
    const html = await page.content();
    const htmlSize = html.length;
    const payload = {
      ok: true,
      url: urlStr,
      finalUrl: page.url(),
      title,
      textContent: textContent.slice(0, 200_000),
      htmlSize,
      statusCode: resp?.status() ?? 0,
    };
    res.writeHead(200, { "Content-Type": "application/json; charset=utf-8" });
    res.end(JSON.stringify(payload));
  } catch (e) {
    res.writeHead(200, { "Content-Type": "application/json; charset=utf-8" });
    res.end(
      JSON.stringify({
        ok: false,
        error: e instanceof Error ? e.message : String(e),
      })
    );
  } finally {
    await browser.close();
  }
}

http.createServer(handle).listen(PORT, "0.0.0.0", () => {
  // eslint-disable-next-line no-console
  console.log(`[playwright-worker] listening on 0.0.0.0:${PORT}, allowlist size=${allowed.size}`);
});
