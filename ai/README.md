# ProcessLink AI sidecar

Local `transformers.js` service. It receives activity labels, map step labels and
capture task titles; it never receives case ids, raw event rows or person data.

```sh
cd ai
npm install
npm start
```

Default: `http://127.0.0.1:4183`, model `Xenova/all-MiniLM-L6-v2`. The first
call downloads the quantised model to the Hugging Face cache; after that the
service works offline. Set `AI_PORT` or `AI_MODEL` to change them.

Endpoints:

- `GET /health`
- `POST /api/map` — `{ activities, steps:[{id,label}] }` → mapping + confidence
- `POST /api/name` — `{ samples:[{app,title}], candidates }` → suggested task names

The macOS app uses this for **Suggest with AI** in Map activities and **AI name
tasks** on a capture session. Settings → AI exposes the sidecar URL and a test
button. Nothing is sent to a hosted AI provider.
