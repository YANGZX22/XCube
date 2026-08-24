import { createServer } from 'node:http'
import { spawn } from 'node:child_process'
import { createHash, timingSafeEqual } from 'node:crypto'
import { mkdtemp, readFile, rm, writeFile } from 'node:fs/promises'
import { tmpdir } from 'node:os'
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'
import {
  isLoopbackHost,
  MAX_JSON_BODY_BYTES,
  parseModLensOutput,
  validateAnalyzePayload
} from './core.mjs'
import {
  createAuthConfig,
  createLoginRateLimiter,
  issueSessionToken,
  verifyCredentials,
  verifySessionToken
} from './auth.mjs'
import { logLoginFailure } from './audit.mjs'

const gatewayRoot = resolve(dirname(fileURLToPath(import.meta.url)), '..')
const host = (process.env.MODLENS_GATEWAY_HOST ?? '127.0.0.1').trim()
const port = parsePositiveInteger(process.env.MODLENS_GATEWAY_PORT, 8787, 65535)
const requestTimeoutMs = parsePositiveInteger(process.env.MODLENS_TIMEOUT_MS, 180000, 900000)
const maxConcurrentAnalyses = parsePositiveInteger(process.env.MODLENS_MAX_CONCURRENT, 1, 16)
const authToken = (process.env.MODLENS_GATEWAY_TOKEN ?? '').trim()
const provider = (process.env.MODLENS_PROVIDER ?? '').trim()
const accountAuth = createAuthConfig()
const loginRateLimiter = createLoginRateLimiter()
let activeAnalyses = 0

if (!isLoopbackHost(host) && authToken === '') {
  throw new Error('MODLENS_GATEWAY_TOKEN is required when listening on a non-loopback address')
}

function parsePositiveInteger(value, fallback, maximum) {
  const parsed = Number.parseInt(value ?? '', 10)
  if (!Number.isFinite(parsed) || parsed <= 0 || parsed > maximum) {
    return fallback
  }
  return parsed
}

function respond(response, statusCode, body, extraHeaders = {}) {
  const payload = JSON.stringify(body)
  response.writeHead(statusCode, {
    'Content-Type': 'application/json; charset=utf-8',
    'Content-Length': Buffer.byteLength(payload),
    'Cache-Control': 'no-store',
    'X-Content-Type-Options': 'nosniff',
    ...extraHeaders
  })
  response.end(payload)
}

function tokenMatches(authorization) {
  if (authToken === '' && accountAuth === null) {
    return true
  }
  if (typeof authorization !== 'string' || !authorization.startsWith('Bearer ')) {
    return false
  }
  const supplied = authorization.slice(7).trim()
  if (authToken !== '') {
    const expectedHash = createHash('sha256').update(authToken).digest()
    const suppliedHash = createHash('sha256').update(supplied).digest()
    if (timingSafeEqual(expectedHash, suppliedHash)) {
      return true
    }
  }
  return accountAuth !== null && verifySessionToken(accountAuth, supplied)
}

async function readJsonBody(request, maximumBytes = MAX_JSON_BODY_BYTES) {
  const chunks = []
  let size = 0
  for await (const chunk of request) {
    size += chunk.length
    if (size > maximumBytes) {
      throw new Error(`Request body exceeds the ${maximumBytes} byte limit`)
    }
    chunks.push(chunk)
  }
  const raw = Buffer.concat(chunks).toString('utf8')
  try {
    return JSON.parse(raw)
  } catch (_error) {
    throw new Error('Request body is not valid JSON')
  }
}

function getLoginClientKey(request) {
  const forwardedFor = request.headers['x-forwarded-for']
  if (typeof forwardedFor === 'string') {
    const addresses = forwardedFor.split(',').map((value) => value.trim()).filter(Boolean)
    if (addresses.length > 0) {
      // Apache appends the actual peer address. Using the last value prevents a
      // direct client from bypassing the per-client limit with a forged prefix.
      return addresses.at(-1).slice(0, 128)
    }
  }
  return request.socket.remoteAddress ?? 'unknown'
}

