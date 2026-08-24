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
        "description": "list 返回全部用户保存的地点标签；resolve 按标签精确查找。默认 list。"
      },
      "label": {
        "type": "string",
        "description": "action=resolve 时必填，例如‘家’、‘公司’。"
      }
    }
  }`) as object)
  return new ToolDefinition(new ToolFunction(
    SAVED_PLACES_TOOL_ID,
    '读取用户在设置中主动保存的常用地点标签、地址和坐标。用户询问“我保存了哪些地点”时使用 list；用户提到“家”“公司”等自定义标签但需要确认其精确位置时使用 resolve。此工具只读，不能新增、修改或删除地点。路线规划或导航时，可将返回坐标传给地图或花瓣导航工具。',
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
