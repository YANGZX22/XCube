import test from 'node:test'
import assert from 'node:assert/strict'
import {
  createLoginFailureAuditEvent,
  getAuditClientIp,
  parseUserAgent
} from '../src/audit.mjs'

function request(headers = {}, remoteAddress = '127.0.0.1') {
  return { headers, socket: { remoteAddress } }
}

test('audit IP prefers Cloudflare client IP and falls back safely', () => {
  assert.deepEqual(getAuditClientIp(request({
    'cf-connecting-ip': '203.0.113.7',
    'x-forwarded-for': '198.51.100.2, 192.0.2.3'
  })), { address: '203.0.113.7', source: 'cf-connecting-ip' })
  assert.deepEqual(getAuditClientIp(request({
    'cf-connecting-ip': 'not-an-ip',
    'x-forwarded-for': '198.51.100.2, 192.0.2.3'
  })), { address: '198.51.100.2', source: 'x-forwarded-for' })
  assert.deepEqual(getAuditClientIp(request()), { address: '127.0.0.1', source: 'socket' })
})

test('user agent parser extracts OS and browser without dependencies', () => {
  assert.deepEqual(parseUserAgent(
    'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 Chrome/140.0.0.0 Safari/537.36'
  ), {
    os: 'macOS 10.15.7',
    browser: 'Chrome 140.0.0.0',
    userAgent: 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 Chrome/140.0.0.0 Safari/537.36'
  })
})

test('failed login audit contains safe metadata but no credentials', () => {
  const event = createLoginFailureAuditEvent(request({
    'cf-connecting-ip': '203.0.113.7',
    'cf-ray': 'abc123-SJC',
    'user-agent': 'Mozilla/5.0 (iPhone; CPU iPhone OS 18_6 like Mac OS X) Version/18.6 Mobile Safari/604.1',
    'accept-language': 'en-US,en;q=0.9'
  }), 'invalid_credentials', {
    timeZone: 'America/Los_Angeles',
    utcOffsetMinutes: -420,
    locale: 'en-US',
    password: 'must-not-be-logged'
  }, new Date('2026-08-24T05:00:00.000Z'))

  assert.equal(event.event, 'login_failed')
  assert.equal(event.timestamp, '2026-08-24T05:00:00.000Z')
  assert.equal(event.network.ip, '203.0.113.7')
  assert.equal(event.client.os, 'iOS 18.6')
  assert.equal(event.client.browser, 'Safari 18.6')
  assert.equal(event.client.timeZone, 'America/Los_Angeles')
  assert.equal(event.client.utcOffsetMinutes, -420)
  assert.equal(event.client.locale, 'en-US')
  assert.equal(JSON.stringify(event).includes('must-not-be-logged'), false)
})
