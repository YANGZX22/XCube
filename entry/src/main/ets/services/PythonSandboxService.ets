export class PythonSandboxRequest {
  code?: string
  variables?: Record<string, Object>
  packages?: string[]
  max_iterations?: number | string
}

export class PythonSandboxResult {
  ok: boolean = true
  stdout: string[] = []
  result: string = ''
  variables: Record<string, Object> = {}
  warnings: string[] = []
  error: string = ''

  constructor(ok: boolean = true) {
    this.ok = ok
  }
}

class PyToken {
  type: string = ''
  value: string = ''

  constructor(type: string, value: string) {
    this.type = type
    this.value = value
  }
}

class PyRangeValue {
  values: number[] = []

  constructor(values: number[]) {
    this.values = values
  }
}

class PythonExpressionParser {
  private tokens: PyToken[]
  private index: number = 0
  private env: Record<string, Object>

  constructor(tokens: PyToken[], env: Record<string, Object>) {
    this.tokens = tokens
    this.env = env
  }

  parse(): Object {
    const value = this.parseAdditive()
    if (!this.isAtEnd()) {
      throw new Error(`无法解析表达式片段: ${this.peek().value}`)
    }
    return value
  }

  private parseAdditive(): Object {
    let left = this.parseMultiplicative()
    while (this.matchValue('+') || this.matchValue('-')) {
      const operator = this.previous().value
      const right = this.parseMultiplicative()
      if (operator === '+') {
        left = this.addValues(left, right)
      } else {
        left = this.toNumber(left) - this.toNumber(right)
      }
    }
    return left
  }

  private parseMultiplicative(): Object {
    let left = this.parsePower()
    while (this.matchValue('*') || this.matchValue('/') || this.matchValue('%')) {
      const operator = this.previous().value
      const right = this.parsePower()
      if (operator === '*') {
        left = this.toNumber(left) * this.toNumber(right)
      } else if (operator === '/') {
        left = this.toNumber(left) / this.toNumber(right)
      } else {
        left = this.toNumber(left) % this.toNumber(right)
      }
    }
    return left
  }

  private parsePower(): Object {
    let left = this.parseUnary()
    if (this.matchValue('**')) {
      const right = this.parsePower()
      left = Math.pow(this.toNumber(left), this.toNumber(right))
    }
    return left
  }

  private parseUnary(): Object {
    if (this.matchValue('-')) {
      return -this.toNumber(this.parseUnary())
    }
    if (this.matchValue('+')) {
      return this.toNumber(this.parseUnary())
    }
    return this.parsePrimary()
  }

  private parsePrimary(): Object {
    if (this.matchType('number')) {
      return Number(this.previous().value)
    }
    if (this.matchType('string')) {
      return this.previous().value
    }
    if (this.matchValue('(')) {
      const value = this.parseAdditive()
      this.consumeValue(')', '缺少右括号')
      return value
    }
    if (this.matchValue('[')) {
      const values: Object[] = []
      if (!this.checkValue(']')) {
        do {
          values.push(this.parseAdditive())
        } while (this.matchValue(','))
      }
      this.consumeValue(']', '缺少右方括号')
      return values
    }
    if (this.matchType('identifier')) {
      const name = this.previous().value
      if (this.matchValue('(')) {
        const args: Object[] = []
        if (!this.checkValue(')')) {
          do {
            args.push(this.parseAdditive())
          } while (this.matchValue(','))
        }
        this.consumeValue(')', '缺少函数右括号')
        return this.callFunction(name, args)
      }
      if (name === 'True') {
        return true
      }
      if (name === 'False') {
        return false
      }
      if (this.env[name] === undefined) {
        throw new Error(`未定义变量: ${name}`)
      }
      return this.env[name]
    }
    throw new Error(`无法解析表达式: ${this.peek().value}`)
  }

