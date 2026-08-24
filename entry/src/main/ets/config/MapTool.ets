import {
  ToolConfig,
  ToolDefinition,
  ToolFunction,
  ToolParameters,
  ToolPermissionLevel,
  ToolSourceType
} from '../models/ChatModels'
import {
  getMapKitService,
  MapOpenRequest,
  MapSearchRouteRequest
} from '../services/MapKitService'
import { ToolExecutor } from '../services/ToolRegistry'

export const MAP_SEARCH_ROUTE_TOOL_ID: string = 'map_search_route'
export const OPEN_MAP_ROUTE_TOOL_ID: string = 'open_map_route'

class MapSearchRouteExecutor implements ToolExecutor {
  async execute(args: string): Promise<string> {
    const request = this.parseRequest(args)
    const result = await getMapKitService().searchOrPlanRoute(request)
    return JSON.stringify(result)
  }

  private parseRequest(args: string): MapSearchRouteRequest {
    try {
      return JSON.parse(args) as MapSearchRouteRequest
    } catch (error) {
      throw new Error('地图工具参数必须是有效 JSON')
    }
  }
}

class OpenMapRouteExecutor implements ToolExecutor {
  async execute(args: string): Promise<string> {
    const request = this.parseRequest(args)
    const result = await getMapKitService().openMap(request)
    return JSON.stringify(result)
  }

  private parseRequest(args: string): MapOpenRequest {
    try {
      return JSON.parse(args) as MapOpenRequest
    } catch (error) {
      throw new Error('打开地图工具参数必须是有效 JSON')
    }
  }
}

export function createMapSearchRouteToolDefinition(): ToolDefinition {
  const parameters = new ToolParameters()
  const rawSchemaJson: string = `{
    "type": "object",
    "properties": {
      "action": {
        "type": "string",
        "enum": ["search_places", "plan_route"],
        "description": "search_places 搜索候选地点，plan_route 计算到目的地的路线。"
      },
      "query": {
        "type": "string",
        "description": "地点搜索关键词。action=search_places 时必填，例如‘安静的咖啡店’、‘博物馆’。"
      },
      "nearby": {
        "type": "boolean",
        "description": "是否限定为周边搜索。用户说‘附近/周边’时设为 true。"
      },
      "use_current_location": {
        "type": "boolean",
        "description": "是否使用设备当前位置作为搜索中心或路线起点。只有用户意图涉及当前位置、附近或从这里出发时才设为 true。"
      },
      "center": {
        "type": "object",
        "properties": {
          "latitude": { "type": "number" },
          "longitude": { "type": "number" }
        },
        "required": ["latitude", "longitude"],
        "description": "搜索中心坐标。提供后无需读取设备位置。"
      },
      "origin": {
        "type": "string",
        "description": "路线起点名称。省略时应设置 use_current_location=true。"
      },
      "origin_location": {
        "type": "object",
        "properties": {
          "latitude": { "type": "number" },
          "longitude": { "type": "number" }
        },
        "required": ["latitude", "longitude"],
        "description": "路线起点坐标，优先于 origin。"
      },
      "destination": {
        "type": "string",
        "description": "路线目的地的完整名称或地址。action=plan_route 且未提供 destination_location 时必填。"
      },
      "destination_location": {
        "type": "object",
        "properties": {
          "latitude": { "type": "number" },
          "longitude": { "type": "number" }
        },
        "required": ["latitude", "longitude"],
        "description": "路线目的地坐标，优先于 destination。"
      },
      "coordinate_type": {
        "type": "string",
        "enum": ["gcj02", "wgs84"],
        "description": "传入坐标的坐标系，默认 gcj02。Map Kit 会按服务区域自动纠偏。"
      },
      "travel_mode": {
        "type": "string",
        "enum": ["driving", "walking", "cycling"],
        "description": "路线出行方式，默认 driving。"
      },
      "radius_meters": {
        "type": "number",
        "description": "搜索半径，1 到 50000 米，默认 5000。"
      },
      "limit": {
        "type": "number",
        "description": "返回地点数量，1 到 10，默认 5。"
      },
      "include_details": {
        "type": "boolean",
        "description": "是否补充候选地点详情。需要比较评分、电话、营业时间时设为 true，最多补充前 5 个。"
      },
      "language": {
        "type": "string",
        "description": "Map Kit 返回语言，默认 zh_CN。"
      }
    },
    "required": ["action"]
  }`
  parameters.setRawSchema(JSON.parse(rawSchemaJson) as object)
  return new ToolDefinition(new ToolFunction(
    MAP_SEARCH_ROUTE_TOOL_ID,
    '使用华为 Map Kit 搜索公共地点、查找附近兴趣点，或规划驾车、步行、骑行路线。适合回答“附近有什么”“推荐一个目的地”“怎么去”等问题。推荐地点时先搜索候选并根据返回的距离、评分、营业信息做比较；不要虚构未返回的信息。仅在用户明确涉及当前位置、附近或从这里出发时设置 use_current_location=true。工具只返回规划结果，不会自动打开地图应用。',
    parameters
  ))
}

