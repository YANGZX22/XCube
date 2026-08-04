export namespace WebImpl {
  export function canBeLoadedAsWebComponentURL(src: string) {
    // 正则判断 http/https 协议 + 域名 + 可选路径参数
    const pattern = /^(https?):\/\/[^\s/$.?#].[^\s]*$/i;
    return pattern.test(src.trim());
  }
}