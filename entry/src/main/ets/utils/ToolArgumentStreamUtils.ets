enum PrefixResult {
  COMPLETE,
  INCOMPLETE,
  INVALID
}

// Validates JSON syntax prefixes without repairing or discarding argument characters.
// Used only to distinguish a cumulative snapshot from a legitimate incremental fragment.
class JsonPrefixReader {
  private source: string
  private offset: number = 0

  constructor(source: string) {
    this.source = source
  }

  isPossible(): boolean {
    this.skipSpace()
    if (this.atEnd()) {
      return true
    }
    const state = this.value(0)
    if (state === PrefixResult.INCOMPLETE) {
      return true
    }
    this.skipSpace()
    return state === PrefixResult.COMPLETE && this.atEnd()
  }

  private atEnd(): boolean {
    return this.offset >= this.source.length
  }

  private skipSpace(): void {
    while (!this.atEnd() && ' \t\r\n'.includes(this.source[this.offset])) {
      this.offset++
    }
  }

  private value(depth: number): PrefixResult {
    this.skipSpace()
    // Conservative at excessive depth: do not use an uncertain parse to discard a delta.
    if (this.atEnd() || depth > 128) {
      return PrefixResult.INCOMPLETE
    }
    const ch = this.source[this.offset]
    if (ch === '"') {
      return this.string()
    }
    if (ch === '{' || ch === '[') {
      return this.container(ch === '{', depth + 1)
    }
    if (ch === 't' || ch === 'f' || ch === 'n') {
      const literal: string = ch === 't' ? 'true' : (ch === 'f' ? 'false' : 'null')
      for (let i = 0; i < literal.length; i++) {
        if (this.atEnd()) {
          return PrefixResult.INCOMPLETE
        }
        if (this.source[this.offset++] !== literal[i]) {
          return PrefixResult.INVALID
        }
      }
      return PrefixResult.COMPLETE
    }
    if (ch === '-' || this.isDigit(ch)) {
      return this.number()
    }
    return PrefixResult.INVALID
  }

  private string(): PrefixResult {
    this.offset++
    while (!this.atEnd()) {
      const ch = this.source[this.offset++]
      if (ch === '"') {
        return PrefixResult.COMPLETE
      }
      if (ch.charCodeAt(0) < 32) {
        return PrefixResult.INVALID
      }
      if (ch === '\\') {
        if (this.atEnd()) {
          return PrefixResult.INCOMPLETE
        }
        const escaped = this.source[this.offset++]
        if (escaped === 'u') {
          for (let i = 0; i < 4; i++) {
            if (this.atEnd()) {
              return PrefixResult.INCOMPLETE
            }
            if (!'0123456789abcdefABCDEF'.includes(this.source[this.offset++])) {
              return PrefixResult.INVALID
            }
          }
        } else if (!'"\\/bfnrt'.includes(escaped)) {
          return PrefixResult.INVALID
        }
      }
    }
    return PrefixResult.INCOMPLETE
  }

  private container(isObject: boolean, depth: number): PrefixResult {
    const close = isObject ? '}' : ']'
    this.offset++
    this.skipSpace()
    if (this.atEnd()) {
      return PrefixResult.INCOMPLETE
    }
    if (this.source[this.offset] === close) {
      this.offset++
      return PrefixResult.COMPLETE
    }
    while (!this.atEnd()) {
      if (isObject) {
        if (this.source[this.offset] !== '"') {
          return PrefixResult.INVALID
        }
        const keyState = this.string()
        if (keyState !== PrefixResult.COMPLETE) {
          return keyState
        }
        this.skipSpace()
        if (this.atEnd()) {
          return PrefixResult.INCOMPLETE
        }
        if (this.source[this.offset++] !== ':') {
          return PrefixResult.INVALID
        }
      }
      const valueState = this.value(depth)
      if (valueState !== PrefixResult.COMPLETE) {
        return valueState
      }
      this.skipSpace()
      if (this.atEnd()) {
        return PrefixResult.INCOMPLETE
      }
      const delimiter = this.source[this.offset++]
      if (delimiter === close) {
        return PrefixResult.COMPLETE
      }
      if (delimiter !== ',') {
        return PrefixResult.INVALID
      }
      this.skipSpace()
    }
    return PrefixResult.INCOMPLETE
  }

  private isDigit(ch: string): boolean {
    return ch >= '0' && ch <= '9'
  }

  private number(): PrefixResult {
    if (this.source[this.offset] === '-') {
      this.offset++
    }
    if (this.atEnd()) {
      return PrefixResult.INCOMPLETE
    }
    if (!this.isDigit(this.source[this.offset])) {
      return PrefixResult.INVALID
    }
    if (this.source[this.offset] === '0') {
      this.offset++
    } else {
      while (!this.atEnd() && this.isDigit(this.source[this.offset])) {
        this.offset++
      }
    }
    if (this.source[this.offset] === '.') {
      this.offset++
      if (this.atEnd()) {
        return PrefixResult.INCOMPLETE
      }
      if (!this.isDigit(this.source[this.offset])) {
        return PrefixResult.INVALID
      }
      while (!this.atEnd() && this.isDigit(this.source[this.offset])) {
        this.offset++
      }
    }
    if (this.source[this.offset] === 'e' || this.source[this.offset] === 'E') {
      this.offset++
      if (this.source[this.offset] === '+' || this.source[this.offset] === '-') {
        this.offset++
      }
      if (this.atEnd()) {
        return PrefixResult.INCOMPLETE
      }
      if (!this.isDigit(this.source[this.offset])) {
        return PrefixResult.INVALID
      }
      while (!this.atEnd() && this.isDigit(this.source[this.offset])) {
        this.offset++
      }
    }
    return PrefixResult.COMPLETE
  }
}

export function isPossibleToolArgumentsJsonPrefix(source: string): boolean {
  return new JsonPrefixReader(source).isPossible()
}

export function mergeToolArgumentDelta(previous: string, incoming: string): string {
  if (previous === '') {
    return incoming
  }
  if (incoming === '') {
    return previous
  }
  const appended = previous + incoming
  // Short fragments such as {, {", [ and repeated string characters are data,
  // not stale snapshots. If concatenation can still be valid JSON, preserve it.
  // Explicit object/Responses snapshots are handled by argumentsAreSnapshot upstream.
  if (incoming.length >= previous.length && incoming.startsWith(previous) &&
    !isPossibleToolArgumentsJsonPrefix(appended) && isPossibleToolArgumentsJsonPrefix(incoming)) {
    return incoming
  }
  return appended
}
