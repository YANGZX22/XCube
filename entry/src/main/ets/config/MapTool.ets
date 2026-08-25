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
        "description": "公开地点搜索关键词，只用于 action=search_places，例如‘安静的咖啡店’、‘博物馆’。禁止传常用地点 label（如‘家’‘公司’）；围绕常用地点搜索时把 saved_places 坐标填入 center，query 只填要找的公开地点类型。规划路线时不要用本字段传目的地。"
      },
      "nearby": {
        "type": "boolean",
        "description": "是否限定为周边搜索。用户说‘附近/周边’时设为 true。"
      },
      "use_current_location": {
        "type": "boolean",
        "description": "是否使用设备当前位置作为搜索中心或路线起点。只有用户意图涉及当前位置、附近或从这里出发时才设为 true。设为 true 时不要再传 origin 或 origin_location；围绕常用地点搜索应传 center，从常用地点出发应传 origin_location。"
      },
      "center": {
        "type": "object",
        "properties": {
          "latitude": { "type": "number" },
          "longitude": { "type": "number" }
        },
        "required": ["latitude", "longitude"],
        "description": "搜索中心坐标。提供后无需读取设备位置。用户要求搜索‘家附近/公司周边’时，从 saved_places 找到对应地点，把其 latitude/longitude 复制到 center，并把 coordinateType 复制到 coordinate_type；query 只填写要找的公开地点类型。"
      },
      "origin": {
        "type": "string",
        "description": "路线起点的公开地点全名或完整地址。禁止传常用地点 label（如‘家’‘公司’）；常用地点必须把 saved_places 返回的 latitude/longitude 填入 origin_location。省略时应设置 use_current_location=true。"
      },
      "origin_location": {
        "type": "object",
        "properties": {
          "latitude": { "type": "number" },
          "longitude": { "type": "number" }
        },
        "required": ["latitude", "longitude"],
        "description": "路线起点坐标，优先于 origin。使用常用地点时必须从 saved_places 返回值逐字段复制 latitude/longitude 到这里，并将 coordinateType 复制到 coordinate_type；不要只复制 label。"
      },
      "destination": {
        "type": "string",
        "description": "路线目的地的公开地点全名或完整地址。禁止传常用地点 label（如‘家’‘公司’）；常用地点必须使用 saved_places 返回的坐标填写 destination_location。action=plan_route 且未提供 destination_location 时必填。"
      },
      "destination_location": {
        "type": "object",
        "properties": {
          "latitude": { "type": "number" },
          "longitude": { "type": "number" }
        },
        "required": ["latitude", "longitude"],
        "description": "路线目的地坐标，优先于 destination。使用常用地点时必须从 saved_places 返回值逐字段复制 latitude/longitude 到这里，并将 coordinateType 复制到 coordinate_type；不要只复制 label。也可使用上一次 search_places 返回的候选坐标。"
      },
      "coordinate_type": {
        "type": "string",
        "enum": ["gcj02", "wgs84"],
        "description": "传入坐标的坐标系，默认 gcj02。使用 saved_places 坐标时，复制其 coordinateType 字段，不要自行猜测。Map Kit 会按服务区域自动纠偏。"
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
      '选择 action：找地方用 search_places（公开地点关键词放 query）；算路线用 plan_route（目的地放 destination/destination_location，起点放 origin/origin_location 或 use_current_location=true）。' +
      '不要用 query 传路线目的地，也不要用 destination 传搜索关键词。\n' +
      '【常用地点硬规则】“家”“公司”等是本地 label，不是公开地点关键词，绝不能把 label 直接传入 query、origin 或 destination。\n' +
      '用户提到常用地点时，先调用 saved_places 的 list/resolve，在返回的 places 中找到目标；然后把 latitude/longitude ' +
      '用于路线时填入对应的 origin_location 或 destination_location，用于“家附近”这类搜索时填入 center；' +
      '同时把 coordinateType 填入 coordinate_type。' +
      '不要读取完整结果后只复制 label。\n' +
      '附近搜索示例：找“家附近的咖啡店”应传 {action:"search_places", query:"咖啡店", nearby:true, ' +
      'center:{latitude:<家.latitude>,longitude:<家.longitude>}, coordinate_type:<家.coordinateType>}；禁止传 query:"家"。\n' +
      '示例：saved_places 返回 {label:"家", latitude:31.2, longitude:121.4, coordinateType:"gcj02"}，' +
      '从当前位置回家应调用 {action:"plan_route", use_current_location:true, ' +
      'destination_location:{latitude:31.2, longitude:121.4}, coordinate_type:"gcj02"}；禁止写 destination:"家"。\n' +
      '同一个端点只用一种定位方式：给了 destination_location 就不要再给 destination；给了 origin_location 就不要再给 origin 或 use_current_location=true。\n' +
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
        "description": "公开地点全名或完整地址。禁止传常用地点 label（如‘家’‘公司’）；常用地点必须使用 saved_places 返回的坐标填写 destination_location。未提供 destination_location 时必填。"
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
        "description": "目的地坐标，优先于 destination。常用地点必须从 saved_places 返回值复制 latitude/longitude 到这里，并将 coordinateType 复制到 coordinate_type；不要只复制 label。也可使用 map_search_route 返回的确切坐标。"
      },
      "origin": {
        "type": "string",
        "description": "可选起点的公开地点全名或完整地址。禁止传常用地点 label；常用地点必须使用 saved_places 返回的坐标填写 origin_location。要从当前位置出发就省略 origin 和 origin_location。"
      },
      "origin_location": {
        "type": "object",
        "properties": {
          "latitude": { "type": "number" },
          "longitude": { "type": "number" }
        },
        "required": ["latitude", "longitude"],
        "description": "可选起点坐标，优先于 origin。常用地点必须从 saved_places 返回值复制 latitude/longitude 到这里，并将 coordinateType 复制到 coordinate_type；不要只复制 label。"
      },
      "coordinate_type": {
        "type": "string",
        "enum": ["gcj02", "wgs84"],
        "description": "传入坐标的坐标系，默认 gcj02。使用 saved_places 坐标时复制其 coordinateType 字段，不要自行猜测。"
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
      '【常用地点硬规则】绝不能把“家”“公司”等 label 直接传给 destination 或 origin。先调用 saved_places，' +
      '再把返回的 latitude/longitude 填入 destination_location 或 origin_location，并把 coordinateType 填入 coordinate_type。' +
      '不要读取完整结果后只复制 label。\n' +
      '示例：前往保存的“家”应传 destination_location:{latitude:<返回值>,longitude:<返回值>} 和对应 coordinate_type；' +
      '禁止只传 destination:"家"。同一个端点只用一种定位方式。\n' +
      '此操作会切换到地图应用，执行前应用会要求用户审批。' +
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
