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

const gatewayRoot = resolve(dirname(fileURLToPath(import.meta.url)), '..')
const host = (process.env.MODLENS_GATEWAY_HOST ?? '127.0.0.1').trim()
const port = parsePositiveInteger(process.env.MODLENS_GATEWAY_PORT, 8787, 65535)
const requestTimeoutMs = parsePositiveInteger(process.env.MODLENS_TIMEOUT_MS, 180000, 900000)
const authToken = (process.env.MODLENS_GATEWAY_TOKEN ?? '').trim()
const provider = (process.env.MODLENS_PROVIDER ?? '').trim()

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

function respond(response, statusCode, body) {
  const payload = JSON.stringify(body)
  response.writeHead(statusCode, {
    'Content-Type': 'application/json; charset=utf-8',
    'Content-Length': Buffer.byteLength(payload),
    'Cache-Control': 'no-store',
    'X-Content-Type-Options': 'nosniff'
  })
  response.end(payload)
}

function tokenMatches(authorization) {
  if (authToken === '') {
    return true
  }
  if (typeof authorization !== 'string' || !authorization.startsWith('Bearer ')) {
    return false
  }
  const supplied = authorization.slice(7).trim()
  const expectedHash = createHash('sha256').update(authToken).digest()
  const suppliedHash = createHash('sha256').update(supplied).digest()
  return timingSafeEqual(expectedHash, suppliedHash)
}

async function readJsonBody(request) {
  const chunks = []
  let size = 0
  for await (const chunk of request) {
    size += chunk.length
    if (size > MAX_JSON_BODY_BYTES) {
      throw new Error(`Request body exceeds the ${MAX_JSON_BODY_BYTES} byte limit`)
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
        modlensVersion: await readModLensVersion()
      })
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
