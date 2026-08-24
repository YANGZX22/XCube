import { describe, expect, it } from '@ohos/hypium'
import {
  getMapKitService,
  MAP_ACTION_ROUTE,
  MAP_ACTION_SEARCH,
  MapVisualizationData,
  normalizeMapAction,
  normalizeMapTravelMode
} from '../main/ets/services/MapKitService'
import {
  getBuiltinToolIds,
  MAP_SEARCH_ROUTE_TOOL_ID,
  OPEN_MAP_ROUTE_TOOL_ID
} from '../main/ets/config/BuiltinTools'

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
    })

    it('builds_map_visualization_for_legacy_tool_results', 0, () => {
      const content = JSON.stringify({
        ok: true,
        action: MAP_ACTION_SEARCH,
        query: '咖啡店',
        usedCurrentLocation: false,
        places: [{
          name: '测试咖啡店',
          address: '测试地址',
          latitude: 31.2304,
          longitude: 121.4737
        }],
        routes: []
      })
      const visualization = JSON.parse(getMapKitService().getVisualizationJson(content)) as MapVisualizationData
      expect(visualization.destination?.name).assertEqual('测试咖啡店')
      expect(visualization.places.length).assertEqual(1)
    })
  })
}
