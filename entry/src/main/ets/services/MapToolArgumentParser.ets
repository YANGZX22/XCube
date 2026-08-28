import {
  MapCoordinateArgs,
  MapOpenRequest,
  MapSearchRouteRequest
} from './MapKitService'

interface RawMapCoordinateArgs {
  latitude?: number | string
  longitude?: number | string
  lat?: number | string
  lng?: number | string
  lon?: number | string
}

interface RawMapToolArguments {
  action?: string
  query?: string
  nearby?: boolean | string
  useCurrentLocation?: boolean | string
  use_current_location?: boolean | string
  center?: MapCoordinateArgs | string
  origin?: string
  originLocation?: MapCoordinateArgs | string
  origin_location?: MapCoordinateArgs | string
  originSiteId?: string
  origin_site_id?: string
  destination?: string
  destinationSiteId?: string
  destination_site_id?: string
  destinationLocation?: MapCoordinateArgs | string
  destination_location?: MapCoordinateArgs | string
  coordinateType?: string
  coordinate_type?: string
  travelMode?: string
  travel_mode?: string
  radiusMeters?: number | string
  radius_meters?: number | string
  limit?: number | string
  includeDetails?: boolean | string
  include_details?: boolean | string
  language?: string
  center_latitude?: number | string
  center_longitude?: number | string
  centerLatitude?: number | string
  centerLongitude?: number | string
  origin_latitude?: number | string
  origin_longitude?: number | string
  originLatitude?: number | string
  originLongitude?: number | string
  destination_latitude?: number | string
  destination_longitude?: number | string
  destinationLatitude?: number | string
  destinationLongitude?: number | string
  arguments?: Object | string
  input?: Object | string
  params?: Object | string
  parameters?: Object | string
}

function stripJsonCodeFence(raw: string): string {
  const source = raw.trim()
  if (!source.startsWith('```')) {
    return source
  }
  const firstLineEnd = source.indexOf('\n')
  const closingFence = source.lastIndexOf('```')
  if (firstLineEnd < 0 || closingFence <= firstLineEnd) {
    return source
  }
  return source.substring(firstLineEnd + 1, closingFence).trim()
}

// 只补齐完整值尾部缺失的对象/数组闭合符；字符串被截断时拒绝修复。
export function repairTruncatedMapToolArguments(raw: string): string {
  const source = raw.trim()
  if (!source.startsWith('{')) {
    return ''
  }
  const stack: string[] = []
  let inString = false
  let escaped = false
  let rootClosed = false
  for (let i = 0; i < source.length; i++) {
    const character = source.charAt(i)
    if (inString) {
      if (escaped) {
        escaped = false
      } else if (character === '\\') {
        escaped = true
      } else if (character === '"') {
        inString = false
      }
      continue
    }
    if (character === '"') {
      inString = true
      continue
    }
    if (rootClosed) {
      if (character.trim() !== '') {
        return ''
      }
      continue
    }
    if (character === '{' || character === '[') {
      stack.push(character)
    } else if (character === '}' || character === ']') {
      if (stack.length === 0) {
        return ''
      }
      const expectedOpen = character === '}' ? '{' : '['
      if (stack[stack.length - 1] !== expectedOpen) {
        return ''
      }
      stack.pop()
      if (stack.length === 0) {
        rootClosed = true
      }
    }
  }
  if (inString || escaped || stack.length === 0) {
    return ''
  }
  const lastCharacter = source.charAt(source.length - 1)
  if (lastCharacter === ',' || lastCharacter === ':' || lastCharacter === '{' || lastCharacter === '[') {
    return ''
  }
  let repaired = source
  for (let i = stack.length - 1; i >= 0; i--) {
    repaired += stack[i] === '{' ? '}' : ']'
  }
  return repaired
}

function extractCompleteJsonObjects(raw: string): string[] {
  const objects: string[] = []
  const stack: string[] = []
  let start = -1
  let inString = false
  let escaped = false
  for (let i = 0; i < raw.length; i++) {
    const character = raw.charAt(i)
    if (inString) {
      if (escaped) {
        escaped = false
      } else if (character === '\\') {
        escaped = true
      } else if (character === '"') {
        inString = false
      }
      continue
    }
    if (character === '"') {
      inString = true
      continue
    }
    if (character === '{' || character === '[') {
      if (stack.length === 0 && character === '{') {
        start = i
      }
      stack.push(character)
      continue
    }
    if (character !== '}' && character !== ']') {
      continue
    }
    if (stack.length === 0) {
      start = -1
      continue
    }
    const expectedOpen = character === '}' ? '{' : '['
    if (stack[stack.length - 1] !== expectedOpen) {
      stack.length = 0
      start = -1
      continue
    }
    stack.pop()
    if (stack.length === 0 && start >= 0) {
      objects.push(raw.substring(start, i + 1))
      start = -1
    }
  }
  return objects
}

function hasMapArgumentField(value: Object): boolean {
  const args = value as RawMapToolArguments
  return args.action !== undefined || args.query !== undefined || args.destination !== undefined ||
    args.destination_location !== undefined || args.destination_latitude !== undefined ||
    args.origin !== undefined || args.origin_location !== undefined || args.origin_latitude !== undefined ||
    args.center !== undefined || args.center_latitude !== undefined || args.use_current_location !== undefined
}

