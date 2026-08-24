import {
  createHmac,
  randomBytes,
  scryptSync,
  timingSafeEqual
} from 'node:crypto'

const SESSION_VERSION = 'v1'
const PASSWORD_HASH_BYTES = 64
const MIN_SESSION_SECRET_BYTES = 32
const DEFAULT_SESSION_TTL_SECONDS = 8 * 60 * 60
const MAX_SESSION_TTL_SECONDS = 24 * 60 * 60

function safeEqual(left, right) {
  const leftBuffer = Buffer.from(left)
  const rightBuffer = Buffer.from(right)
  if (leftBuffer.length !== rightBuffer.length) {
    return false
  }
  return timingSafeEqual(leftBuffer, rightBuffer)
}

function parseHex(value, name, expectedBytes) {
  if (!/^[a-fA-F0-9]+$/.test(value) || value.length % 2 !== 0) {
    throw new Error(`${name} must be hex encoded`)
  }
  const parsed = Buffer.from(value, 'hex')
  if (expectedBytes !== undefined && parsed.length !== expectedBytes) {
    throw new Error(`${name} must contain ${expectedBytes} bytes`)
  }
  return parsed
}

function parseSessionSecret(value) {
  if (!/^[a-zA-Z0-9_-]+$/.test(value)) {
    throw new Error('MODLENS_SESSION_SECRET must be base64url encoded')
  }
  const secret = Buffer.from(value, 'base64url')
  if (secret.length < MIN_SESSION_SECRET_BYTES) {
    throw new Error(`MODLENS_SESSION_SECRET must contain at least ${MIN_SESSION_SECRET_BYTES} bytes`)
  }
  return secret
}

function parseSessionTtl(value) {
  const parsed = Number.parseInt(value ?? '', 10)
  if (!Number.isFinite(parsed) || parsed <= 0) {
    return DEFAULT_SESSION_TTL_SECONDS
  }
  return Math.min(parsed, MAX_SESSION_TTL_SECONDS)
}

export function derivePasswordHash(password, salt) {
  return scryptSync(password, salt, PASSWORD_HASH_BYTES, {
    N: 32768,
    r: 8,
    p: 1,
    maxmem: 64 * 1024 * 1024
  })
}

export function createAuthConfig(env = process.env) {
  const raw = {
    username: (env.MODLENS_AUTH_USERNAME ?? '').trim(),
    passwordSalt: (env.MODLENS_AUTH_PASSWORD_SALT ?? '').trim(),
    passwordHash: (env.MODLENS_AUTH_PASSWORD_HASH ?? '').trim(),
    sessionSecret: (env.MODLENS_SESSION_SECRET ?? '').trim()
  }
  const configuredValues = Object.values(raw).filter((value) => value !== '')
  if (configuredValues.length === 0) {
    return null
  }
  if (configuredValues.length !== Object.keys(raw).length) {
    throw new Error('All single-account authentication variables must be configured together')
  }
  if (raw.username.length > 128) {
    throw new Error('MODLENS_AUTH_USERNAME must not exceed 128 characters')
  }
  const passwordSalt = parseHex(raw.passwordSalt, 'MODLENS_AUTH_PASSWORD_SALT')
  if (passwordSalt.length < 16) {
    throw new Error('MODLENS_AUTH_PASSWORD_SALT must contain at least 16 bytes')
  }
  return {
    username: raw.username,
    passwordSalt,
    passwordHash: parseHex(raw.passwordHash, 'MODLENS_AUTH_PASSWORD_HASH', PASSWORD_HASH_BYTES),
    sessionSecret: parseSessionSecret(raw.sessionSecret),
    sessionTtlSeconds: parseSessionTtl(env.MODLENS_SESSION_TTL_SECONDS)
  }
}

export function verifyCredentials(config, username, password) {
  const suppliedUsername = typeof username === 'string' ? username.trim() : ''
  const suppliedPassword = typeof password === 'string' ? password : ''
  const suppliedHash = derivePasswordHash(suppliedPassword, config.passwordSalt)
  const usernameMatches = safeEqual(suppliedUsername, config.username)
  const passwordMatches = timingSafeEqual(suppliedHash, config.passwordHash)
  return usernameMatches && passwordMatches
}

function signTokenBody(body, secret) {
  return createHmac('sha256', secret).update(body).digest('base64url')
}

export function issueSessionToken(config, nowSeconds = Math.floor(Date.now() / 1000)) {
  const expiresAt = nowSeconds + config.sessionTtlSeconds
  const payload = Buffer.from(JSON.stringify({
    sub: config.username,
    iat: nowSeconds,
    exp: expiresAt,
    nonce: randomBytes(12).toString('base64url')
  })).toString('base64url')
  const body = `${SESSION_VERSION}.${payload}`
  return {
    token: `${body}.${signTokenBody(body, config.sessionSecret)}`,
    expiresAt,
    expiresIn: config.sessionTtlSeconds
  }
}

export function verifySessionToken(config, token, nowSeconds = Math.floor(Date.now() / 1000)) {
  if (typeof token !== 'string' || token.length > 2048) {
    return false
  }
  const parts = token.split('.')
  if (parts.length !== 3 || parts[0] !== SESSION_VERSION || parts[1] === '' || parts[2] === '') {
    return false
  }
  const body = `${parts[0]}.${parts[1]}`
  const expectedSignature = signTokenBody(body, config.sessionSecret)
  if (!safeEqual(parts[2], expectedSignature)) {
    return false
  }
  try {
    const payload = JSON.parse(Buffer.from(parts[1], 'base64url').toString('utf8'))
    return payload !== null &&
      typeof payload === 'object' &&
      payload.sub === config.username &&
      Number.isInteger(payload.iat) &&
      Number.isInteger(payload.exp) &&
      payload.iat <= nowSeconds + 60 &&
      payload.exp > nowSeconds &&
      payload.exp - payload.iat <= MAX_SESSION_TTL_SECONDS
  } catch (_error) {
    return false
  }
}

export function createLoginRateLimiter({
  windowMs = 15 * 60 * 1000,
  perClientLimit = 5,
  globalLimit = 30,
  maxClients = 2048,
  now = () => Date.now()
} = {}) {
  let globalWindow = { startsAt: now(), count: 0 }
  const clients = new Map()

  function refreshGlobal(currentTime) {
    if (currentTime - globalWindow.startsAt >= windowMs) {
      globalWindow = { startsAt: currentTime, count: 0 }
      clients.clear()
    }
  }

  return {
    consume(clientKey) {
      const currentTime = now()
      refreshGlobal(currentTime)
      if (globalWindow.count >= globalLimit) {
        return { allowed: false, retryAfterSeconds: Math.max(1, Math.ceil((globalWindow.startsAt + windowMs - currentTime) / 1000)) }
      }

      const key = typeof clientKey === 'string' && clientKey !== '' ? clientKey.slice(0, 128) : 'unknown'
      let client = clients.get(key)
      if (client === undefined || currentTime - client.startsAt >= windowMs) {
        if (clients.size >= maxClients) {
          clients.clear()
        }
        client = { startsAt: currentTime, count: 0 }
        clients.set(key, client)
      }
      if (client.count >= perClientLimit) {
        return { allowed: false, retryAfterSeconds: Math.max(1, Math.ceil((client.startsAt + windowMs - currentTime) / 1000)) }
      }

      client.count += 1
      globalWindow.count += 1
      return { allowed: true, retryAfterSeconds: 0 }
    },
    resetClient(clientKey) {
      clients.delete(clientKey)
    }
  }
}
