export function determineCode(text: string): boolean {
  return text.trim().slice(0, 3) == '```' ? true : false
}
