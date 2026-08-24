import { describe, expect, it } from '@ohos/hypium'
import {
  normalizeSavedPlaceLabel,
  parseSavedPlacesJson,
  SavedPlace,
  upsertSavedPlaceList
} from '../main/ets/services/SavedPlacesService'

function createPlace(label: string, latitude: number, longitude: number): SavedPlace {
  const place = new SavedPlace()
  place.label = label
  place.name = `${label}地点`
  place.address = `${label}地址`
  place.latitude = latitude
  place.longitude = longitude
  return place
}

export default function savedPlacesServiceTest() {
  describe('savedPlacesServiceTest', () => {
    it('normalizes_labels_and_adds_places_without_a_count_limit', 0, () => {
      expect(normalizeSavedPlaceLabel('  我的   公司 ')).assertEqual('我的 公司')
      let places: SavedPlace[] = []
      for (let i = 0; i < 24; i++) {
        places = upsertSavedPlaceList(places, createPlace(`地点 ${i}`, 30 + i / 100, 120 + i / 100), 1000 + i)
      }
      expect(places.length).assertEqual(24)
    })

    it('updates_by_id_and_rejects_duplicate_labels', 0, () => {
      let places = upsertSavedPlaceList([], createPlace('家', 31.2, 121.4), 1000)
      const updated = createPlace('家', 31.3, 121.5)
      updated.id = places[0].id
      places = upsertSavedPlaceList(places, updated, 2000)
      expect(places.length).assertEqual(1)
      expect(places[0].latitude).assertEqual(31.3)
      let duplicateRejected = false
      try {
        upsertSavedPlaceList(places, createPlace('家', 32.0, 120.0), 3000)
      } catch (_error) {
        duplicateRejected = true
      }
      expect(duplicateRejected).assertTrue()
    })

    it('filters_invalid_persisted_places', 0, () => {
      const places = parseSavedPlacesJson(JSON.stringify([
        { id: 'home', label: '家', latitude: 31.2, longitude: 121.4, coordinateType: 'gcj02' },
        { id: 'invalid', label: '', latitude: 999, longitude: 999 }
      ]))
      expect(places.length).assertEqual(1)
      expect(places[0].label).assertEqual('家')
    })
  })
}
