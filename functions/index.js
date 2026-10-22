// Proxy Gemini: giấu khóa API khỏi app, chỉ cho người dùng đã đăng nhập.
// Triển khai:  firebase functions:secrets:set GEMINI_API_KEY && firebase deploy --only functions
const { onRequest } = require("firebase-functions/v2/https");
const { defineSecret } = require("firebase-functions/params");
const admin = require("firebase-admin");

admin.initializeApp();
const GEMINI_API_KEY = defineSecret("GEMINI_API_KEY");
const MODEL = "gemini-2.5-flash";

exports.gemini = onRequest({ secrets: [GEMINI_API_KEY], region: "asia-southeast1" }, async (req, res) => {
  if (req.method !== "POST") return res.status(405).send("POST only");
  const m = /^Bearer (.+)$/.exec(req.get("Authorization") || "");
  if (!m) return res.status(401).send("Missing token");
  try {
    await admin.auth().verifyIdToken(m[1]);
  } catch (_) {
    return res.status(401).send("Invalid token");
  }
  const r = await fetch(
    `https://generativelanguage.googleapis.com/v1beta/models/${MODEL}:generateContent`,
    {
      method: "POST",
      headers: { "Content-Type": "application/json", "x-goog-api-key": GEMINI_API_KEY.value() },
      body: JSON.stringify(req.body),
    }
  );
  res.status(r.status).type("application/json").send(await r.text());
});
