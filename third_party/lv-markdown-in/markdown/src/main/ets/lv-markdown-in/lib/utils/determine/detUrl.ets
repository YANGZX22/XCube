export function determineUrl(text: string): boolean {
  return text.trim().indexOf('[') !== -1 && text.trim().indexOf('](') !== -1 && text.trim().indexOf(')') !== -1 &&
    text.trim().substring(text.trim().indexOf('[') + 1, text.trim().indexOf('[') + 2) != "^" ? true :
    false
}
