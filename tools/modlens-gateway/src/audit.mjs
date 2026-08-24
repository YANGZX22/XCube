import { isIP } from 'node:net'

const MAX_USER_AGENT_LENGTH = 512
const MAX_METADATA_LENGTH = 128

function headerValue(request, name) {
  const value = request.headers?.[name]
  if (Array.isArray(value)) {
    return value[0] ?? ''
  }
  return typeof value === 'string' ? value : ''
}

function safeText(value, maximumLength = MAX_METADATA_LENGTH) {
  return typeof value === 'string'
    ? value.replace(/[\u0000-\u001f\u007f]/g, '').trim().slice(0, maximumLength)
    : ''
}

function validIp(value) {
  const candidate = safeText(value, 128)
  return isIP(candidate) === 0 ? '' : candidate
}

export function getAuditClientIp(request) {
  const cloudflareIp = validIp(headerValue(request, 'cf-connecting-ip'))
  if (cloudflareIp !== '') {
    return { address: cloudflareIp, source: 'cf-connecting-ip' }
  }

  const forwardedFor = headerValue(request, 'x-forwarded-for')
    .split(',')
    .map((value) => validIp(value))
    .find((value) => value !== '')
  if (forwardedFor !== undefined) {
    return { address: forwardedFor, source: 'x-forwarded-for' }
  }

  const peerAddress = validIp(request.socket?.remoteAddress)
  return {
    address: peerAddress || 'unknown',
    source: peerAddress ? 'socket' : 'unavailable'
  }
}

export function parseUserAgent(userAgentValue) {
  const userAgent = safeText(userAgentValue, MAX_USER_AGENT_LENGTH)
  let os = 'Unknown'
  let browser = 'Unknown'

  const windows = userAgent.match(/Windows NT ([0-9.]+)/i)
  const android = userAgent.match(/Android ([0-9.]+)/i)
  const ios = userAgent.match(/(?:iPhone OS|CPU(?: iPhone)? OS) ([0-9_]+)/i)
  const macos = userAgent.match(/Mac OS X ([0-9_]+)/i)
  const chromeOs = userAgent.match(/CrOS [^ ]+ ([0-9.]+)/i)
  if (windows) os = `Windows NT ${windows[1]}`
  else if (android) os = `Android ${android[1]}`
  else if (ios) os = `iOS ${ios[1].replaceAll('_', '.')}`
  else if (macos) os = `macOS ${macos[1].replaceAll('_', '.')}`
  else if (chromeOs) os = `ChromeOS ${chromeOs[1]}`
  else if (/Linux/i.test(userAgent)) os = 'Linux'

  const edge = userAgent.match(/Edg(?:A|iOS)?\/([0-9.]+)/i)
  const opera = userAgent.match(/(?:OPR|Opera)\/([0-9.]+)/i)
  const firefox = userAgent.match(/(?:Firefox|FxiOS)\/([0-9.]+)/i)
  const chrome = userAgent.match(/(?:Chrome|CriOS)\/([0-9.]+)/i)
  const safari = userAgent.match(/Version\/([0-9.]+).*Safari\//i)
  if (edge) browser = `Edge ${edge[1]}`
  else if (opera) browser = `Opera ${opera[1]}`
  else if (firefox) browser = `Firefox ${firefox[1]}`
  else if (chrome) browser = `Chrome ${chrome[1]}`
  else if (safari) browser = `Safari ${safari[1]}`

  return { userAgent, os, browser }
}

function parseClientMetadata(value) {
  if (value === null || typeof value !== 'object' || Array.isArray(value)) {
    return { timeZone: '', utcOffsetMinutes: null, locale: '' }
  }
  const timeZone = safeText(value.timeZone, 64)
  const locale = safeText(value.locale, 64)
  const utcOffsetMinutes = Number.isInteger(value.utcOffsetMinutes) &&
    value.utcOffsetMinutes >= -14 * 60 && value.utcOffsetMinutes <= 14 * 60
    ? value.utcOffsetMinutes
    : null
  return { timeZone, utcOffsetMinutes, locale }
}

export function createLoginFailureAuditEvent(request, reason, clientMetadata, now = new Date()) {
  const ip = getAuditClientIp(request)
  const agent = parseUserAgent(headerValue(request, 'user-agent'))
  const client = parseClientMetadata(clientMetadata)
  return {
    event: 'login_failed',
    timestamp: now.toISOString(),
    reason: safeText(reason, 64) || 'unknown',
    network: {
      ip: ip.address,
      ipSource: ip.source,
      cfRay: safeText(headerValue(request, 'cf-ray'), 128)
    },
    client: {
      os: agent.os,
      browser: agent.browser,
      userAgent: agent.userAgent,
      timeZone: client.timeZone,
      utcOffsetMinutes: client.utcOffsetMinutes,
      locale: client.locale,
      acceptLanguage: safeText(headerValue(request, 'accept-language'), 128)
    }
  }
}

export function logLoginFailure(request, reason, clientMetadata) {
  const event = createLoginFailureAuditEvent(request, reason, clientMetadata)
  console.warn(`[modlens-gateway:audit] ${JSON.stringify(event)}`)
}