async function login(request, response) {
  if (accountAuth === null) {
    logLoginFailure(request, 'login_not_configured')
    respond(response, 404, { ok: false, error: 'Not found' })
    return
  }
  if (!request.headers['content-type']?.toLowerCase().startsWith('application/json')) {
    logLoginFailure(request, 'unsupported_content_type')
    respond(response, 415, { ok: false, error: 'Content-Type must be application/json' })
    return
  }
  const clientKey = getLoginClientKey(request)
  const rateLimit = loginRateLimiter.consume(clientKey)
  if (!rateLimit.allowed) {
    logLoginFailure(request, 'rate_limited')
    respond(response, 429, { ok: false, error: 'Too many login attempts; retry later' }, {
      'Retry-After': `${rateLimit.retryAfterSeconds}`
    })
    return
  }
  let payload
  try {
    payload = await readJsonBody(request, 4096)
  } catch (error) {
    const reason = error instanceof Error && error.message.includes('exceeds')
      ? 'request_too_large'
      : 'invalid_json'
    logLoginFailure(request, reason)
    throw error
  }
  if (payload === null || typeof payload !== 'object' || Array.isArray(payload) ||
    !verifyCredentials(accountAuth, payload.username, payload.password)) {
    logLoginFailure(request, 'invalid_credentials', payload?.client)
    respond(response, 401, { ok: false, error: 'Invalid credentials' })
    return
  }
  loginRateLimiter.resetClient(clientKey)
  const session = issueSessionToken(accountAuth)
  respond(response, 200, {
    ok: true,
    tokenType: 'Bearer',
    token: session.token,
    expiresAt: new Date(session.expiresAt * 1000).toISOString(),
    expiresIn: session.expiresIn
  })
}

async function resolveModLensCli() {
  const override = (process.env.MODLENS_CLI_PATH ?? '').trim()
  if (override !== '') {
    return resolve(override)
  }
  const packageJsonUrl = import.meta.resolve('@liustack/modlens/package.json')
  const packageJsonPath = fileURLToPath(packageJsonUrl)
  const packageJson = JSON.parse(await readFile(packageJsonPath, 'utf8'))
  const binPath = typeof packageJson.bin === 'string' ? packageJson.bin : packageJson.bin?.modlens
  if (typeof binPath !== 'string' || binPath.trim() === '') {
    throw new Error('Installed @liustack/modlens package has no modlens executable')
  }
  return resolve(dirname(packageJsonPath), binPath)
}

async function readModLensVersion() {
  try {
    const packageJsonUrl = import.meta.resolve('@liustack/modlens/package.json')
    const packageJson = JSON.parse(await readFile(fileURLToPath(packageJsonUrl), 'utf8'))
    return typeof packageJson.version === 'string' ? packageJson.version : 'unknown'
  } catch (_error) {
    return 'unavailable'
  }
}