export function createMapSearchRouteToolConfig(): ToolConfig {
  return new ToolConfig(
    MAP_SEARCH_ROUTE_TOOL_ID,
    '地图',
    '使用 Map Kit 推荐地点并规划驾车、步行或骑行路线',
    null,
    true,
    false,
    ToolSourceType.BUILTIN,
    'builtin',
    MAP_SEARCH_ROUTE_TOOL_ID,
    '内置工具',
    ToolPermissionLevel.READ
  )
}

export function createOpenMapRouteToolDefinition(): ToolDefinition {
  const parameters = new ToolParameters()
  const rawSchemaJson: string = `{
    "type": "object",
    "properties": {
      "action": {
        "type": "string",
        "enum": ["route_plan", "navigation"],
        "description": "route_plan 打开花瓣地图路线页；navigation 直接发起导航。"
      },
      "destination": {
        "type": "string",
        "description": "目的地的完整名称或地址。未提供 destination_location 时必填。"
      },
      "destination_site_id": {
        "type": "string",
        "description": "map_search_route 返回的目的地 siteId，可提升地点匹配准确性。"
      },
      "destination_location": {
        "type": "object",
        "properties": {
          "latitude": { "type": "number" },
          "longitude": { "type": "number" }
        },
        "required": ["latitude", "longitude"],
        "description": "目的地坐标，优先于 destination。"
      },
      "origin": {
        "type": "string",
        "description": "可选起点；省略时由花瓣地图使用用户当前位置。"
      },
      "origin_location": {
        "type": "object",
        "properties": {
          "latitude": { "type": "number" },
          "longitude": { "type": "number" }
        },
        "required": ["latitude", "longitude"],
        "description": "可选起点坐标，优先于 origin。"
      },
      "coordinate_type": {
        "type": "string",
        "enum": ["gcj02", "wgs84"],
        "description": "传入坐标的坐标系，默认 gcj02。"
      },
      "travel_mode": {
        "type": "string",
        "enum": ["driving", "walking", "cycling", "transit"],
        "description": "出行方式，默认 driving。"
      },
      "language": {
        "type": "string",
        "description": "地点解析语言，默认 zh_CN。"
      }
    },
    "required": ["action"]
  }`
  parameters.setRawSchema(JSON.parse(rawSchemaJson) as object)
  return new ToolDefinition(new ToolFunction(
    OPEN_MAP_ROUTE_TOOL_ID,
    '在花瓣地图中打开路线规划或发起导航。只有当用户明确要求“打开地图/带我去/开始导航/查看路线”时才调用；不要仅因用户询问路线或请求推荐而调用。此操作会切换到地图应用，执行前应用会要求用户审批。若地点可能重名，先调用 map_search_route 确认准确地点，再传入其名称、siteId 和坐标。',
    parameters
  ))
}

export function createOpenMapRouteToolConfig(): ToolConfig {
  return new ToolConfig(
    OPEN_MAP_ROUTE_TOOL_ID,
    '花瓣导航',
    '经用户确认后打开路线规划或发起导航',
    null,
    true,
    false,
    ToolSourceType.BUILTIN,
    'builtin',
    OPEN_MAP_ROUTE_TOOL_ID,
    '内置工具',
    ToolPermissionLevel.WRITE
  )
}

export function createMapSearchRouteExecutor(): ToolExecutor {
  return new MapSearchRouteExecutor()
}

export function createOpenMapRouteExecutor(): ToolExecutor {
  return new OpenMapRouteExecutor()
}
