import { describe, expect, it } from '@ohos/hypium'
import {
  buildImmediateDrivingRouteParams,
  getMapKitService,
  MAP_ACTION_ROUTE,
  MAP_ACTION_SEARCH,
  MapRouteAlternative,
  MapVisualizationData,
  NonRetryableMapError,
  normalizeMapAction,
  normalizeMapTravelMode,
  shouldRetryMapOperation
} from '../main/ets/services/MapKitService'
import { formatToolExecutionError } from '../main/ets/services/ToolExecutionService'
import {
  getBuiltinToolIds,
  MAP_SEARCH_ROUTE_TOOL_ID,
  OPEN_MAP_ROUTE_TOOL_ID,
  SAVED_PLACES_TOOL_ID
} from '../main/ets/config/BuiltinTools'

// 旧版工具结果的载荷形状：只有当时存在的字段，没有 visualToken / destination 等后加的字段。
// ArkTS 不允许无类型的对象字面量，这里显式声明以保持 JSON 与线上旧数据一致。
class LegacyMapPlacePayload {
  name: string = ''
  address: string = ''
  latitude: number = 0
  longitude: number = 0
}

class LegacyMapToolResultPayload {
  ok: boolean = true
  action: string = ''
  query: string = ''
  usedCurrentLocation: boolean = false
  places: LegacyMapPlacePayload[] = []
  routes: MapRouteAlternative[] = []
}

class MapBusinessErrorPayload {
  code: number = 0
  message: string = ''

  constructor(code: number, message: string = '') {
    this.code = code
    this.message = message
  }
}

class MapCoordinatePayload {
  latitude: number = 0
  longitude: number = 0

  constructor(latitude: number, longitude: number) {
    this.latitude = latitude
    this.longitude = longitude
  }
}

export default function mapToolTest() {
  describe('mapToolTest', () => {
    it('normalizes_map_actions', 0, () => {
      expect(normalizeMapAction('route')).assertEqual(MAP_ACTION_ROUTE)
      expect(normalizeMapAction('route_plan')).assertEqual(MAP_ACTION_ROUTE)
      expect(normalizeMapAction('unknown')).assertEqual(MAP_ACTION_SEARCH)
    })

    it('normalizes_travel_modes', 0, () => {
      expect(normalizeMapTravelMode('walk')).assertEqual('walking')
      expect(normalizeMapTravelMode('bike')).assertEqual('cycling')
      expect(normalizeMapTravelMode('public_transit')).assertEqual('transit')
      expect(normalizeMapTravelMode(undefined)).assertEqual('driving')
      expect(normalizeMapTravelMode(undefined)).assertEqual(normalizeMapTravelMode('driving'))
    })

    it('omits_departure_timestamp_for_immediate_driving_routes', 0, () => {
      const origin = new MapCoordinatePayload(30.623852430715218, 104.07162581667365)
      const destination = new MapCoordinatePayload(30.572815000000001, 104.06680100000001)
      const params = buildImmediateDrivingRouteParams(origin, destination, 'zh_CN')
      expect(params.departAt === undefined).assertTrue()
      expect(params.alternatives).assertTrue()
      expect(params.origins[0].latitude).assertEqual(origin.latitude)
    })

    it('includes_map_tools_in_builtin_catalog', 0, () => {
      const ids = getBuiltinToolIds()
      expect(ids.includes(MAP_SEARCH_ROUTE_TOOL_ID)).assertTrue()
      expect(ids.includes(OPEN_MAP_ROUTE_TOOL_ID)).assertTrue()
      expect(ids.includes(SAVED_PLACES_TOOL_ID)).assertTrue()
    })

    it('retries_only_transient_map_and_location_failures', 0, () => {
      expect(shouldRetryMapOperation(new MapBusinessErrorPayload(1002600010), 0)).assertTrue()
      expect(shouldRetryMapOperation(new MapBusinessErrorPayload(1002600003), 0)).assertTrue()
      expect(shouldRetryMapOperation(new MapBusinessErrorPayload(3301200), 1)).assertTrue()
      expect(shouldRetryMapOperation(new Error('SDK failure without code'), 0)).assertTrue()
      expect(shouldRetryMapOperation(new Object(), 1)).assertTrue()
      expect(shouldRetryMapOperation(new MapBusinessErrorPayload(1002600010), 2)).assertFalse()

      expect(shouldRetryMapOperation(new MapBusinessErrorPayload(1002600004), 0)).assertFalse()
      expect(shouldRetryMapOperation(new MapBusinessErrorPayload(1002600006), 0)).assertFalse()
      expect(shouldRetryMapOperation(new MapBusinessErrorPayload(3301100), 0)).assertFalse()
      expect(shouldRetryMapOperation(new NonRetryableMapError('经纬度超出 Map Kit 支持范围'), 0)).assertFalse()
    })

    it('preserves_non_enumerable_tool_error_details', 0, () => {
      expect(formatToolExecutionError(new Error('地图路线服务超时'))).assertEqual('地图路线服务超时')
      expect(formatToolExecutionError(new MapBusinessErrorPayload(1002600010, 'Server busy')))
        .assertEqual('code=1002600010, message=Server busy')
      expect(formatToolExecutionError(new Object()))
        .assertEqual('未知错误（工具未提供错误码或错误信息）')
    })

    it('builds_map_visualization_for_legacy_tool_results', 0, () => {
      const place = new LegacyMapPlacePayload()
      place.name = '测试咖啡店'
      place.address = '测试地址'
      place.latitude = 31.2304
      place.longitude = 121.4737

      const payload = new LegacyMapToolResultPayload()
      payload.ok = true
      payload.action = MAP_ACTION_SEARCH
      payload.query = '咖啡店'
      payload.usedCurrentLocation = false
      payload.places = [place]

      const content = JSON.stringify(payload)
      const visualization = JSON.parse(getMapKitService().getVisualizationJson(content)) as MapVisualizationData
      expect(visualization.destination?.name).assertEqual('测试咖啡店')
      expect(visualization.places.length).assertEqual(1)
    })
  })
}
