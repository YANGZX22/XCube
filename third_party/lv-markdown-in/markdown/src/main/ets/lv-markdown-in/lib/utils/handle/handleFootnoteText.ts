export default function handleFootnoteText(text: string): string[] {
  return text.split(/(\[\^[^\]]+\]\([^\)]+\))/g)
}