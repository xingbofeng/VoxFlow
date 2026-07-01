const crypto = require("crypto");

const tokenEndpoint = "https://api.weixin.qq.com/cgi-bin/token";
const ticketEndpoint = "https://api.weixin.qq.com/cgi-bin/ticket/getticket";
const cacheSafetyWindowMs = 5 * 60 * 1000;

let accessTokenCache = null;
let jsapiTicketCache = null;

function json(res, statusCode, payload) {
  res.statusCode = statusCode;
  res.setHeader("Content-Type", "application/json; charset=utf-8");
  res.setHeader("Cache-Control", "no-store");
  res.end(JSON.stringify(payload));
}

function isConfigured() {
  return Boolean(process.env.WECHAT_APP_ID && process.env.WECHAT_APP_SECRET);
}

function assertShareURL(value) {
  if (!value) throw new Error("missing url");
  const parsed = new URL(value);
  if (parsed.protocol !== "https:") throw new Error("url must use https");
  if (parsed.hostname !== "mashangxie.app" && parsed.hostname !== "www.mashangxie.app") {
    throw new Error("url host is not allowed");
  }
  parsed.hash = "";
  return parsed.toString();
}

async function fetchWechatJSON(url) {
  const response = await fetch(url);
  const payload = await response.json();
  if (!response.ok || payload.errcode) {
    const message = payload.errmsg || `WeChat request failed with ${response.status}`;
    throw new Error(message);
  }
  return payload;
}

function cacheIsFresh(cache) {
  return cache && cache.expiresAt > Date.now() + cacheSafetyWindowMs;
}

async function getAccessToken() {
  if (cacheIsFresh(accessTokenCache)) return accessTokenCache.value;

  const params = new URLSearchParams({
    grant_type: "client_credential",
    appid: process.env.WECHAT_APP_ID,
    secret: process.env.WECHAT_APP_SECRET
  });
  const payload = await fetchWechatJSON(`${tokenEndpoint}?${params}`);
  accessTokenCache = {
    value: payload.access_token,
    expiresAt: Date.now() + (Number(payload.expires_in || 7200) * 1000)
  };
  jsapiTicketCache = null;
  return accessTokenCache.value;
}

async function getJsapiTicket() {
  if (cacheIsFresh(jsapiTicketCache)) return jsapiTicketCache.value;

  const accessToken = await getAccessToken();
  const params = new URLSearchParams({
    access_token: accessToken,
    type: "jsapi"
  });
  const payload = await fetchWechatJSON(`${ticketEndpoint}?${params}`);
  jsapiTicketCache = {
    value: payload.ticket,
    expiresAt: Date.now() + (Number(payload.expires_in || 7200) * 1000)
  };
  return jsapiTicketCache.value;
}

function createNonce() {
  return crypto.randomBytes(12).toString("hex");
}

function createSignature({ ticket, nonceStr, timestamp, url }) {
  const stringToSign = [
    `jsapi_ticket=${ticket}`,
    `noncestr=${nonceStr}`,
    `timestamp=${timestamp}`,
    `url=${url}`
  ].join("&");
  return crypto.createHash("sha1").update(stringToSign).digest("hex");
}

module.exports = async function handler(req, res) {
  if (req.method !== "GET") {
    json(res, 405, { error: "method_not_allowed" });
    return;
  }

  if (!isConfigured()) {
    json(res, 501, { error: "wechat_not_configured" });
    return;
  }

  try {
    const requestURL = new URL(req.url, `https://${req.headers.host || "mashangxie.app"}`);
    const shareURL = assertShareURL(req.query?.url || requestURL.searchParams.get("url"));
    const ticket = await getJsapiTicket();
    const nonceStr = createNonce();
    const timestamp = Math.floor(Date.now() / 1000);
    const signature = createSignature({
      ticket,
      nonceStr,
      timestamp,
      url: shareURL
    });

    json(res, 200, {
      appId: process.env.WECHAT_APP_ID,
      nonceStr,
      timestamp,
      signature,
      url: shareURL
    });
  } catch (error) {
    json(res, 400, {
      error: "wechat_signature_failed",
      message: error.message
    });
  }
};
