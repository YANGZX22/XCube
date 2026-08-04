function parseVersionSegments(version: string): number[] | null {
  let normalized = version.trim()
  if (normalized.startsWith('v') || normalized.startsWith('V')) {
    normalized = normalized.substring(1)
  }

  const suffixIndex = normalized.search(/[-+]/)
  if (suffixIndex >= 0) {
    normalized = normalized.substring(0, suffixIndex)
  }
  if (normalized === '') {
    return null
  }

  const rawSegments = normalized.split('.')
  const segments: number[] = []
  for (let i = 0; i < rawSegments.length; i++) {
    const rawSegment = rawSegments[i]
    if (!/^\d+$/.test(rawSegment)) {
      return null
    }
    segments.push(Number.parseInt(rawSegment, 10))
  }
  return segments
}

export function normalizeAppVersion(version: string): string {
  let normalized = version.trim()
  if (normalized.startsWith('v') || normalized.startsWith('V')) {
    normalized = normalized.substring(1)
  }
  return normalized
}

export function isAppVersionNewer(candidateVersion: string, currentVersion: string): boolean {
  const candidate = parseVersionSegments(candidateVersion)
  const current = parseVersionSegments(currentVersion)
  if (candidate === null || current === null) {
    return false
  }

  const segmentCount = Math.max(candidate.length, current.length)
  for (let i = 0; i < segmentCount; i++) {
    const candidateSegment = i < candidate.length ? candidate[i] : 0
    const currentSegment = i < current.length ? current[i] : 0
    if (candidateSegment > currentSegment) {
      return true
    }
    if (candidateSegment < currentSegment) {
      return false
    }
  }
  return false
}
