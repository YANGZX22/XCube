import { getPreferencesService, PreferenceKeys, PreferencesService } from './PreferencesService'

interface SavedPlaceJson {
  id?: string
  label?: string
  name?: string
  address?: string
  siteId?: string
  latitude?: number
  longitude?: number
  coordinateType?: string
  createdAt?: number
  updatedAt?: number
}

export class SavedPlace {
  id: string = ''
  label: string = ''
  name: string = ''
  address: string = ''
  siteId: string = ''
  latitude: number = 0
  longitude: number = 0
  coordinateType: string = 'gcj02'
  createdAt: number = 0
  updatedAt: number = 0
}

export function normalizeSavedPlaceLabel(value: string): string {
  return value.trim().replace(/\s+/g, ' ')
}

function normalizeSavedPlaceCoordinateType(value: string): string {
  return value.trim().toLowerCase() === 'wgs84' ? 'wgs84' : 'gcj02'
}

function isValidSavedPlaceCoordinate(latitude: number, longitude: number): boolean {
  return Number.isFinite(latitude) && Number.isFinite(longitude) &&
    latitude >= -90 && latitude <= 90 && longitude >= -180 && longitude <= 180
}

export function cloneSavedPlace(value: SavedPlace): SavedPlace {
  const result = new SavedPlace()
  result.id = value.id
  result.label = value.label
  result.name = value.name
  result.address = value.address
  result.siteId = value.siteId
  result.latitude = value.latitude
  result.longitude = value.longitude
  result.coordinateType = value.coordinateType
  result.createdAt = value.createdAt
  result.updatedAt = value.updatedAt
  return result
}

function toSavedPlace(value: SavedPlaceJson): SavedPlace | null {
  const label = normalizeSavedPlaceLabel(value.label || '')
  const latitude = Number(value.latitude)
  const longitude = Number(value.longitude)
  if (label === '' || !isValidSavedPlaceCoordinate(latitude, longitude)) {
    return null
  }
  const result = new SavedPlace()
  result.id = (value.id || '').trim()
  result.label = label
  result.name = (value.name || '').trim()
  result.address = (value.address || '').trim()
  result.siteId = (value.siteId || '').trim()
  result.latitude = latitude
  result.longitude = longitude
  result.coordinateType = normalizeSavedPlaceCoordinateType(value.coordinateType || '')
  result.createdAt = Number.isFinite(value.createdAt) ? Number(value.createdAt) : 0
  result.updatedAt = Number.isFinite(value.updatedAt) ? Number(value.updatedAt) : result.createdAt
  return result
}

export function parseSavedPlacesJson(raw: string): SavedPlace[] {
  if (raw.trim() === '') {
    return []
  }
  try {
    const parsed = JSON.parse(raw) as SavedPlaceJson[]
    if (!Array.isArray(parsed)) {
      return []
    }
    const result: SavedPlace[] = []
    const normalizedLabels: string[] = []
    for (let i = 0; i < parsed.length; i++) {
      const place = toSavedPlace(parsed[i])
      if (place === null) {
        continue
      }
      const normalizedLabel = place.label.toLocaleLowerCase()
      if (normalizedLabels.includes(normalizedLabel)) {
        continue
      }
      if (place.id === '') {
        place.id = `saved_place_${place.createdAt}_${i}`
      }
      normalizedLabels.push(normalizedLabel)
      result.push(place)
    }
    return result
  } catch (_error) {
    return []
  }
}

export function upsertSavedPlaceList(places: SavedPlace[], input: SavedPlace, now: number = Date.now()): SavedPlace[] {
  const normalizedLabel = normalizeSavedPlaceLabel(input.label)
  if (normalizedLabel === '') {
    throw new Error('请输入地点标签')
  }
  if (!isValidSavedPlaceCoordinate(input.latitude, input.longitude)) {
    throw new Error('请选择有效地点')
  }
  let editingIndex = -1
  for (let i = 0; i < places.length; i++) {
    if (input.id !== '' && places[i].id === input.id) {
      editingIndex = i
      continue
    }
    if (places[i].label.toLocaleLowerCase() === normalizedLabel.toLocaleLowerCase()) {
      throw new Error(`地点标签“${normalizedLabel}”已存在`)
    }
  }
  const saved = cloneSavedPlace(input)
  saved.id = input.id.trim() !== '' ? input.id.trim() :
    `saved_place_${now}_${Math.floor(Math.random() * 1000000)}`
  saved.label = normalizedLabel
  saved.name = input.name.trim()
  saved.address = input.address.trim()
  saved.siteId = input.siteId.trim()
  saved.coordinateType = normalizeSavedPlaceCoordinateType(input.coordinateType)
  saved.createdAt = editingIndex >= 0 && places[editingIndex].createdAt > 0 ? places[editingIndex].createdAt : now
  saved.updatedAt = now

  const result: SavedPlace[] = []
  for (let i = 0; i < places.length; i++) {
    result.push(i === editingIndex ? saved : cloneSavedPlace(places[i]))
  }
  if (editingIndex < 0) {
    result.push(saved)
  }
  return result
}

export class SavedPlacesService {
  private static instance: SavedPlacesService | null = null
  private preferencesService: PreferencesService = getPreferencesService()

  private constructor() {}

  static getInstance(): SavedPlacesService {
    if (SavedPlacesService.instance === null) {
      SavedPlacesService.instance = new SavedPlacesService()
    }
    return SavedPlacesService.instance
  }

  async loadPlaces(): Promise<SavedPlace[]> {
    const raw = await this.preferencesService.getString(PreferenceKeys.SAVED_PLACES_JSON, '')
    const places = parseSavedPlacesJson(raw)
    return places.map((place: SavedPlace): SavedPlace => cloneSavedPlace(place))
  }

  async savePlace(input: SavedPlace): Promise<SavedPlace> {
    const places = await this.loadPlaces()
    const nextPlaces = upsertSavedPlaceList(places, input)
    await this.persist(nextPlaces)
    for (let i = 0; i < nextPlaces.length; i++) {
      if (nextPlaces[i].id === input.id ||
        nextPlaces[i].label.toLocaleLowerCase() === normalizeSavedPlaceLabel(input.label).toLocaleLowerCase()) {
        return cloneSavedPlace(nextPlaces[i])
      }
    }
    throw new Error('保存地点失败')
  }

  async deletePlace(placeId: string): Promise<void> {
    const places = await this.loadPlaces()
    const nextPlaces: SavedPlace[] = []
    for (let i = 0; i < places.length; i++) {
      if (places[i].id !== placeId) {
        nextPlaces.push(places[i])
      }
    }
    await this.persist(nextPlaces)
  }

  async resolveLabel(label: string): Promise<SavedPlace | null> {
    const normalized = normalizeSavedPlaceLabel(label).toLocaleLowerCase()
    if (normalized === '') {
      return null
    }
    const places = await this.loadPlaces()
    for (let i = 0; i < places.length; i++) {
      if (places[i].label.toLocaleLowerCase() === normalized) {
        return cloneSavedPlace(places[i])
      }
    }
    return null
  }

  private async persist(places: SavedPlace[]): Promise<void> {
    await this.preferencesService.setString(PreferenceKeys.SAVED_PLACES_JSON, JSON.stringify(places))
  }
}

export function getSavedPlacesService(): SavedPlacesService {
  return SavedPlacesService.getInstance()
}
