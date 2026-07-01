const http = require("http");
const path = require("path");
const fs = require("fs");
const wechatSignature = require(fs.existsSync(path.join(__dirname, "wechat-signature.js"))
  ? "./wechat-signature"
  : "../api/wechat-signature");

const port = Number(process.env.PORT || 8080);
const publicDir = process.env.PUBLIC_DIR || path.join(__dirname, "public");

const mimeTypes = new Map([
  [".css", "text/css; charset=utf-8"],
  [".html", "text/html; charset=utf-8"],
  [".js", "application/javascript; charset=utf-8"],
  [".json", "application/json; charset=utf-8"],
  [".png", "image/png"],
  [".txt", "text/plain; charset=utf-8"]
]);

function send(res, statusCode, headers, body) {
  res.writeHead(statusCode, headers);
  res.end(body);
}

function serveStatic(req, res) {
  let pathname = "/";
  try {
    const requestURL = new URL(req.url, "https://mashangxie.app");
    pathname = decodeURIComponent(requestURL.pathname);
  } catch {
    send(res, 400, { "Content-Type": "text/plain; charset=utf-8" }, "Bad Request");
    return;
  }

  const candidate = pathname === "/" ? "/index.html" : pathname;
  const resolved = path.resolve(publicDir, `.${candidate}`);
  const publicRoot = path.resolve(publicDir);

  if (resolved !== publicRoot && !resolved.startsWith(`${publicRoot}${path.sep}`)) {
    send(res, 403, { "Content-Type": "text/plain; charset=utf-8" }, "Forbidden");
    return;
  }

  const filePath = fs.existsSync(resolved) && fs.statSync(resolved).isFile()
    ? resolved
    : path.join(publicDir, "index.html");
  const extension = path.extname(filePath);
  send(res, 200, {
    "Content-Type": mimeTypes.get(extension) || "application/octet-stream",
    "Cache-Control": extension === ".html" ? "no-cache" : "public, max-age=31536000, immutable"
  }, fs.readFileSync(filePath));
}

const server = http.createServer((req, res) => {
  if (req.url === "/ready" || req.url === "/health") {
    send(res, 200, { "Content-Type": "text/plain; charset=utf-8" }, "ok");
    return;
  }
  if (req.url?.startsWith("/api/wechat-signature")) {
    wechatSignature(req, res);
    return;
  }
  serveStatic(req, res);
});

server.listen(port, "0.0.0.0", () => {
  console.log(`voxflow landing server listening on ${port}`);
});
