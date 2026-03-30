/**
 * Минимальный HTTP-сервис: POST /v1/fetch { url, waitUntil }
 * Защита: ALLOWED_HOSTS (обязательно непустой в production), Bearer FETCH_TOKEN.
 * См. playwright-worker/README.md
 */
import http from "http";
import { chromium } from "playwright";
import dns from "dns";
import net from "net";

const PORT = Number(process.env.PORT || 3001);
const TOKEN = (process.env.FETCH_TOKEN || "").trim();
const envAllowed = new Set(
  (process.env.ALLOWED_HOSTS || "")
    .split(",")
    .map((s) => s.trim().toLowerCase())
    .filter(Boolean)
);

function normalizeAllowedHosts(hosts) {
  const arr = Array.isArray(hosts) ? hosts : [];
  return new Set(
    arr
      .map((s) => String(s).trim().toLowerCase())
      .filter(Boolean)
  );
}

function isPrivateIPv4(ip) {
  // Very small helper; enough for SSRF protection.
  const parts = ip.split(".").map((x) => Number(x));
  if (parts.length !== 4 || parts.some((n) => Number.isNaN(n))) return false;
  const [a, b] = parts;
  if (a === 10) return true;
  if (a === 127) return true;
  if (a === 169 && b === 254) return true;
  if (a === 172 && b >= 16 && b <= 31) return true;
  if (a === 192 && b === 168) return true;
  return false;
}

function isPrivateIPv6(ip) {
  // Basic checks:
  // - loopback ::1
  // - unique local fc00::/7
  // - link-local fe80::/10
  if (ip === "::1") return true;
  const lower = ip.toLowerCase();
  if (lower.startsWith("fc") || lower.startsWith("fd")) return true;
  if (lower.startsWith("fe80:")) return true;
  return false;
}

function safeHostLiteral(hostname) {
  const lower = hostname.toLowerCase();
  if (lower === "localhost" || lower.endsWith(".localhost")) return false;
  if (lower === "0.0.0.0") return false;

  if (net.isIP(lower) === 4) return !isPrivateIPv4(lower);
  if (net.isIP(lower) === 6) return !isPrivateIPv6(lower);
  return true; // domain name: check via DNS in safeHostForRequest()
}

async function safeHostForRequest(hostname) {
  if (!safeHostLiteral(hostname)) return false;

  // If it's not an IP literal, resolve and block private IP targets.
  if (net.isIP(hostname) === 0) {
    try {
      const res = await dns.promises.lookup(hostname, { all: true });
      const addrs = Array.isArray(res) ? res.map((r) => r.address) : [];
      if (addrs.length === 0) return false;
      for (const ip of addrs) {
        if (net.isIP(ip) === 4) {
          if (isPrivateIPv4(ip)) return false;
        } else if (net.isIP(ip) === 6) {
          if (isPrivateIPv6(ip)) return false;
        }
      }
    } catch {
      return false;
    }
  }

  return true;
}

function hostAllowed(hostname, allowedSet) {
  if (!allowedSet || allowedSet.size === 0) return false;
  return allowedSet.has(hostname.toLowerCase());
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

  const requestAllowedHosts = normalizeAllowedHosts(json.allowedHosts);
  const allowedSet = requestAllowedHosts.size > 0 ? requestAllowedHosts : envAllowed;

  if (!hostAllowed(u.hostname, allowedSet)) {
    res.writeHead(403, { "Content-Type": "application/json; charset=utf-8" });
    res.end(JSON.stringify({ ok: false, error: "host_not_allowed" }));
    return;
  }

  const safe = await safeHostForRequest(u.hostname);
  if (!safe) {
    res.writeHead(403, { "Content-Type": "application/json; charset=utf-8" });
    res.end(JSON.stringify({ ok: false, error: "unsafe_host" }));
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