  private callFunction(name: string, args: Object[]): Object {
    const normalized = name === 'math.sqrt' ? 'sqrt' :
      (name === 'math.log' ? 'log' :
        (name === 'math.exp' ? 'exp' :
          (name === 'math.sin' ? 'sin' :
            (name === 'math.cos' ? 'cos' :
              (name === 'math.tan' ? 'tan' :
                (name === 'statistics.mean' ? 'mean' :
                  (name === 'statistics.median' ? 'median' :
                    (name === 'statistics.stdev' ? 'stdev' : name))))))))
    switch (normalized) {
      case 'abs':
        return Math.abs(this.toNumber(args[0]))
      case 'round':
        return Math.round(this.toNumber(args[0]))
      case 'sqrt':
        return Math.sqrt(this.toNumber(args[0]))
      case 'log':
        return Math.log(this.toNumber(args[0]))
      case 'exp':
        return Math.exp(this.toNumber(args[0]))
      case 'sin':
        return Math.sin(this.toNumber(args[0]))
      case 'cos':
        return Math.cos(this.toNumber(args[0]))
      case 'tan':
        return Math.tan(this.toNumber(args[0]))
      case 'len':
        return this.toArray(args[0]).length
      case 'sum':
        return this.toArray(args[0]).reduce((acc: number, value: Object) => acc + this.toNumber(value), 0)
      case 'min':
        return Math.min(...this.toArray(args[0]).map((value: Object) => this.toNumber(value)))
      case 'max':
        return Math.max(...this.toArray(args[0]).map((value: Object) => this.toNumber(value)))
      case 'mean':
        return this.callFunction('sum', args) as number / Math.max(1, this.toArray(args[0]).length)
      case 'median':
        return this.median(this.toArray(args[0]).map((value: Object) => this.toNumber(value)))
      case 'stdev':
        return this.stdev(this.toArray(args[0]).map((value: Object) => this.toNumber(value)))
      case 'range':
        return new PyRangeValue(this.buildRange(args))
      case 'sorted':
        return this.toArray(args[0]).slice().sort((a: Object, b: Object) => this.toNumber(a) - this.toNumber(b))
      default:
        throw new Error(`不支持的函数: ${name}`)
    }
  }

  private buildRange(args: Object[]): number[] {
    let start = 0
    let stop = 0
    let step = 1
    if (args.length === 1) {
      stop = Math.floor(this.toNumber(args[0]))
    } else if (args.length >= 2) {
      start = Math.floor(this.toNumber(args[0]))
      stop = Math.floor(this.toNumber(args[1]))
      if (args.length >= 3) {
        step = Math.floor(this.toNumber(args[2]))
      }
    }
    if (step === 0) {
      throw new Error('range step 不能为 0')
    }
    const result: number[] = []
    if (step > 0) {
      for (let i = start; i < stop && result.length < 10000; i += step) {
        result.push(i)
      }
    } else {
      for (let i = start; i > stop && result.length < 10000; i += step) {
        result.push(i)
      }
    }
    return result
  }

  private median(values: number[]): number {
    if (values.length === 0) {
      return 0
    }
    const sorted = values.slice().sort((a, b) => a - b)
    const mid = Math.floor(sorted.length / 2)
    return sorted.length % 2 === 1 ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2
  }

  private stdev(values: number[]): number {
    if (values.length <= 1) {
      return 0
    }
    const mean = values.reduce((acc, value) => acc + value, 0) / values.length
    let variance = 0
    for (let i = 0; i < values.length; i++) {
      variance += Math.pow(values[i] - mean, 2)
    }
    return Math.sqrt(variance / (values.length - 1))
  }

  private addValues(left: Object, right: Object): Object {
    if (typeof left === 'string' || typeof right === 'string') {
      return `${this.valueToText(left)}${this.valueToText(right)}`
    }
    if (Array.isArray(left as Array<Object>) && Array.isArray(right as Array<Object>)) {
      return (left as Object[]).concat(right as Object[])
    }
    return this.toNumber(left) + this.toNumber(right)
  }

  private toArray(value: Object | undefined): Object[] {
    if (value instanceof PyRangeValue) {
      return value.values
    }
    if (Array.isArray(value as Array<Object>)) {
      return value as Object[]
    }
    throw new Error('需要列表参数')
  }