function parseBestJsonValue(raw: string): Object | string {
  const source = stripJsonCodeFence(raw)
  try {
    return JSON.parse(source) as Object | string
  } catch (firstError) {
    const completeObjects = extractCompleteJsonObjects(source)
    let fallback: Object | null = null
    for (let i = completeObjects.length - 1; i >= 0; i--) {
      try {
        const candidate = JSON.parse(completeObjects[i]) as Object
        if (candidate !== null && hasMapArgumentField(candidate)) {
          return candidate
        }
        if (fallback === null) {
          fallback = candidate
        }
      } catch (_error) {}
    }
    if (fallback !== null) {
      return fallback
    }
    const repaired = repairTruncatedMapToolArguments(source)
    if (repaired !== '') {
      return JSON.parse(repaired) as Object
    }
    throw new Error(firstError instanceof Error ? firstError.message : JSON.stringify(firstError))
  }
}

function parseMapArgumentsObject(raw: string): RawMapToolArguments {
  let parsed = parseBestJsonValue(raw)
  for (let depth = 0; depth < 2 && typeof parsed === 'string'; depth++) {
    parsed = parseBestJsonValue(parsed)
  }
  if (typeof parsed === 'string' || parsed === null || Array.isArray(parsed)) {
    throw new Error('地图工具参数必须是 JSON 对象')
  }
  let args = parsed as RawMapToolArguments
  if (!hasMapArgumentField(args)) {
    const wrapped = args.arguments ?? args.input ?? args.params ?? args.parameters
    if (wrapped !== undefined) {
      if (typeof wrapped === 'string') {
        return parseMapArgumentsObject(wrapped)
      }
      if (wrapped !== null && !Array.isArray(wrapped)) {
        args = wrapped as RawMapToolArguments
      }
    }
  }
  return args
}

function parseCoordinateObject(value: MapCoordinateArgs | string | undefined): RawMapCoordinateArgs | null {
  if (value === undefined || value === null) {
    return null
  }
  let parsed: Object | string = value as Object | string
  if (typeof parsed === 'string') {
    try {
      parsed = JSON.parse(stripJsonCodeFence(parsed)) as Object | string
    } catch (_error) {
      return null
    }
  }
  if (typeof parsed === 'string' || parsed === null || Array.isArray(parsed)) {
    return null
  }
  return parsed as RawMapCoordinateArgs
}

function firstDefinedCoordinateValue(
  first: number | string | undefined,
  second: number | string | undefined,
  third?: number | string
): number | string | undefined {
  if (first !== undefined) {
    return first
  }
  if (second !== undefined) {
    return second
  }
  return third
}

function normalizeCoordinate(
  nested: MapCoordinateArgs | string | undefined,
  flatLatitude: number | string | undefined,
  flatLongitude: number | string | undefined
): MapCoordinateArgs | undefined {
  const raw = parseCoordinateObject(nested)
  const latitude = raw !== null ? firstDefinedCoordinateValue(raw.latitude, raw.lat, flatLatitude) : flatLatitude
  const longitude = raw !== null ?
    firstDefinedCoordinateValue(raw.longitude, raw.lng, raw.lon !== undefined ? raw.lon : flatLongitude) : flatLongitude
  if (latitude === undefined && longitude === undefined) {
    return undefined
  }
  return { latitude: latitude, longitude: longitude }
}

function firstDefined(
  first: number | string | undefined,
  second: number | string | undefined
): number | string | undefined {
  return first !== undefined ? first : second
}

export function parseMapSearchRouteToolArguments(raw: string): MapSearchRouteRequest {
  const args = parseMapArgumentsObject(raw)
  const request = args as MapSearchRouteRequest
  const center = normalizeCoordinate(
    args.center,
    firstDefined(args.center_latitude, args.centerLatitude),
    firstDefined(args.center_longitude, args.centerLongitude)
  )
  const origin = normalizeCoordinate(
    args.origin_location ?? args.originLocation,
    firstDefined(args.origin_latitude, args.originLatitude),
    firstDefined(args.origin_longitude, args.originLongitude)
  )
  const destination = normalizeCoordinate(
    args.destination_location ?? args.destinationLocation,
    firstDefined(args.destination_latitude, args.destinationLatitude),
    firstDefined(args.destination_longitude, args.destinationLongitude)
  )
  if (center !== undefined) {
    request.center = center
  }
  if (origin !== undefined) {
    request.origin_location = origin
  }
  if (destination !== undefined) {
    request.destination_location = destination
  }
  return request
}

export function parseOpenMapRouteToolArguments(raw: string): MapOpenRequest {
  const args = parseMapArgumentsObject(raw)
  const request = args as MapOpenRequest
  const origin = normalizeCoordinate(
    args.origin_location ?? args.originLocation,
    firstDefined(args.origin_latitude, args.originLatitude),
    firstDefined(args.origin_longitude, args.originLongitude)
  )
  const destination = normalizeCoordinate(
    args.destination_location ?? args.destinationLocation,
    firstDefined(args.destination_latitude, args.destinationLatitude),
    firstDefined(args.destination_longitude, args.destinationLongitude)
  )
  if (origin !== undefined) {
    request.origin_location = origin
  }
  if (destination !== undefined) {
    request.destination_location = destination
  }
  return request
}
