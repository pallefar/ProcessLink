import http from 'node:http'
import fs from 'node:fs'
import path from 'node:path'
import crypto from 'node:crypto'

const PORT = Number(process.env.AGENT_PORT || 4185)
const DATA = process.env.AGENT_DATA_DIR || path.join(process.cwd(), 'data')
const TOKEN = process.env.AGENT_ENROLL_TOKEN || 'local-dev-token'
const FILE = path.join(DATA, 'agents.json')

function load() {
  try { return JSON.parse(fs.readFileSync(FILE, 'utf8')) } catch { return { agents: {} } }
}
function save(state) {
  fs.mkdirSync(DATA, { recursive: true })
  const temp = `${FILE}.tmp`
  fs.writeFileSync(temp, JSON.stringify(state, null, 2))
  fs.renameSync(temp, FILE)
}
function json(res, status, body) {
  res.writeHead(status, {
    'content-type': 'application/json; charset=utf-8',
    'access-control-allow-origin': '*',
    'access-control-allow-headers': 'content-type, authorization',
    'access-control-allow-methods': 'GET, POST, PUT, DELETE, OPTIONS',
    'cache-control': 'no-store',
  })
  res.end(JSON.stringify(body))
}
async function body(req) {
  let raw = ''
  for await (const chunk of req) raw += chunk
  return raw ? JSON.parse(raw) : {}
}
function bearer(req) {
  return (req.headers.authorization || '').replace(/^Bearer /, '')
}
function adminAuthorized(req) { return bearer(req) === TOKEN }
function hash(value) { return crypto.createHash('sha256').update(value).digest('hex') }
function deviceFor(req, state) {
  const token = bearer(req)
  if (!token) return null
  const tokenHash = hash(token)
  return Object.values(state.agents).find(agent => agent.tokenHash === tokenHash) ?? null
}

const server = http.createServer(async (req, res) => {
  try {
    if (req.method === 'OPTIONS') return json(res, 204, {})
    if (req.method === 'GET' && req.url === '/health') return json(res, 200, { ok: true, service: 'processlink-agent-control' })
    if (req.url === '/health') return json(res, 200, { ok: true, service: 'processlink-agent-control' })
    if (req.method === 'POST' && req.url === '/v1/enroll' && !adminAuthorized(req)) return json(res, 401, { error: 'enrollment token required' })

    if (req.method === 'POST' && req.url === '/v1/enroll') {
      const input = await body(req)
      if (!input.deviceID || !input.policy) return json(res, 400, { error: 'deviceID and policy required' })
      const state = load()
      const deviceToken = crypto.randomBytes(32).toString('hex')
      state.agents[input.deviceID] = {
        deviceID: input.deviceID,
        tokenHash: hash(deviceToken),
        workspaceID: input.workspaceID || '',
        projectID: input.projectID || '',
        policy: input.policy,
        consents: Array.isArray(input.consents) ? input.consents : [],
        enrolledAt: new Date().toISOString(),
        lastHeartbeat: new Date().toISOString(),
      }
      save(state)
      return json(res, 201, { ok: true, deviceID: input.deviceID, deviceToken, enrolledAt: state.agents[input.deviceID].enrolledAt })
    }
    if (req.method === 'POST' && req.url === '/v1/heartbeat') {
      const input = await body(req)
      const state = load()
      const agent = deviceFor(req, state)
      if (!agent || (input.deviceID && input.deviceID !== agent.deviceID)) return json(res, 401, { error: 'device token required' })
      agent.lastHeartbeat = new Date().toISOString()
      save(state)
      return json(res, 200, { ok: true, deviceID: agent.deviceID, lastHeartbeat: agent.lastHeartbeat })
    }
    if (req.method === 'GET' && req.url === '/v1/agents') {
      if (!adminAuthorized(req)) return json(res, 401, { error: 'enrollment token required' })
      const agents = Object.values(load().agents).map(({ tokenHash: _omit, ...safe }) => safe)
      return json(res, 200, { agents })
    }
    if (req.method === 'DELETE' && req.url.startsWith('/v1/agents/')) {
      if (!adminAuthorized(req)) return json(res, 401, { error: 'enrollment token required' })
      const deviceID = decodeURIComponent(req.url.slice('/v1/agents/'.length))
      const state = load()
      if (!state.agents[deviceID]) return json(res, 404, { error: 'unknown device' })
      delete state.agents[deviceID]
      save(state)
      return json(res, 200, { ok: true, deviceID })
    }
    if (req.method === 'GET' && req.url.startsWith('/v1/policy')) {
      const deviceID = new URL(req.url, 'http://localhost').searchParams.get('deviceID') || ''
      const state = load()
      const agent = deviceFor(req, state)
      if (!agent || agent.deviceID !== deviceID) return json(res, 401, { error: 'device token required' })
      const { tokenHash: _omit, ...safe } = agent
      return json(res, 200, { agent: safe })
    }
    return json(res, 404, { error: 'not found' })
  } catch (error) {
    return json(res, 500, { error: error instanceof Error ? error.message : 'agent service error' })
  }
})
server.listen(PORT, '0.0.0.0', () => console.log(`ProcessLink agent control on http://127.0.0.1:${PORT}`))