  private toNumber(value: Object | undefined): number {
    if (typeof value === 'number') {
      return value
    }
    if (typeof value === 'boolean') {
      return value ? 1 : 0
    }
    const parsed = Number(value)
    if (Number.isNaN(parsed)) {
      throw new Error(`需要数字，实际为: ${this.valueToText(value)}`)
    }
    return parsed
  }

  private valueToText(value: Object | undefined): string {
    if (value instanceof PyRangeValue) {
      return `[${value.values.join(', ')}]`
    }
    if (Array.isArray(value as Array<Object>)) {
      return `[${(value as Object[]).map((item: Object) => this.valueToText(item)).join(', ')}]`
    }
    return `${value}`
  }

  private consumeValue(value: string, message: string): void {
    if (this.matchValue(value)) {
      return
    }
    throw new Error(message)
  }

  private matchType(type: string): boolean {
    if (this.checkType(type)) {
      this.index += 1
      return true
    }
    return false
  }

  private matchValue(value: string): boolean {
    if (this.checkValue(value)) {
      this.index += 1
      return true
    }
    return false
  }

  private checkType(type: string): boolean {
    return !this.isAtEnd() && this.peek().type === type
  }

  private checkValue(value: string): boolean {
    return !this.isAtEnd() && this.peek().value === value
  }

  private previous(): PyToken {
    return this.tokens[this.index - 1]
  }

  private peek(): PyToken {
    return this.tokens[this.index]
  }

  private isAtEnd(): boolean {
    return this.peek().type === 'eof'
  }
}

export class PythonSandboxService {
  private static instance: PythonSandboxService | null = null
  private readonly maxCodeLength: number = 6000
  private readonly maxLines: number = 160

  static getInstance(): PythonSandboxService {
    if (PythonSandboxService.instance === null) {
      PythonSandboxService.instance = new PythonSandboxService()
    }
    return PythonSandboxService.instance
  }

  run(request: PythonSandboxRequest): PythonSandboxResult {
    const result = new PythonSandboxResult(true)
    const code = (request.code ?? '').trim()
    if (code === '') {
      return this.fail('缺少 Python 代码')
    }
    if (code.length > this.maxCodeLength) {
      return this.fail(`代码过长，最多 ${this.maxCodeLength} 字符`)
    }

    const env = this.buildInitialEnvironment(request.variables)
    const lines = code.split(/\r?\n/)
    if (lines.length > this.maxLines) {
      return this.fail(`代码行数过多，最多 ${this.maxLines} 行`)
    }

    try {
      const maxIterations = this.resolveMaxIterations(request.max_iterations)
      const lastValue = this.executeBlock(lines, 0, lines.length, 0, env, result.stdout, maxIterations)
      result.result = this.formatValue(lastValue)
      result.variables = this.serializeEnvironment(env)
      return result
    } catch (error) {
      const failed = new PythonSandboxResult(false)
      failed.stdout = result.stdout
      failed.variables = this.serializeEnvironment(env)
      failed.error = error instanceof Error ? error.message : JSON.stringify(error)
      return failed
    }
  }

  private executeBlock(
    lines: string[],
    start: number,
    end: number,
    indent: number,
    env: Record<string, Object>,
    stdout: string[],
    maxIterations: number
  ): Object {
    let lastValue: Object = ''
    let i = start
    let iterationCount = 0
    while (i < end) {
      const rawLine = lines[i]
      if (rawLine.trim() === '' || rawLine.trim().startsWith('#')) {
        i += 1
        continue
      }
      const lineIndent = this.countIndent(rawLine)
      if (lineIndent < indent) {
        break
      }
      if (lineIndent > indent) {
        throw new Error(`第 ${i + 1} 行缩进不符合预期`)
      }
      const line = this.stripComment(rawLine.trim())
      if (line === '') {
        i += 1
        continue
      }
      if (line.startsWith('for ') && line.endsWith(':')) {
        const bodyStart = i + 1
        let bodyEnd = bodyStart
        while (bodyEnd < end && (lines[bodyEnd].trim() === '' || this.countIndent(lines[bodyEnd]) > lineIndent)) {
          bodyEnd += 1
        }
        const loopInfo = this.parseForLine(line)
        const iterable = this.toIterable(this.evaluateExpression(loopInfo[1], env))
        for (let j = 0; j < iterable.length; j++) {
          iterationCount += 1
          if (iterationCount > maxIterations) {
            throw new Error(`循环次数超过限制 ${maxIterations}`)
          }
          env[loopInfo[0]] = iterable[j]
          lastValue = this.executeBlock(lines, bodyStart, bodyEnd, lineIndent + 2, env, stdout, maxIterations)
        }
        i = bodyEnd
        continue
      }
      lastValue = this.executeLine(line, env, stdout)
      i += 1
    }
    return lastValue
  }

