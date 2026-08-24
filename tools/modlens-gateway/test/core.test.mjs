import test from 'node:test'
import assert from 'node:assert/strict'
import {
  isLoopbackHost,
  isModLensOutput,
  sanitizeFileName,
  sniffImageMime,
  validateAnalyzePayload
} from '../src/core.mjs'

const onePixelPng = Buffer.from(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
  'base64'
)

test('sniffImageMime detects supported signatures', () => {
  assert.equal(sniffImageMime(onePixelPng), 'image/png')
  assert.equal(sniffImageMime(Buffer.from([0xff, 0xd8, 0xff, 0x00])), 'image/jpeg')
  assert.equal(sniffImageMime(Buffer.from('not an image')), '')
})

test('validateAnalyzePayload validates and normalizes input', () => {
  const payload = validateAnalyzePayload({
    image: {
      data: onePixelPng.toString('base64'),
      mimeType: 'text/plain',
      fileName: '../../screen.exe'
    },
    prompt: 'read the chart'
  })
  assert.equal(payload.mimeType, 'image/png')
  assert.equal(payload.fileName, 'screen.png')
  assert.equal(payload.prompt, 'read the chart')
})

test('validateAnalyzePayload rejects non-images', () => {
  assert.throws(() => validateAnalyzePayload({
    image: { data: Buffer.from('hello').toString('base64') }
  }), /Unsupported or invalid image format/)
  assert.throws(() => validateAnalyzePayload({
    image: { data: Buffer.from([0x42, 0x4d, 0x00, 0x00]).toString('base64') }
  }), /Unsupported or invalid image format/)
  assert.throws(() => validateAnalyzePayload({
    image: { data: Buffer.from([0x00, 0x00, 0x00, 0x18, 0x66, 0x74, 0x79, 0x70, 0x68, 0x65, 0x69, 0x63]).toString('base64') }
  }), /Unsupported or invalid image format/)
})

test('ModLens schema check requires structured evidence', () => {
  assert.equal(isModLensOutput({
    provider: 'gemini-api',
    result: {
      summary: 'A chart',
      ocr: {},
      layout: {},
      semantics: {},
      visual: {},
      uncertainty: []
    }
  }), true)
  assert.equal(isModLensOutput({ provider: 'gemini-api', result: { summary: 'A chart' } }), false)
})

test('network and filename safety helpers are conservative', () => {
  assert.equal(isLoopbackHost('127.0.0.1'), true)
  assert.equal(isLoopbackHost('::1'), true)
  assert.equal(isLoopbackHost('0.0.0.0'), false)
  assert.equal(sanitizeFileName('报告 2026.jpeg', 'image/jpeg'), '_2026.jpeg')
})
