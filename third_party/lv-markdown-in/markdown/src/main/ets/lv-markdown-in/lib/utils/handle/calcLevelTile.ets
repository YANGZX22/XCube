export default function calcLevelTile(text: string): number {
  let size: number = 0
  text.slice(0, 6).split('').forEach((item: string) => item == '#' ? ++size : size)
  return size
}