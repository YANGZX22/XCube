import { describe, expect, it } from '@ohos/hypium'
import {
  getMapKitService,
  MAP_ACTION_ROUTE,
  MAP_ACTION_SEARCH,
  MapRouteAlternative,
  MapVisualizationData,
  normalizeMapAction,
  normalizeMapTravelMode
} from '../main/ets/services/MapKitService'
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
    })

    it('includes_map_tools_in_builtin_catalog', 0, () => {
      const ids = getBuiltinToolIds()
      expect(ids.includes(MAP_SEARCH_ROUTE_TOOL_ID)).assertTrue()
      expect(ids.includes(OPEN_MAP_ROUTE_TOOL_ID)).assertTrue()
      expect(ids.includes(SAVED_PLACES_TOOL_ID)).assertTrue()
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
