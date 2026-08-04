import { LatexMathColorFormat, latexStringToImageWithError, TeXResultCode } from '@cangjie-tpc/formula_hybrid';
import { image } from '@kit.ImageKit';
import { common } from '@kit.AbilityKit';

export interface LatexInfo {
  pixelMap: image.PixelMap,
  width: number
  height: number
}

export namespace LatexUtil {
  // 缓存数学公式图片，键为公式文本、字体大小和颜色的组合
  const latexCache: Map<string, LatexInfo> = new Map();
  // 维护插入顺序用于 FIFO 淘汰，避免流式过程中部分公式不断生成导致缓存无界增长
  const latexCacheOrder: string[] = [];
  const MAX_CACHE_SIZE = 128;

  function stripLatexDelimiters(latexText: string): string {
    let text = latexText.trim();
    if (text.length >= 4 && text.startsWith('\\[') && text.endsWith('\\]')) {
      return text.substring(2, text.length - 2).trim();
    }
    if (text.length >= 4 && text.startsWith('\\(') && text.endsWith('\\)')) {
      return text.substring(2, text.length - 2).trim();
    }
    if (text.length >= 4 && text.startsWith('$$') && text.endsWith('$$')) {
      return text.substring(2, text.length - 2).trim();
    }
    if (text.length >= 2 && text.startsWith('$') && text.endsWith('$')) {
      return text.substring(1, text.length - 1).trim();
    }
    return text;
  }

  function normalizeBareFractions(latexText: string): string {
    return latexText
      .replace(/\\(dfrac|tfrac|cfrac|frac)\s+([A-Za-z0-9])\s+([A-Za-z0-9])/g, '\\$1{$2}{$3}')
      .replace(/\\(dfrac|tfrac|cfrac|frac)([A-Za-z0-9])([A-Za-z0-9])/g, '\\$1{$2}{$3}');
  }

  function normalizeLatexText(latexText: string): string {
    let text = stripLatexDelimiters(latexText);
    text = text.replace(/\r\n?/g, '\n').replace(/\n+/g, ' ').replace(/\s+/g, ' ').trim();
    return normalizeBareFractions(text);
  }

  function buildCacheKey(latexText: string, latexMathTextSize: number, latexMathTextColor: number): string {
    return `${latexText}_${latexMathTextSize}_${latexMathTextColor}`;
  }

  function saveCache(cacheKey: string, latexInfo: LatexInfo) {
    if (!latexCache.has(cacheKey)) {
      latexCacheOrder.push(cacheKey);
    }
    latexCache.set(cacheKey, latexInfo);
    while (latexCacheOrder.length > MAX_CACHE_SIZE) {
      const oldKey = latexCacheOrder.shift();
      if (oldKey !== undefined) {
        latexCache.delete(oldKey);
      }
    }
  }

  export function latexToPixelMap(latexText: string, latexMathTextSize: number,
    latexMathTextColor: number, context: UIContext): Promise<LatexInfo> {
    const normalizedLatexText = normalizeLatexText(latexText);
    if (!normalizedLatexText) {
      return Promise.reject('empty latex text');
    }
    // 生成缓存键
    const cacheKey = buildCacheKey(normalizedLatexText, latexMathTextSize, latexMathTextColor);

    // 检查缓存中是否已有该公式的图片
    if (latexCache.has(cacheKey)) {
      return Promise.resolve(latexCache.get(cacheKey)!);
    }

    let abilityStageContext = getContext() as common.AbilityStageContext;
    // 获取当前模块名
    let moduleName = abilityStageContext.currentHapModuleInfo.name;

    // 缓存中没有，生成新的图片
    return new Promise(async (resolve, reject) => {
      try {
        let parseResult =
          await latexStringToImageWithError(normalizedLatexText, context.fp2px(latexMathTextSize), latexMathTextColor,
            0x00000000, LatexMathColorFormat.COLOR_FORMAT_BGRA_8888,
            `/data/storage/el1/bundle/${moduleName}/resources/resfile/res`)
        if (parseResult.resultCode != TeXResultCode.Success) {
          reject(parseResult.errorMessage)
          return
        }
        let buf: ArrayBuffer = parseResult.imageBytes
        let imageSource = image.createImageSource(buf)
        // 图片pixelMap
        let pixelMap = imageSource.createPixelMapSync()
        let size: Size = pixelMap.getImageInfoSync().size

        const latexInfo: LatexInfo = {
          pixelMap: pixelMap,
          width: size.width,
          height: size.height
        };

        // 将生成的图片存入缓存（带 FIFO 上限）
        saveCache(cacheKey, latexInfo);

        resolve(latexInfo);
      } catch (err) {
        reject(err);
      }
    });
  }

  export function getCachedLatex(latexText: string, latexMathTextSize: number,
    latexMathTextColor: number): LatexInfo | undefined {
    return latexCache.get(buildCacheKey(normalizeLatexText(latexText), latexMathTextSize, latexMathTextColor));
  }

  // 清理缓存。注意：latexCache 为全局共享，单个 Markdown 实例卸载时不应调用此方法，
  // 否则会清掉其他存活实例正在使用的公式缓存。仅在确实需要整体释放时手动调用。
  export function clearCache() {
    latexCache.clear();
    latexCacheOrder.length = 0;
  }
}
