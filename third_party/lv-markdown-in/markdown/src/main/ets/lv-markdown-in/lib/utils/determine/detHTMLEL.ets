export function determineHTMLIMG(text: string): boolean {
  return text.trim().indexOf('<img') !== -1 && text.trim().indexOf('src=') !== -1 ? true : false
}

export function determineHTMLFONT(text: string): boolean {
  return text.trim().indexOf('<font') !== -1 && text.trim().indexOf('font>') !== -1 ? true : false
}
