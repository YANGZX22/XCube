import test from 'node:test'
import assert from 'node:assert/strict'
import {
  createAuthConfig,
  createLoginRateLimiter,
  derivePasswordHash,
  issueSessionToken,
  verifyCredentials,
  verifySessionToken
} from '../src/auth.mjs'

function testConfig() {
  const salt = Buffer.from('0123456789abcdef0123456789abcdef')
  const passwordHash = derivePasswordHash('correct horse battery staple', salt)
  return createAuthConfig({
    MODLENS_AUTH_USERNAME: 'owner',
    MODLENS_AUTH_PASSWORD_SALT: salt.toString('hex'),
    MODLENS_AUTH_PASSWORD_HASH: passwordHash.toString('hex'),
    MODLENS_SESSION_SECRET: Buffer.alloc(32, 7).toString('base64url'),
    MODLENS_SESSION_TTL_SECONDS: '3600'
  })
}

test('single-account credentials use a derived password hash', () => {
  const config = testConfig()
  assert.equal(verifyCredentials(config, 'owner', 'correct horse battery staple'), true)
  assert.equal(verifyCredentials(config, 'owner', 'wrong password'), false)
  assert.equal(verifyCredentials(config, 'someone-else', 'correct horse battery staple'), false)
})

test('session tokens are signed, expire, and cannot be changed', () => {
  const config = testConfig()
  const session = issueSessionToken(config, 1000)
  assert.equal(verifySessionToken(config, session.token, 1001), true)
  assert.equal(verifySessionToken(config, session.token, 4600), false)
  assert.equal(verifySessionToken(config, `${session.token}changed`, 1001), false)
})

test('partial or weak authentication configuration is rejected', () => {
  assert.equal(createAuthConfig({}), null)
  assert.throws(() => createAuthConfig({ MODLENS_AUTH_USERNAME: 'owner' }), /configured together/)
  assert.throws(() => createAuthConfig({
    MODLENS_AUTH_USERNAME: 'owner',
    MODLENS_AUTH_PASSWORD_SALT: '00',
    MODLENS_AUTH_PASSWORD_HASH: '00'.repeat(64),
    MODLENS_SESSION_SECRET: 'dG9vLXNob3J0'
  }), /at least 16 bytes/)
})

test('login rate limiter enforces per-client and global windows', () => {
  let currentTime = 1000
  const limiter = createLoginRateLimiter({
    windowMs: 1000,
    perClientLimit: 2,
    globalLimit: 3,
    now: () => currentTime
  })
  assert.equal(limiter.consume('a').allowed, true)
  assert.equal(limiter.consume('a').allowed, true)
  assert.equal(limiter.consume('a').allowed, false)
  assert.equal(limiter.consume('b').allowed, true)
  assert.equal(limiter.consume('c').allowed, false)
  currentTime += 1001
  assert.equal(limiter.consume('a').allowed, true)
})
