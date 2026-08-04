export function determineTable(text: string): boolean {
  return text.split('|').length - 1 > 2 ? true : false
}
