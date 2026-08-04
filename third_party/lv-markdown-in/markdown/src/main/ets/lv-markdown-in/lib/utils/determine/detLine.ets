export function determineLine(text: string): boolean {
  return text.trim().slice(0, 3) === '---' || text.trim().slice(0, 3) === '***' ? true : false
}
