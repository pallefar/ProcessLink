# transformers.js AI sidecar

ProcessLink uses a local Node process rather than embedding a browser model or
calling a hosted provider.

- Model: `Xenova/all-MiniLM-L6-v2` by default, via `@huggingface/transformers`.
- `Suggest with AI` maps activity labels to map steps by embedding similarity.
- `AI name tasks` suggests task names from capture segments and the process
  vocabulary.
- Settings → AI can test the sidecar; an unavailable sidecar leaves the normal
  manual mapping and capture paths intact.
- Only labels are sent. Case ids, event rows and person data never leave the Mac.

Start it with `cd ai && npm install && npm start` (port 4183).


The web Mining → Insights **AI map alignment** card calls the same `/api/map`
endpoint and shows confidence. Browsers need the sidecar running with CORS
enabled (it is); the card fails explicitly when it is unavailable.
