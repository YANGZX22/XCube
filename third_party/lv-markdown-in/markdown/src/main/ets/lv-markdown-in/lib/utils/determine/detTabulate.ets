function isNumeric(str: string) {
  const regex = /^\d+$/;
  return regex.test(str);
}

export function determineTabulate(text: string, textPre: string, textNext: string): boolean {
  let check = text.trim().split(".")
  let checkPre = textPre?.trim().split(".")
  let checkNext = textNext?.trim().split(".")
  if (
    (check.length > 1 && isNumeric(check[0]) && checkPre.length > 1 && isNumeric(checkPre[0])) ||
      (check.length > 1 && isNumeric(check[0]) && checkNext.length > 1 && isNumeric(checkNext[0]))
  ) {
    return true
  }
  const textP1 = text.trim().slice(0, 1)
  const textP2 = text.trim().slice(1, 2)
  return ((textP1 === '*' && textP2 !== '*') || textP1 === '-' || textP1 === '+') ? true : false
}