async function runModLens(imagePath, prompt) {
  const cliPath = await resolveModLensCli()
  const args = [cliPath, '-i', imagePath, '--timeout', `${requestTimeoutMs}`]
  if (provider !== '') {
    args.push('--provider', provider)
  }
  if (prompt !== '') {
    args.push('--prompt', prompt)
  }
  return await new Promise((resolvePromise, rejectPromise) => {
    const child = spawn(process.execPath, args, {
      cwd: (process.env.MODLENS_WORKDIR ?? gatewayRoot).trim() || gatewayRoot,
      env: process.env,
      stdio: ['ignore', 'pipe', 'pipe']
    })
    const stdoutChunks = []
    const stderrChunks = []
    let stdoutSize = 0
    let stderrSize = 0
    let settled = false
    let timeout
    const finish = (callback) => {
      if (settled) {
        return
      }
      settled = true
      clearTimeout(timeout)
      callback()
    }
    child.stdout.on('data', (chunk) => {
      stdoutSize += chunk.length
      if (stdoutSize <= 10 * 1024 * 1024) {
        stdoutChunks.push(chunk)
      } else {
        child.kill('SIGTERM')
      }
    })
    child.stderr.on('data', (chunk) => {
      stderrSize += chunk.length
      if (stderrSize <= 1024 * 1024) {
        stderrChunks.push(chunk)
      }
    })
    child.on('error', (error) => finish(() => rejectPromise(error)))
    child.on('close', (code, signal) => finish(() => {
      const stdout = Buffer.concat(stdoutChunks).toString('utf8')
      const stderr = Buffer.concat(stderrChunks).toString('utf8').trim()
      if (stdoutSize > 10 * 1024 * 1024) {
        rejectPromise(new Error('ModLens response exceeded the 10 MiB limit'))
        return
      }
      if (code !== 0) {
        rejectPromise(new Error(stderr || `ModLens exited with code ${code ?? 'unknown'} (${signal ?? 'no signal'})`))
        return
      }
      try {
        resolvePromise(parseModLensOutput(stdout))
      } catch (error) {
        rejectPromise(error)
      }
    }))
    timeout = setTimeout(() => {
      child.kill('SIGTERM')
      setTimeout(() => child.kill('SIGKILL'), 2000).unref()
      finish(() => rejectPromise(new Error(`ModLens timed out after ${requestTimeoutMs} ms`)))
    }, requestTimeoutMs + 15000)
    timeout.unref()
  })
}

async function analyze(request, response) {
  if (!tokenMatches(request.headers.authorization)) {
    respond(response, 401, { ok: false, error: 'Unauthorized' })
    return
  }
  if (activeAnalyses >= maxConcurrentAnalyses) {
    respond(response, 429, { ok: false, error: 'Vision gateway is busy; retry later' })
    return
  }
  activeAnalyses += 1
  try {
    const payload = validateAnalyzePayload(await readJsonBody(request))
    const tempDirectory = await mkdtemp(join(tmpdir(), 'chatcube-modlens-'))
    const imagePath = join(tempDirectory, payload.fileName)
    try {
      await writeFile(imagePath, payload.imageBuffer, { mode: 0o600 })
      const output = await runModLens(imagePath, payload.prompt)
      respond(response, 200, { ok: true, output })
    } finally {
      await rm(tempDirectory, { recursive: true, force: true })
    }
  } finally {
    activeAnalyses -= 1
  }
}

const server = createServer(async (request, response) => {
  try {
    if (request.method === 'GET' && request.url === '/health') {
      if (!tokenMatches(request.headers.authorization)) {
        respond(response, 401, { ok: false, error: 'Unauthorized' })
        return
      }
      respond(response, 200, {
        ok: true,
        service: 'chatcube-modlens-gateway',
        modlensVersion: await readModLensVersion(),
        capacity: {
          active: activeAnalyses,
          maximum: maxConcurrentAnalyses
        }
      })
      return
    }
    if (request.method === 'POST' && request.url === '/auth/login') {
      await login(request, response)
      return
    }
    if (request.method === 'POST' && request.url === '/analyze') {
      await analyze(request, response)
      return
    }
    respond(response, 404, { ok: false, error: 'Not found' })
  } catch (error) {
    const message = error instanceof Error ? error.message : `${error}`
    const statusCode = message.includes('exceeds') ? 413 : 400
    console.error('[modlens-gateway]', message)
    if (!response.headersSent) {
      respond(response, statusCode, { ok: false, error: message })
    } else {
      response.end()
    }
  }
})

server.requestTimeout = requestTimeoutMs + 30000
server.headersTimeout = 15000
server.listen(port, host, () => {
  console.info(`[modlens-gateway] listening on http://${host}:${port}`)
})
