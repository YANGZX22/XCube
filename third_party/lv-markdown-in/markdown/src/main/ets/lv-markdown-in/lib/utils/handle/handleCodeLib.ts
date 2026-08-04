export default function  handleCodeLib(text: string): string[] {
  let reg = (/([(\s=){}."])/gi)
  return text.split(reg)
}