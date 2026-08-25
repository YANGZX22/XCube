import {
  ToolConfig,
  ToolDefinition,
  ToolFunction,
  ToolParameters,
  ToolPermissionLevel,
  ToolSourceType
} from '../models/ChatModels'
import { getSavedPlacesService, SavedPlace } from '../services/SavedPlacesService'
import { ToolExecutor } from '../services/ToolRegistry'

export const SAVED_PLACES_TOOL_ID: string = 'saved_places'

interface SavedPlacesToolArgs {
  action?: string
  label?: string
}

class SavedPlacesToolResult {
  ok: boolean = true
  action: string = ''
  count: number = 0
  places: SavedPlace[] = []
  message: string = ''
}

export class SavedPlacesExecutor implements ToolExecutor {
  async execute(args: string): Promise<string> {
    let request = {} as SavedPlacesToolArgs
    if (args.trim() !== '') {
      try {
        request = JSON.parse(args) as SavedPlacesToolArgs
      } catch (_error) {
        throw new Error('常用地点工具参数必须是有效 JSON')
      }
    }
    const action = (request.action || 'list').trim().toLowerCase()
    const result = new SavedPlacesToolResult()
    result.action = action === 'resolve' ? 'resolve' : 'list'
    if (result.action === 'resolve') {
      const label = (request.label || '').trim()
      if (label === '') {
        throw new Error('解析常用地点需要 label')
      }
      const place = await getSavedPlacesService().resolveLabel(label)
      result.places = place !== null ? [place] : []
      result.count = result.places.length
      result.message = place !== null ? `已找到常用地点“${place.label}”` : `未找到常用地点“${label}”`
      return JSON.stringify(result)
    }
    result.places = await getSavedPlacesService().loadPlaces()
    result.count = result.places.length
    result.message = result.count > 0 ? `已读取 ${result.count} 个常用地点` : '尚未设置常用地点'
    return JSON.stringify(result)
  }
}

export function createSavedPlacesToolDefinition(): ToolDefinition {
  const parameters = new ToolParameters()
  parameters.setRawSchema(JSON.parse(`{
    "type": "object",
    "properties": {
      "action": {
        "type": "string",
        "enum": ["list", "resolve"],
        "description": "list 返回全部用户保存的地点标签；resolve 按标签精确查找单个地点。默认 list。不知道用户保存了哪些标签、或不确定标签的确切写法时，先用 list——它没有参数，也不会失败。"
      },
      "label": {
        "type": "string",
        "description": "action=resolve 时必填，例如‘家’、‘公司’。必须是用户保存的标签原文，逐字匹配（大小写不敏感，但不做模糊匹配、不去掉修饰词）：‘我家’‘家里’都匹配不上‘家’。请使用 list 返回的 label 字段原文，不要翻译、改写或从用户口语里猜。"
      }
    }
  }`) as object)
  return new ToolDefinition(new ToolFunction(
    SAVED_PLACES_TOOL_ID,
    '读取用户在设置中主动保存的常用地点标签、地址和坐标。此工具只读，不能新增、修改或删除地点。\n' +
      '用户询问“我保存了哪些地点”时用 list；只想确认某个标签指向哪里时用 resolve。\n' +
      '标签由用户自定义，按原文逐字匹配，不做模糊匹配，也不一定等于用户口语里的说法' +
      '（用户说“回我家”，保存的标签可能就叫“家”）。因此在使用任何标签之前，若不确定它的确切写法，先调用一次 list。\n' +
      '重要：如果目的只是规划路线或导航，不必先调用本工具取坐标——' +
      'map_search_route 和 open_map_route 的 origin / destination 直接接受标签原文并会自行解析。' +
      '多绕一步反而容易把坐标填进错误的字段。只有在需要向用户展示或核对具体地址时，才用 resolve 取详情。',
    parameters
  ))
}

export function createSavedPlacesToolConfig(): ToolConfig {
  return new ToolConfig(
    SAVED_PLACES_TOOL_ID,
    '常用地点',
    '读取用户保存的地点标签，用于路线规划和导航',
    null,
    true,
    false,
    ToolSourceType.BUILTIN,
    'builtin',
    SAVED_PLACES_TOOL_ID,
    '内置工具',
    ToolPermissionLevel.READ
  )
}
