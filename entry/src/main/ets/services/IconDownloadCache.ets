/**
 * 图标下载缓存服务
 * 下载远程图标并缓存到沙箱。
 * SVG 先按原始扩展名落盘，再由 ImageKit 从文件转换为 PNG，避免 ArrayBuffer 格式识别失败。
 */

import { http } from '@kit.NetworkKit'
import { image } from '@kit.ImageKit'
import { fileIo } from '@kit.CoreFileKit'
import { Context } from '@kit.AbilityKit'
import { util } from '@kit.ArkTS'

const CACHE_DIR = 'icon_cache'
const ICON_SIZE = 128

export class IconDownloadCache {
  private static instance: IconDownloadCache | null = null
  private cacheDir: string = ''
  private isInitialized: boolean = false
  // url → 沙箱文件路径
  private memoryIndex: Map<string, string> = new Map()
  // 正在下载的 URL，防止重复请求
  private pendingDownloads: Map<string, Promise<string>> = new Map()

  private constructor() {}

  static getInstance(): IconDownloadCache {
    if (IconDownloadCache.instance === null) {
      IconDownloadCache.instance = new IconDownloadCache()
    }
    return IconDownloadCache.instance
  }

  async initialize(context: Context): Promise<void> {
    if (this.isInitialized) {
      return
    }
    this.cacheDir = `${context.filesDir}/${CACHE_DIR}`
    await this.ensureCacheDir()
    this.rebuildIndex()
    this.isInitialized = true
  }

  private async ensureCacheDir(): Promise<void> {
    try {
      fileIo.accessSync(this.cacheDir)
    } catch (_e) {
      fileIo.mkdirSync(this.cacheDir, true)
    }
  }
  // 启动时扫描缓存目录重建内存索引
  private rebuildIndex(): void {
    try {
      const entries = fileIo.listFileSync(this.cacheDir)
      for (let i = 0; i < entries.length; i++) {
        const fileName = entries[i]
        if (fileName.endsWith('.png') || fileName.endsWith('.svg')) {
          const filePath = `${this.cacheDir}/${fileName}`
          // 文件名格式: {hash}.png / {hash}.svg，对应的 URL 无法反推。
          // 这里先用 filePath 作为 value，后续 getCachedIconUri 通过 hash 匹配
          const hash = fileName.substring(0, fileName.length - 4)
          const indexedPath = this.memoryIndex.get(hash)
          // 同一 URL 同时存在源 SVG 和转换后的 PNG 时优先使用 PNG。
          if (fileName.endsWith('.png') || indexedPath === undefined) {
            this.memoryIndex.set(hash, filePath)
          }
        }
      }
    } catch (_e) {
      // 目录为空或不存在，忽略
    }
  }

  // 同步获取已缓存的沙箱路径，未缓存返回空字符串
  getCachedIconUri(logoUrl: string): string {
    if (!this.isInitialized) {
      return ''
    }
    const hash = this.hashUrl(logoUrl)
    const cached = this.memoryIndex.get(hash)
    if (cached !== undefined) {
      return cached
    }
    return ''
  }

