export function determineImg(text: string): boolean {
  return text.trim().indexOf('![') !== -1 && text.trim().indexOf('](') !== -1 && text.trim().indexOf(')') !== -1 ? true : false
}
