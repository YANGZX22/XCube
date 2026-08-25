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
        "description": "地点搜索关键词，只用于 action=search_places，例如‘安静的咖啡店’、‘博物馆’。规划路线时不要用本字段传目的地——那属于 destination。本字段不解析常用地点标签。"
      },
      "nearby": {
        "type": "boolean",
        "description": "是否限定为周边搜索。用户说‘附近/周边’时设为 true。"
      },
      "use_current_location": {
        "type": "boolean",
        "description": "是否使用设备当前位置作为搜索中心或路线起点。只有用户意图涉及当前位置、附近或从这里出发时才设为 true。设为 true 时不要再传 origin 或 origin_location；需要从某个常用地点出发时，请传 origin 而不是本字段。"
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
        "description": "路线起点：常用地点标签、地点名称或地址，三选一直接传字符串。传标签时必须与用户保存的标签逐字一致（如‘公司’），本工具会自己解析，不需要你先查坐标。字符串对不上任何已保存标签时会被当成公开地点名去搜索，可能得到毫不相干的地点，所以不确定标签原文时先调用 saved_places 的 list 拿到确切写法，不要自行改写、翻译或加字（‘我公司’‘公司地址’都匹配不上‘公司’）。省略时应设置 use_current_location=true。"
      },
      "origin_location": {
        "type": "object",
        "properties": {
          "latitude": { "type": "number" },
          "longitude": { "type": "number" }
        },
        "required": ["latitude", "longitude"],
        "description": "路线起点坐标，优先于 origin。已经用标签或名称表达了起点时不要再传本字段，两者同时给出会忽略 origin。"
      },
      "destination": {
        "type": "string",
        "description": "路线目的地：常用地点标签、完整地点名称或地址，三选一直接传字符串。传标签时必须与用户保存的标签逐字一致（如‘家’），本工具会自己解析成坐标，不需要你先调 saved_places 再传坐标。字符串对不上任何已保存标签时会退化成公开地点搜索，可能命中同名的陌生地点，所以不确定标签原文时先用 saved_places 的 list 确认，不要改写、翻译或加字（‘我家’‘家里’都匹配不上‘家’）。action=plan_route 且未提供 destination_location 时必填。"
      },
      "destination_location": {
        "type": "object",
        "properties": {
          "latitude": { "type": "number" },
          "longitude": { "type": "number" }
        },
        "required": ["latitude", "longitude"],
        "description": "路线目的地坐标，优先于 destination。只有当你手上已经有明确坐标（例如上一次 search_places 返回的候选）时才用；用标签或名称表达目的地时不要再传本字段。"
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
    '使用华为 Map Kit 搜索公共地点、查找附近兴趣点，或规划驾车、步行、骑行路线。' +
      '适合回答“附近有什么”“推荐一个目的地”“怎么去”等问题。\n' +
      '选择 action：找地方用 search_places（关键词放 query）；算路线用 plan_route（目的地放 destination，起点放 origin 或 use_current_location=true）。' +
      '不要用 query 传路线目的地，也不要用 destination 传搜索关键词。\n' +
      '关于常用地点（用户在设置里保存的“家”“公司”这类标签）：\n' +
      '1. 直接把标签原文作为字符串传给 origin / destination，本工具会自行解析成坐标。不要先调 saved_places 取坐标再填进 *_location，多这一步只会增加填错字段的机会。\n' +
      '2. 标签是逐字精确匹配的，大小写不敏感但不做模糊匹配。“我家”“家里”“家的地址”都匹配不上“家”。\n' +
      '3. 匹配不上时不会报错，而是把这串文字当成公开地点名去搜索，于是返回一个同名但毫不相干的地点。' +
      '所以只要你不确定用户保存的标签原文是什么，先调用 saved_places 的 list 看一眼，再用返回的确切标签。\n' +
      '4. 用户嘴上说的词不一定等于保存的标签；以 saved_places 返回的 label 为准，不要翻译或改写。\n' +
      '同一个端点只用一种表达：给了 destination 就不要再给 destination_location，给了 origin 就不要再设 use_current_location=true。\n' +
      '推荐地点时先搜索候选并根据返回的距离、评分、营业信息做比较；不要虚构未返回的信息。' +
      '仅在用户明确涉及当前位置、附近或从这里出发时设置 use_current_location=true。工具只返回规划结果，不会自动打开地图应用。',
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
        "description": "目的地：常用地点标签、完整地点名称或地址，直接传字符串即可，工具会自行解析。传标签时必须与用户保存的标签逐字一致（如‘家’）；对不上就会退化成公开地点搜索并可能命中同名的陌生地点，所以不确定标签原文时先用 saved_places 的 list 确认，不要改写或加字。未提供 destination_location 时必填。"
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
        "description": "目的地坐标，优先于 destination。仅在已有 map_search_route 返回的确切坐标时使用；用标签或名称表达目的地时不要再传本字段。"
      },
      "origin": {
        "type": "string",
        "description": "可选起点：常用地点标签、名称或地址，规则同 destination（标签逐字精确匹配）。要从当前位置出发就直接省略本字段，不要传‘当前位置’‘我的位置’这类文字——它们会被当成地点名去搜索。"
      },
      "origin_location": {
        "type": "object",
        "properties": {
          "latitude": { "type": "number" },
          "longitude": { "type": "number" }
        },
        "required": ["latitude", "longitude"],
        "description": "可选起点坐标，优先于 origin。用标签或名称表达起点时不要再传本字段。"
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
    '在花瓣地图中打开路线规划或发起导航。只有当用户明确要求“打开地图/带我去/开始导航/查看路线”时才调用；' +
      '不要仅因用户询问路线或请求推荐而调用。\n' +
      '起终点可直接使用用户保存的常用地点标签（如“家”“公司”）：把标签原文传给 destination / origin 即可，' +
      '工具会自行解析成坐标，不需要先调 saved_places 取坐标再填 *_location。\n' +
      '标签是逐字精确匹配的：“我家”“家里”匹配不上“家”，且匹配失败不会报错，而是把这串文字当公开地点名去搜索，' +
      '很容易把用户导航到一个同名的陌生地点。不确定标签原文时，先调用 saved_places 的 list 拿到确切写法。\n' +
      '同一个端点只用一种表达，不要同时传字符串和坐标。此操作会切换到地图应用，执行前应用会要求用户审批。' +
      '若公共地点可能重名，先调用 map_search_route 确认准确地点，再传入其名称、siteId 和坐标。',
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
