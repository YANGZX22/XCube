export function determineCheckbox(text: string): boolean {
  return (text.trim().slice(0, 3) === '- [' && text.trim().indexOf(']') !== -1) ? true : false
}