  private executeLine(line: string, env: Record<string, Object>, stdout: string[]): Object {
    if (line === 'import math' || line === 'import statistics' || line === 'from math import *') {
      return ''
    }
    if (line.startsWith('print(') && line.endsWith(')')) {
      const value = this.evaluateExpression(line.substring(6, line.length - 1), env)
      stdout.push(this.formatValue(value))
      return value
    }
    const augmented = /^([A-Za-z_][A-Za-z0-9_]*)\s*(\+=|-=|\*=|\/=)\s*(.+)$/.exec(line)
    if (augmented !== null) {
      const name = augmented[1]
      const current = env[name] ?? 0
      const value = this.evaluateExpression(augmented[3], env)
      if (augmented[2] === '+=') {
        env[name] = this.evaluateExpression(`${this.formatForExpression(current)} + ${this.formatForExpression(value)}`, env)
      } else if (augmented[2] === '-=') {
        env[name] = (Number(current) - Number(value)) as Object
      } else if (augmented[2] === '*=') {
        env[name] = (Number(current) * Number(value)) as Object
      } else {
        env[name] = (Number(current) / Number(value)) as Object
      }
      return env[name]
    }
    const assignmentIndex = this.findTopLevelAssignment(line)
    if (assignmentIndex > 0) {
      const name = line.substring(0, assignmentIndex).trim()
      if (!/^[A-Za-z_][A-Za-z0-9_]*$/.test(name)) {
        throw new Error(`不支持的赋值目标: ${name}`)
      }
      const value = this.evaluateExpression(line.substring(assignmentIndex + 1), env)
      env[name] = value
      return value
    }
    return this.evaluateExpression(line, env)
  }

  private evaluateExpression(expression: string, env: Record<string, Object>): Object {
    const tokens = this.tokenize(expression)
    return new PythonExpressionParser(tokens, env).parse()
  }

  private tokenize(expression: string): PyToken[] {
    const tokens: PyToken[] = []
    let i = 0
    while (i < expression.length) {
      const ch = expression[i]
      if (/\s/.test(ch)) {
        i += 1
        continue
      }
      if (/[0-9.]/.test(ch)) {
        let j = i
        while (j < expression.length && /[0-9.]/.test(expression[j])) {
          j += 1
        }
        tokens.push(new PyToken('number', expression.substring(i, j)))
        i = j
        continue
      }
      if (ch === '"' || ch === "'") {
        const quote = ch
        let j = i + 1
        let value = ''
        while (j < expression.length && expression[j] !== quote) {
          value += expression[j]
          j += 1
        }
        if (j >= expression.length) {
          throw new Error('字符串缺少结束引号')
        }
        tokens.push(new PyToken('string', value))
        i = j + 1
        continue
      }
      if (/[A-Za-z_]/.test(ch)) {
        let j = i
        while (j < expression.length && /[A-Za-z0-9_.]/.test(expression[j])) {
          j += 1
        }
        tokens.push(new PyToken('identifier', expression.substring(i, j)))
        i = j
        continue
      }
      if (expression.substring(i, i + 2) === '**') {
        tokens.push(new PyToken('operator', '**'))
        i += 2
        continue
      }
      if ('+-*/%(),[]'.includes(ch)) {
        tokens.push(new PyToken('operator', ch))
        i += 1
        continue
      }
      throw new Error(`不支持的字符: ${ch}`)
    }
    tokens.push(new PyToken('eof', ''))
    return tokens
  }

