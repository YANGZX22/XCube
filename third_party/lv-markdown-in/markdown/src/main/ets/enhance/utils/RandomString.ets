export function generateRandomString(): string {
  // 定义字母（包含大小写）和数字字符集
  const letters: string = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz';
  const numbers: string = '0123456789';
  const allChars: string = letters + numbers;

  // 第一个字符必须是字母（随机大小写）
  const firstChar: string = letters[Math.floor(Math.random() * letters.length)];

  // 生成剩余9个字符（字母或数字）
  let result: string = firstChar;
  for (let i = 1; i < 10; i++) {
    const randomIndex: number = Math.floor(Math.random() * allChars.length);
    result += allChars[randomIndex];
  }

  return result;
}
