export default function handleImgText(text: string): string[] {
  return text.split(/(\!\[.*?\))/g)
}