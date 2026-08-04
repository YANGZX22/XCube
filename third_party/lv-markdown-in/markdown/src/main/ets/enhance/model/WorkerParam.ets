import { TreeNode } from './TreeNode'
import { PluginSyntaxManifest } from './MarkdownPlugin'

export interface WorkerParam {
  key: string,
  data: WorkerResTextParam,
  union?: string
}

export interface WorkerTreeNodeResp {
  key: string,
  data: TreeNode[],
  union?: string,
  requestId?: number,
  // 解析抛错时由 worker 置 true: 宿主据此结算 in-flight 闸门但跳过渲染(保留上一次有效结果, 不清空)。
  error?: boolean
}

export interface MarkdownParseOptions {
  setextHeading?: boolean
}

export interface WorkerParseData {
  text: string,
  plugins?: PluginSyntaxManifest[],
  parseOptions?: MarkdownParseOptions
}

export interface WorkerParseReq {
  key: string,
  data: WorkerParseData,
  union?: string,
  requestId?: number
}

export interface WorkerStringResp {
  key: string,
  data: string,
  union?: string
}

export interface WorkerResTextParam {
  ctx: Context
  rawfilePath: string
}
