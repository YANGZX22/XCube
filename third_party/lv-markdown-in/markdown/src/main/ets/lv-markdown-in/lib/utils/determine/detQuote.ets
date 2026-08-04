export function determineQuote(text: string): boolean {
  return text.trim().slice(0, 1) === '>' ? true : false
}