  private parseForLine(line: string): string[] {
    const match = /^for\s+([A-Za-z_][A-Za-z0-9_]*)\s+in\s+(.+):$/.exec(line)
    if (match === null) {
      throw new Error(`不支持的 for 语句: ${line}`)
    }
    return [match[1], match[2]]
  }

  private toIterable(value: Object): Object[] {
    if (value instanceof PyRangeValue) {
      return value.values
    }
    if (Array.isArray(value as Array<Object>)) {
      return value as Object[]
    }
    throw new Error('for 语句需要列表或 range')
  }

  private buildInitialEnvironment(input: Record<string, Object> | undefined): Record<string, Object> {
    const env: Record<string, Object> = {}
    if (input === undefined) {
      return env
    }
    const keys = Object.keys(input)
    for (let i = 0; i < keys.length; i++) {
      if (/^[A-Za-z_][A-Za-z0-9_]*$/.test(keys[i])) {
        env[keys[i]] = input[keys[i]]
      }
    }
    return env
  }

  private serializeEnvironment(env: Record<string, Object>): Record<string, Object> {
    const result: Record<string, Object> = {}
    const keys = Object.keys(env)
    for (let i = 0; i < keys.length; i++) {
      const value = env[keys[i]]
      if (value instanceof PyRangeValue) {
        result[keys[i]] = value.values
      } else {
        result[keys[i]] = value
      }
    }
    return result
  }

  private findTopLevelAssignment(line: string): number {
    let depth = 0
    let quote = ''
    for (let i = 0; i < line.length; i++) {
      const ch = line[i]
      if (quote !== '') {
        if (ch === quote) {
          quote = ''
        }
        continue
      }
      if (ch === '"' || ch === "'") {
        quote = ch
        continue
      }
      if (ch === '(' || ch === '[') {
        depth += 1
      } else if (ch === ')' || ch === ']') {
        depth -= 1
      } else if (ch === '=' && depth === 0 && line[i - 1] !== '=' && line[i + 1] !== '=') {
        return i
      }
    }
    return -1
  }

  private countIndent(line: string): number {
    let count = 0
    while (count < line.length && line[count] === ' ') {
      count += 1
    }
    return count
  }

  private stripComment(line: string): string {
    let quote = ''
    for (let i = 0; i < line.length; i++) {
      const ch = line[i]
      if (quote !== '') {
        if (ch === quote) {
          quote = ''
        }
        continue
      }
      if (ch === '"' || ch === "'") {
        quote = ch
        continue
      }
      if (ch === '#') {
        return line.substring(0, i).trim()
      }
    }
    return line.trim()
  }

  private formatValue(value: Object | undefined): string {
    if (value instanceof PyRangeValue) {
      return `[${value.values.join(', ')}]`
    }
    if (Array.isArray(value as Array<Object>)) {
      return `[${(value as Object[]).map((item: Object) => this.formatValue(item)).join(', ')}]`
    }
    return `${value ?? ''}`
  }

  private formatForExpression(value: Object): string {
    if (typeof value === 'string') {
      return `"${value.replace(/"/g, '\\"')}"`
    }
    if (Array.isArray(value as Array<Object>)) {
      return `[${(value as Object[]).map((item: Object) => this.formatForExpression(item)).join(', ')}]`
    }
    return `${value}`
  }

  private resolveMaxIterations(value: number | string | undefined): number {
    if (value === undefined) {
      return 10000
    }
    const parsed = Number(value)
    if (Number.isNaN(parsed)) {
      return 10000
    }
    return Math.min(Math.max(Math.floor(parsed), 1), 50000)
  }

  private fail(error: string): PythonSandboxResult {
    const result = new PythonSandboxResult(false)
    result.error = error
    return result
  }
}

export function getPythonSandboxService(): PythonSandboxService {
  return PythonSandboxService.getInstance()
}
