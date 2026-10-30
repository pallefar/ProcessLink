import http from "node:http";
import { pipeline } from "@huggingface/transformers";

const PORT = Number(process.env.AI_PORT || 4183);
const MODEL = process.env.AI_MODEL || "Xenova/all-MiniLM-L6-v2";
let extractorPromise;
const cache = new Map();

async function extractor() {
  if (!extractorPromise) {
    extractorPromise = pipeline("feature-extraction", MODEL, { dtype: "q8" });
  }
  return extractorPromise;
}

async function embed(texts) {
  const model = await extractor();
  const vectors = [];
  for (const text of texts) {
    const clean = String(text || "").trim();
    if (!clean) { vectors.push([]); continue; }
    if (cache.has(clean)) { vectors.push(cache.get(clean)); continue; }
    const output = await model(clean, { pooling: "mean", normalize: true });
    const vector = Array.from(output.data);
    cache.set(clean, vector);
    vectors.push(vector);
  }
  return vectors;
}

const cosine = (a, b) => {
  if (!a.length || !b.length) return 0;
  let dot = 0, aa = 0, bb = 0;
  for (let i = 0; i < a.length; i++) { dot += a[i] * b[i]; aa += a[i] * a[i]; bb += b[i] * b[i]; }
  return aa && bb ? dot / Math.sqrt(aa * bb) : 0;
};

function json(res, status, body) {
  res.writeHead(status, {
    "content-type": "application/json; charset=utf-8",
    "access-control-allow-origin": "*",
    "access-control-allow-headers": "content-type",
    "cache-control": "no-store",
  });
  res.end(JSON.stringify(body));
}

async function readBody(req) {
  let body = "";
  for await (const chunk of req) {
    body += chunk;
    if (body.length > 1_000_000) throw new Error("payload too large");
  }
  return body ? JSON.parse(body) : {};
}

async function mapActivities(activities, steps) {
  const labels = steps.map(step => step.label);
  const [activityVectors, stepVectors] = await Promise.all([embed(activities), embed(labels)]);
  const mapping = {};
  const confidence = {};
  activities.forEach((activity, index) => {
    let best = -1, bestScore = -1;
    stepVectors.forEach((vector, stepIndex) => {
      const score = cosine(activityVectors[index], vector);
      if (score > bestScore) { bestScore = score; best = stepIndex; }
    });
    if (best >= 0 && bestScore >= 0.35) {
      mapping[activity] = steps[best].id;
      confidence[activity] = Number(bestScore.toFixed(3));
    }
  });
  return { mapping, confidence, model: MODEL };
}

async function nameTasks(samples, candidates) {
  const texts = samples.map(sample => [sample.app, sample.title].filter(Boolean).join(" · "));
  const [sampleVectors, candidateVectors] = await Promise.all([embed(texts), embed(candidates)]);
  const names = samples.map((sample, index) => {
    let best = -1, bestScore = -1;
    candidateVectors.forEach((vector, candidateIndex) => {
      const score = cosine(sampleVectors[index], vector);
      if (score > bestScore) { bestScore = score; best = candidateIndex; }
    });
    return {
      app: sample.app, title: sample.title || "",
      suggestedName: best >= 0 && bestScore >= 0.3 ? candidates[best] : sample.app,
      confidence: Math.max(0, Number(bestScore.toFixed(3))),
    };
  });
  return { tasks: names, model: MODEL };
}

const server = http.createServer(async (req, res) => {
  try {
    if (req.method === "OPTIONS") return json(res, 204, {});
    if (req.method === "GET" && req.url === "/health") return json(res, 200, { ok: true, model: MODEL });
    if (req.method === "POST" && req.url === "/api/map") {
      const body = await readBody(req);
      const activities = Array.isArray(body.activities) ? body.activities.filter(Boolean) : [];
      const steps = Array.isArray(body.steps) ? body.steps.filter(step => step?.id && step?.label) : [];
      if (!activities.length || !steps.length) return json(res, 400, { error: "activities and steps required" });
      return json(res, 200, await mapActivities(activities, steps));
    }
    if (req.method === "POST" && req.url === "/api/name") {
      const body = await readBody(req);
      const samples = Array.isArray(body.samples) ? body.samples.slice(0, 200) : [];
      const candidates = Array.isArray(body.candidates) ? body.candidates.filter(Boolean) : [];
      if (!samples.length || !candidates.length) return json(res, 400, { error: "samples and candidates required" });
      return json(res, 200, await nameTasks(samples, candidates));
    }
    return json(res, 404, { error: "not found" });
  } catch (error) {
    console.error("ai error", error?.message || error);
    return json(res, 500, { error: error?.message || "ai error" });
  }
});

server.listen(PORT, "127.0.0.1", () => {
  console.log(`ProcessLink AI on http://127.0.0.1:${PORT} · ${MODEL}`);
});
