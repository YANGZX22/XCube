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
  mapUsageHint: string = ''
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
    result.mapUsageHint = '后续调用地图/导航工具时，不要把 label（如“家”“公司”）直接传给 query、origin 或 ' +
      'destination。路线/导航请把本结果中的 latitude/longitude 复制到对应的 origin_location 或 ' +
      'destination_location；围绕该地点搜索请复制到 center，并把 coordinateType 复制到 coordinate_type。'
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
        "description": "list 返回全部已保存地点的完整结构（label、name、address、latitude、longitude、coordinateType、siteId）；resolve 按标签精确返回单个地点。默认 list。不知道标签原文时先用 list。"
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
      '【地图调用硬规则】用户提到常用地点时，先从本工具结果找到对应 place，然后使用结构化坐标：' +
      '路线/导航时把 latitude/longitude 填入地图工具的 origin_location 或 destination_location，' +
      '围绕该地点搜索时填入 center，' +
      '把 coordinateType 填入 coordinate_type。不要丢弃这些字段后只把 label（如“家”“公司”）传给地图工具；' +
      'label 不是公开地点搜索词，禁止放入 query、origin 或 destination。',
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
