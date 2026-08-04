export default function handleUrlText(text: string): string[] {
  return text.split(/(\[[^\]]+\]\([^\)]+\))/g)
}