  // 异步下载图标并缓存，返回沙箱路径。失败返回空字符串
  async downloadAndCache(logoUrl: string): Promise<string> {
    if (!this.isInitialized) {
      return ''
    }
    // 已缓存直接返回
    const existing = this.getCachedIconUri(logoUrl)
    if (existing !== '') {
      if (existing.endsWith('.svg')) {
        const pngPath = await this.rasterizeSvgFile(existing, this.hashUrl(logoUrl))
        if (pngPath !== '') {
          return pngPath
        }
      }
      return existing
    }
    // 防止重复下载
    const pending = this.pendingDownloads.get(logoUrl)
    if (pending !== undefined) {
      return await pending
    }
    const promise = this.doDownloadAndCache(logoUrl)
    this.pendingDownloads.set(logoUrl, promise)
    const result = await promise
    this.pendingDownloads.delete(logoUrl)
    return result
  }
  private async doDownloadAndCache(logoUrl: string): Promise<string> {
    try {
      const httpRequest = http.createHttp()
      const response = await httpRequest.request(logoUrl, {
        method: http.RequestMethod.GET,
        connectTimeout: 10000,
        readTimeout: 15000,
        expectDataType: http.HttpDataType.ARRAY_BUFFER
      })
      httpRequest.destroy()

      if (response.responseCode !== 200) {
        return ''
      }

      const imageBuffer = response.result as ArrayBuffer
      if (imageBuffer.byteLength === 0) {
        return ''
      }

      const hash = this.hashUrl(logoUrl)
      if (this.isSvgPayload(logoUrl, imageBuffer)) {
        // 先以 .svg 落盘，让 ImageKit 能通过扩展名识别格式，再转换成与默认模型图标相同的本地 PNG。
        const svgPath = `${this.cacheDir}/${hash}.svg`
        this.writeBuffer(svgPath, imageBuffer)
        const pngPath = await this.rasterizeSvgFile(svgPath, hash)
        const cachedPath = pngPath !== '' ? pngPath : svgPath
        this.memoryIndex.set(hash, cachedPath)
        return cachedPath
      }

      // 非 SVG 图片在直接渲染失败后，统一转换为 PNG 作为兜底。
      const imageSource = image.createImageSource(imageBuffer)
      const decodingOptions: image.DecodingOptions = {
        desiredSize: { width: ICON_SIZE, height: ICON_SIZE }
      }
      const pixelMap = await imageSource.createPixelMap(decodingOptions)
      imageSource.release()

      const packer = image.createImagePacker()
      const packOpts: image.PackingOption = {
        format: 'image/png',
        quality: 100
      }
      const pngBuffer = await packer.packing(pixelMap, packOpts)
      packer.release()
      pixelMap.release()

      // 写入沙箱
      const filePath = `${this.cacheDir}/${hash}.png`
      this.writeBuffer(filePath, pngBuffer)

      this.memoryIndex.set(hash, filePath)
      return filePath
    } catch (error) {
      console.warn('IconDownloadCache', `Download failed for ${logoUrl}: ${JSON.stringify(error)}`)
      return ''
    }
  }

  private isSvgPayload(logoUrl: string, imageBuffer: ArrayBuffer): boolean {
    const cleanUrl = logoUrl.split('#')[0].split('?')[0].toLowerCase()
    if (cleanUrl.endsWith('.svg')) {
      return true
    }
    try {
      const decoder = util.TextDecoder.create('utf-8')
      const text = decoder.decodeToString(new Uint8Array(imageBuffer), { stream: false }).trim().toLowerCase()
      return text.startsWith('<svg') || (text.startsWith('<?xml') && text.includes('<svg'))
    } catch (_error) {
      return false
    }
  }

  private async rasterizeSvgFile(svgPath: string, hash: string): Promise<string> {
    let imageSource: image.ImageSource | null = null
    let pixelMap: image.PixelMap | null = null
    let packer: image.ImagePacker | null = null
    try {
      imageSource = image.createImageSource(svgPath)
      const sourceInfo = await imageSource.getImageInfo()
      const maxDimension = Math.max(sourceInfo.size.width, sourceInfo.size.height)
      const scale = maxDimension > 0 ? ICON_SIZE / maxDimension : 1
      const decodingOptions: image.DecodingOptions = {
        desiredSize: {
          width: Math.max(1, Math.round(sourceInfo.size.width * scale)),
          height: Math.max(1, Math.round(sourceInfo.size.height * scale))
        }
      }
      pixelMap = await imageSource.createPixelMap(decodingOptions)
      packer = image.createImagePacker()
      const packOpts: image.PackingOption = {
        format: 'image/png',
        quality: 100
      }
      const pngBuffer = await packer.packToData(pixelMap, packOpts)
      const pngPath = `${this.cacheDir}/${hash}.png`
      this.writeBuffer(pngPath, pngBuffer)
      this.memoryIndex.set(hash, pngPath)
      return pngPath
    } catch (error) {
      console.warn('IconDownloadCache', `SVG rasterization failed for ${svgPath}: ${JSON.stringify(error)}`)
      return ''
    } finally {
      if (packer !== null) {
        packer.release()
      }
      if (pixelMap !== null) {
        pixelMap.release()
      }
      if (imageSource !== null) {
        imageSource.release()
      }
    }
  }

  private writeBuffer(filePath: string, buffer: ArrayBuffer): void {
    const file = fileIo.openSync(filePath,
      fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC)
    try {
      fileIo.writeSync(file.fd, buffer)
    } finally {
      fileIo.closeSync(file)
    }
  }

  // 简单字符串哈希，生成 hex 字符串作为文件名
  private hashUrl(url: string): string {
    let hash: number = 0
    for (let i = 0; i < url.length; i++) {
      const ch = url.charCodeAt(i)
      hash = ((hash << 5) - hash) + ch
      hash = hash & hash // 转为 32 位整数
    }
    // 转为无符号 hex
    const unsigned = hash >>> 0
    return unsigned.toString(16).padStart(8, '0')
  }
}
