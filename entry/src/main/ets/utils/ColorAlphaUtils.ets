export function withColorAlpha(color: string | null | undefined, alphaHex: string | null | undefined): string {
  const fallbackColor = 'rgba(0, 0, 0, 0)'
  const safeColor = typeof color === 'string' && color !== '' ? color : fallbackColor
  const normalizedAlpha = normalizeAlphaHex(alphaHex)
  if (!isHexColor(safeColor) || normalizedAlpha === '') {
    return safeColor
  }
  if (safeColor.length === 4) {
    return '#' + normalizedAlpha + safeColor.charAt(1) + safeColor.charAt(1) + safeColor.charAt(2) + safeColor.charAt(2) +
      safeColor.charAt(3) + safeColor.charAt(3)
  }
  if (safeColor.length === 7) {
    return '#' + normalizedAlpha + safeColor.substring(1)
  }
  if (safeColor.length === 9) {
    return '#' + normalizedAlpha + safeColor.substring(3)
  }
  return safeColor
}

function normalizeAlphaHex(alphaHex: string | null | undefined): string {
  let value = typeof alphaHex === 'string' ? alphaHex : ''
  if (value.startsWith('#')) {
    value = value.substring(1)
  }
  if (value.length !== 2) {
    return ''
  }
  if (!isHexPair(value)) {
    return ''
  }
  return value.toUpperCase()
}

function isHexColor(color: string): boolean {
  if (color === '') {
    return false
  }
  if (!color.startsWith('#')) {
    return false
  }
  if (color.length !== 4 && color.length !== 7 && color.length !== 9) {
    return false
  }
  for (let i = 1; i < color.length; i++) {
    if (!isHexChar(color.charAt(i))) {
      return false
    }
  }
  return true
}

function isHexPair(value: string): boolean {
  return isHexChar(value.charAt(0)) && isHexChar(value.charAt(1))
}

function isHexChar(value: string): boolean {
  return (value >= '0' && value <= '9') || (value >= 'a' && value <= 'f') || (value >= 'A' && value <= 'F')
}
