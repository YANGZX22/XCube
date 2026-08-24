import abilityAccessCtrl, { Permissions, PermissionRequestResult } from '@ohos.abilityAccessCtrl'
import common from '@ohos.app.ability.common'
import { BusinessError } from '@kit.BasicServicesKit'
import { geoLocationManager } from '@kit.LocationKit'
import { map, mapCommon, navi, petalMaps, site } from '@kit.MapKit'
import { fileIo } from '@kit.CoreFileKit'
import { getSavedPlacesService } from './SavedPlacesService'

export const MAP_ACTION_SEARCH: string = 'search_places'
export const MAP_ACTION_ROUTE: string = 'plan_route'
export const MAP_OPEN_ACTION_ROUTE: string = 'route_plan'
export const MAP_OPEN_ACTION_NAVIGATION: string = 'navigation'

const DEFAULT_SEARCH_RADIUS_METERS: number = 5000
const DEFAULT_RESULT_LIMIT: number = 5
const MAX_RESULT_LIMIT: number = 10
const MAX_VISUALIZATION_CACHE_SIZE: number = 24
const MAX_PERSISTED_VISUALIZATION_COUNT: number = 128
const VISUALIZATION_DIRECTORY_NAME: string = 'map_visualizations'

export interface MapCoordinateArgs {
  latitude?: number | string
  longitude?: number | string
}

export interface MapSearchRouteRequest {
  action?: string
  query?: string
  nearby?: boolean | string
  useCurrentLocation?: boolean | string
  use_current_location?: boolean | string
  center?: MapCoordinateArgs
  origin?: string
  originLocation?: MapCoordinateArgs
  origin_location?: MapCoordinateArgs
  destination?: string
  destinationLocation?: MapCoordinateArgs
  destination_location?: MapCoordinateArgs
  coordinateType?: string
  coordinate_type?: string
  travelMode?: string
  travel_mode?: string
  radiusMeters?: number | string
  radius_meters?: number | string
  limit?: number | string
  includeDetails?: boolean | string
  include_details?: boolean | string
  language?: string
}

export interface MapOpenRequest {
  action?: string
  destination?: string
  destinationSiteId?: string
  destination_site_id?: string
  destinationLocation?: MapCoordinateArgs
  destination_location?: MapCoordinateArgs
  origin?: string
  originSiteId?: string
  origin_site_id?: string
  originLocation?: MapCoordinateArgs
  origin_location?: MapCoordinateArgs
  coordinateType?: string
  coordinate_type?: string
  travelMode?: string
  travel_mode?: string
  language?: string
}

export class MapPlaceResult {
  siteId: string = ''
  name: string = ''
  address: string = ''
  latitude: number = 0
  longitude: number = 0
  distanceMeters: number | undefined = undefined
  rating: number | undefined = undefined
  poiTypes: string[] = []
  phone: string = ''
  openingHours: string[] = []
  businessStatus: string = ''
  description: string = ''
  reliability: number | undefined = undefined
}

export class MapRoadSummary {
  roadName: string = ''
  action: string = ''
  distanceMeters: number = 0
  durationSeconds: number = 0
}

export class MapRouteAlternative {
  index: number = 0
  distanceMeters: number = 0
  durationSeconds: number = 0
  durationInTrafficSeconds: number | undefined = undefined
  trafficLightCount: number | undefined = undefined
  hasTolls: boolean | undefined = undefined
  hasFerry: boolean | undefined = undefined
  hasStairs: boolean | undefined = undefined
  hasRestrictedRoad: boolean | undefined = undefined
  roads: MapRoadSummary[] = []
}

export class MapSearchRouteResult {
  ok: boolean = true
  action: string = ''
  summary: string = ''
  usedCurrentLocation: boolean = false
  query: string = ''
  destination: MapPlaceResult | null = null
  places: MapPlaceResult[] = []
  travelMode: string = ''
  routes: MapRouteAlternative[] = []
  visualToken: string = ''
}

export class MapOpenResult {
  ok: boolean = true
  action: string = ''
  destination: string = ''
  message: string = ''
}

export class MapVisualCoordinate {
  latitude: number = 0
  longitude: number = 0

  constructor(latitude: number = 0, longitude: number = 0) {
    this.latitude = latitude
    this.longitude = longitude
  }
}

export class MapVisualPlace extends MapVisualCoordinate {
  name: string = ''
  address: string = ''

  constructor(latitude: number = 0, longitude: number = 0, name: string = '', address: string = '') {
    super(latitude, longitude)
    this.name = name
    this.address = address
  }
}

export class MapVisualizationData {
  token: string = ''
  action: string = ''
  summary: string = ''
  query: string = ''
  travelMode: string = ''
  usedCurrentLocation: boolean = false
  showCurrentLocation: boolean = false
  currentLocation: MapVisualPlace | null = null
  origin: MapVisualPlace | null = null
  destination: MapVisualPlace | null = null
  places: MapVisualPlace[] = []
  routePoints: MapVisualCoordinate[] = []
  distanceMeters: number = 0
  durationSeconds: number = 0
}

class ResolvedCoordinate {
  location: mapCommon.LatLng
  coordinateType: mapCommon.CoordinateType

  constructor(location: mapCommon.LatLng, coordinateType: mapCommon.CoordinateType) {
    this.location = location
    this.coordinateType = coordinateType
  }
}

class ResolvedPlace {
  site: site.Site | null = null
  coordinate: ResolvedCoordinate
  savedLabel: string = ''
  savedName: string = ''
  savedAddress: string = ''
  savedSiteId: string = ''

  constructor(coordinate: ResolvedCoordinate, resolvedSite: site.Site | null = null,
    savedLabel: string = '', savedName: string = '', savedAddress: string = '', savedSiteId: string = '') {
    this.coordinate = coordinate
    this.site = resolvedSite
    this.savedLabel = savedLabel
    this.savedName = savedName
    this.savedAddress = savedAddress
    this.savedSiteId = savedSiteId
  }
}

export function normalizeMapTravelMode(value: string | undefined): string {
  const mode = (value || '').trim().toLowerCase()
  if (mode === 'walking' || mode === 'walk') {
    return 'walking'
  }
  if (mode === 'cycling' || mode === 'bicycle' || mode === 'bike') {
    return 'cycling'
  }
  if (mode === 'transit' || mode === 'public_transit') {
    return 'transit'
  }
  return 'driving'
}

export function normalizeMapAction(value: string | undefined): string {
  const action = (value || '').trim().toLowerCase()
  if (action === MAP_ACTION_ROUTE || action === 'route' || action === 'route_plan') {
    return MAP_ACTION_ROUTE
  }
  return MAP_ACTION_SEARCH
}

export class MapKitService {
  private static instance: MapKitService | null = null
  private context: common.UIAbilityContext | null = null
  private visualizationCache: Map<string, string> = new Map<string, string>()
  private visualizationCacheKeys: string[] = []
  private visualizationCounter: number = 0

  private constructor() {}

  static getInstance(): MapKitService {
    if (MapKitService.instance === null) {
      MapKitService.instance = new MapKitService()
    }
    return MapKitService.instance
  }

  initialize(context: common.UIAbilityContext): void {
    this.context = context
    this.trimPersistedVisualizations()
  }

  /**
   * Returns local-only map geometry for the chat UI. Precise current-location coordinates are kept out of the
   * model-visible tool payload and are only available from the bounded local cache in the app sandbox.
   */
  getVisualizationJson(toolResultContent: string): string {
    try {
      const result = JSON.parse(toolResultContent) as MapSearchRouteResult
      const cached = result.visualToken !== '' ? this.visualizationCache.get(result.visualToken) : undefined
      if (cached !== undefined) {
        return cached
      }
      const persisted = this.readPersistedVisualization(result.visualToken)
      if (persisted !== '') {
        this.visualizationCache.set(result.visualToken, persisted)
        return persisted
      }
      return JSON.stringify(this.buildFallbackVisualization(result))
    } catch (_error) {
      return ''
    }
  }

  async searchPlaceCandidates(query: string, limit: number = 10, language: string = 'zh_CN',
    bias?: MapCoordinateArgs): Promise<MapPlaceResult[]> {
    try {
      const keyword = query.trim()
      if (keyword === '') {
        return []
      }
      const biasLocation = this.readCoordinate(bias)
      const params: site.SearchByTextParams = {
        query: keyword,
        location: biasLocation === null ? undefined : biasLocation,
        language: this.normalizeLanguage(language),
        pageIndex: 1,
        pageSize: Math.max(1, Math.min(MAX_RESULT_LIMIT, Math.round(limit)))
      }
      const response = await site.searchByText(this.ensureContext(), params)
      const sites = response.sites || []
      const result: MapPlaceResult[] = []
      for (let i = 0; i < sites.length; i++) {
        if (sites[i].location !== undefined) {
          result.push(this.toPlaceResult(sites[i]))
        }
      }
      return result
    } catch (error) {
      throw this.toMapError(error)
    }
  }

  async reverseGeocodePlace(location: mapCommon.LatLng, language: string = 'zh_CN'): Promise<MapPlaceResult> {
    try {
      const response = await site.reverseGeocode(this.ensureContext(), {
        location: location,
        radius: 200,
        language: this.normalizeLanguage(language),
        isExtension: true
      })
      const pois = response.pois || []
      const nearest = pois.length > 0 ? pois[0] : undefined
      const result = new MapPlaceResult()
      result.siteId = nearest?.siteId || ''
      result.name = nearest?.name || response.addressDescription || '地图选点'
      result.address = nearest?.address || response.addressDescription || ''
      result.latitude = location.latitude
      result.longitude = location.longitude
      result.distanceMeters = nearest?.distance
      return result
    } catch (error) {
      throw this.toMapError(error)
    }
  }

  async getCurrentPlace(language: string = 'zh_CN'): Promise<MapPlaceResult> {
    try {
      const coordinate = await this.getCurrentMapCoordinate()
      const result = await this.reverseGeocodePlace(coordinate.location, language)
      if (result.name.trim() === '') {
        result.name = '当前位置'
      }
      return result
    } catch (error) {
      throw this.toMapError(error)
    }
  }

  async searchOrPlanRoute(request: MapSearchRouteRequest): Promise<MapSearchRouteResult> {
    try {
      const action = normalizeMapAction(request.action)
      if (action === MAP_ACTION_ROUTE) {
        return await this.planRoute(request)
      }
      return await this.searchPlaces(request)
    } catch (error) {
      throw this.toMapError(error)
    }
  }

  async openMap(request: MapOpenRequest): Promise<MapOpenResult> {
    try {
      const context = this.ensureContext()
      const destination = await this.resolveEndpoint(
        this.firstCoordinate(request.destinationLocation, request.destination_location),
        request.destination,
        undefined,
        this.normalizeCoordinateType(request.coordinateType || request.coordinate_type),
        request.language
      )
      const destinationName = this.resolvePlaceName(destination, request.destination || '目的地')
      const destinationPoiId = (request.destinationSiteId || request.destination_site_id ||
        destination.savedSiteId || destination.site?.siteId || '').trim()
      const action = this.normalizeOpenAction(request.action)
      const vehicleType = this.toVehicleType(request.travelMode || request.travel_mode)

      let origin: ResolvedPlace | null = null
      const originCoordinate = this.firstCoordinate(request.originLocation, request.origin_location)
      if (originCoordinate !== undefined || (request.origin || '').trim() !== '') {
        origin = await this.resolveEndpoint(
          originCoordinate,
          request.origin,
          undefined,
          this.normalizeCoordinateType(request.coordinateType || request.coordinate_type),
          request.language
        )
      }

      if (action === MAP_OPEN_ACTION_NAVIGATION) {
        const params: petalMaps.NaviParams = {
          destinationPosition: destination.coordinate.location,
          destinationName: destinationName,
          destinationPoiId: destinationPoiId !== '' ? destinationPoiId : undefined,
          vehicleType: vehicleType,
          coordinateType: destination.coordinate.coordinateType
        }
        if (origin !== null) {
          params.originPosition = origin.coordinate.location
          params.originName = this.resolvePlaceName(origin, request.origin || '')
          const originPoiId = (request.originSiteId || request.origin_site_id || origin.savedSiteId ||
            origin.site?.siteId || '').trim()
          params.originPoiId = originPoiId !== '' ? originPoiId : undefined
        }
        await petalMaps.openMapNavi(context, params)
      } else {
        const params: petalMaps.RoutePlanParams = {
          destinationPosition: destination.coordinate.location,
          destinationName: destinationName,
          destinationPoiId: destinationPoiId !== '' ? destinationPoiId : undefined,
          vehicleType: vehicleType,
          coordinateType: destination.coordinate.coordinateType
        }
        if (origin !== null) {
          params.originPosition = origin.coordinate.location
          params.originName = this.resolvePlaceName(origin, request.origin || '')
          const originPoiId = (request.originSiteId || request.origin_site_id || origin.savedSiteId ||
            origin.site?.siteId || '').trim()
          params.originPoiId = originPoiId !== '' ? originPoiId : undefined
        }
        await petalMaps.openMapRoutePlan(context, params)
      }

      const result = new MapOpenResult()
      result.action = action
      result.destination = destinationName
      result.message = action === MAP_OPEN_ACTION_NAVIGATION
        ? `已在花瓣地图中发起前往“${destinationName}”的导航`
        : `已在花瓣地图中打开前往“${destinationName}”的路线规划`
      return result
    } catch (error) {
      throw this.toMapError(error)
    }
  }

  private async searchPlaces(request: MapSearchRouteRequest): Promise<MapSearchRouteResult> {
    const context = this.ensureContext()
    const query = (request.query || '').trim()
    if (query === '') {
      throw new Error('地点搜索需要 query 参数')
    }
    const limit = this.normalizeLimit(request.limit)
    const radius = this.normalizeRadius(request.radiusMeters ?? request.radius_meters)
    const nearby = this.readBoolean(request.nearby, false)
    const explicitCenter = this.readCoordinate(request.center)
    const useCurrentLocation = this.readBoolean(
      request.useCurrentLocation ?? request.use_current_location,
      nearby && explicitCenter === null
    )
    let didUseCurrentLocation = false
    let center: ResolvedCoordinate | null = null
    if (explicitCenter !== null) {
      center = await this.rectifyCoordinate(
        explicitCenter,
        this.normalizeCoordinateType(request.coordinateType || request.coordinate_type)
      )
    } else if (useCurrentLocation) {
      center = await this.getCurrentMapCoordinate()
      didUseCurrentLocation = true
    }

    let sites: site.Site[] = []
    let totalCount = 0
    if (nearby) {
      if (center === null) {
        throw new Error('附近搜索需要当前位置或 center 坐标')
      }
      const params: site.NearbySearchParams = {
        query: query,
        location: center.location,
        radius: radius,
        language: this.normalizeLanguage(request.language),
        pageIndex: 1,
        pageSize: limit
      }
      const response = await site.nearbySearch(context, params)
      sites = response.sites || []
      totalCount = response.totalCount
    } else {
      const params: site.SearchByTextParams = {
        query: query,
        location: center?.location,
        radius: center !== null ? radius : undefined,
        language: this.normalizeLanguage(request.language),
        pageIndex: 1,
        pageSize: limit
      }
      const response = await site.searchByText(context, params)
      sites = response.sites || []
      totalCount = response.totalCount
    }

    const includeDetails = this.readBoolean(request.includeDetails ?? request.include_details, false)
    const visibleSites = sites.slice(0, limit)
    if (includeDetails) {
      await this.enrichSiteDetails(visibleSites, request.language)
    }

    const places: MapPlaceResult[] = []
    for (let i = 0; i < visibleSites.length; i++) {
      places.push(this.toPlaceResult(visibleSites[i]))
    }
    const result = new MapSearchRouteResult()
    result.action = MAP_ACTION_SEARCH
    result.query = query
    result.usedCurrentLocation = didUseCurrentLocation
    result.places = places
    result.summary = places.length === 0
      ? `未找到与“${query}”相关的地点`
      : `找到 ${places.length} 个与“${query}”相关的地点（总匹配数 ${totalCount}）`
    const visualization = new MapVisualizationData()
    visualization.action = MAP_ACTION_SEARCH
    visualization.summary = result.summary
    visualization.query = query
    visualization.usedCurrentLocation = didUseCurrentLocation
    let displayCurrentLocation: ResolvedCoordinate | null = didUseCurrentLocation ? center : null
    if (displayCurrentLocation === null) {
      try {
        displayCurrentLocation = await this.getCurrentMapCoordinate()
      } catch (error) {
        console.warn('MapKitService', `Current location is unavailable for map display: ${JSON.stringify(error)}`)
      }
    }
    if (displayCurrentLocation !== null) {
      visualization.showCurrentLocation = true
      visualization.currentLocation = this.toVisualPlace(displayCurrentLocation.location, '当前位置', '')
    }
    if (center !== null) {
      visualization.origin = this.toVisualPlace(
        center.location,
        didUseCurrentLocation ? '当前位置' : '搜索中心',
        ''
      )
    }
    for (let i = 0; i < places.length; i++) {
      visualization.places.push(this.toVisualPlaceFromResult(places[i]))
    }
    if (places.length > 0) {
      visualization.destination = this.toVisualPlaceFromResult(places[0])
    }
    result.visualToken = this.cacheVisualization(visualization)
    return result
  }

  private async planRoute(request: MapSearchRouteRequest): Promise<MapSearchRouteResult> {
    const context = this.ensureContext()
    const inputCoordinateType = this.normalizeCoordinateType(request.coordinateType || request.coordinate_type)
    const originCoordinateArgs = this.firstCoordinate(request.originLocation, request.origin_location)
    const destinationCoordinateArgs = this.firstCoordinate(
      request.destinationLocation,
      request.destination_location
    )
    const originText = (request.origin || '').trim()
    const destinationText = (request.destination || '').trim()
    const useCurrentLocation = this.readBoolean(
      request.useCurrentLocation ?? request.use_current_location,
      originCoordinateArgs === undefined && originText === ''
    )
    let didUseCurrentLocation = false

    let origin: ResolvedPlace
    if (originCoordinateArgs !== undefined || originText !== '') {
      origin = await this.resolveEndpoint(
        originCoordinateArgs,
        originText,
        undefined,
        inputCoordinateType,
        request.language
      )
    } else if (useCurrentLocation) {
      origin = new ResolvedPlace(await this.getCurrentMapCoordinate())
      didUseCurrentLocation = true
    } else {
      throw new Error('路线规划需要 origin、origin_location，或 use_current_location=true')
    }

    const destination = await this.resolveEndpoint(
      destinationCoordinateArgs,
      destinationText,
      origin.coordinate.location,
      inputCoordinateType,
      request.language
    )
    const travelMode = normalizeMapTravelMode(request.travelMode || request.travel_mode)
    if (travelMode === 'transit') {
      throw new Error('应用内路线规划暂不支持公共交通；可使用“花瓣导航”工具查看公交路线')
    }
    const language = this.normalizeLanguage(request.language)
    let routeResult: navi.RouteResult
    if (travelMode === 'walking') {
      const params: navi.RouteParams = {
        origins: [origin.coordinate.location],
        destination: destination.coordinate.location,
        language: language
      }
      routeResult = await navi.getWalkingRoutes(context, params)
    } else if (travelMode === 'cycling') {
      const params: navi.RouteParams = {
        origins: [origin.coordinate.location],
        destination: destination.coordinate.location,
        language: language
      }
      routeResult = await navi.getCyclingRoutes(context, params)
    } else {
      const params: navi.DrivingRouteParams = {
        origins: [origin.coordinate.location],
        destination: destination.coordinate.location,
        language: language,
        alternatives: true,
        departAt: Math.floor(Date.now() / 1000)
      }
      routeResult = await navi.getDrivingRoutes(context, params)
    }

    const routes: MapRouteAlternative[] = []
    for (let i = 0; i < routeResult.routes.length; i++) {
      routes.push(this.toRouteAlternative(routeResult.routes[i], i + 1))
    }
    const destinationResult = destination.site !== null
      ? this.toPlaceResult(destination.site)
      : this.toCoordinatePlaceResult(destination.coordinate.location,
        this.resolvePlaceName(destination, destinationText), destination.savedAddress)
    const result = new MapSearchRouteResult()
    result.action = MAP_ACTION_ROUTE
    result.usedCurrentLocation = didUseCurrentLocation
    result.destination = destinationResult
    result.travelMode = travelMode
    result.routes = routes
    result.summary = routes.length === 0
      ? `未找到前往“${destinationResult.name}”的可用路线`
      : `已规划 ${routes.length} 条前往“${destinationResult.name}”的${this.travelModeLabel(travelMode)}路线`
    const visualization = new MapVisualizationData()
    visualization.action = MAP_ACTION_ROUTE
    visualization.summary = result.summary
    visualization.travelMode = travelMode
    visualization.usedCurrentLocation = didUseCurrentLocation
    let displayCurrentLocation: ResolvedCoordinate | null = didUseCurrentLocation ? origin.coordinate : null
    if (displayCurrentLocation === null) {
      try {
        displayCurrentLocation = await this.getCurrentMapCoordinate()
      } catch (error) {
        console.warn('MapKitService', `Current location is unavailable for map display: ${JSON.stringify(error)}`)
      }
    }
    if (displayCurrentLocation !== null) {
      visualization.showCurrentLocation = true
      visualization.currentLocation = this.toVisualPlace(displayCurrentLocation.location, '当前位置', '')
    }
    visualization.origin = this.toVisualPlace(
      origin.coordinate.location,
      didUseCurrentLocation ? '当前位置' : this.resolvePlaceName(origin, originText || '起点'),
      origin.savedAddress || origin.site?.formatAddress || ''
    )
    visualization.destination = this.toVisualPlaceFromResult(destinationResult)
    if (routeResult.routes.length > 0) {
      visualization.routePoints = this.collectRoutePoints(routeResult.routes[0])
      visualization.distanceMeters = routes[0].distanceMeters
      visualization.durationSeconds = routes[0].durationInTrafficSeconds ?? routes[0].durationSeconds
    }
    result.visualToken = this.cacheVisualization(visualization)
    return result
  }

  private async resolveEndpoint(
    coordinateArgs: MapCoordinateArgs | undefined,
    query: string | undefined,
    bias: mapCommon.LatLng | undefined,
    coordinateType: mapCommon.CoordinateType,
    language: string | undefined
  ): Promise<ResolvedPlace> {
    const explicitCoordinate = this.readCoordinate(coordinateArgs)
    if (explicitCoordinate !== null) {
      return new ResolvedPlace(await this.rectifyCoordinate(explicitCoordinate, coordinateType))
    }
    const keyword = (query || '').trim()
    if (keyword === '') {
      throw new Error('缺少目的地名称或坐标')
    }
    const savedPlace = await getSavedPlacesService().resolveLabel(keyword)
    if (savedPlace !== null) {
      const savedCoordinateType = this.normalizeCoordinateType(savedPlace.coordinateType)
      const savedCoordinate = await this.rectifyCoordinate({
        latitude: savedPlace.latitude,
        longitude: savedPlace.longitude
      }, savedCoordinateType)
      return new ResolvedPlace(savedCoordinate, null, savedPlace.label, savedPlace.name,
        savedPlace.address, savedPlace.siteId)
    }
    const params: site.SearchByTextParams = {
      query: keyword,
      location: bias,
      language: this.normalizeLanguage(language),
      pageIndex: 1,
      pageSize: 5
    }
    const response = await site.searchByText(this.ensureContext(), params)
    const sites = response.sites || []
    for (let i = 0; i < sites.length; i++) {
      if (sites[i].location !== undefined) {
        const corrected = await this.rectifyCoordinate(sites[i].location as mapCommon.LatLng,
          mapCommon.CoordinateType.GCJ02)
        return new ResolvedPlace(corrected, sites[i])
      }
    }
    throw new Error(`未找到“${keyword}”的可用坐标`)
  }

  private async getCurrentMapCoordinate(): Promise<ResolvedCoordinate> {
    await this.ensurePreciseLocationPermission()
    const request: geoLocationManager.CurrentLocationRequest = {
      priority: geoLocationManager.LocationRequestPriority.ACCURACY,
      scenario: geoLocationManager.LocationRequestScenario.DAILY_LIFE_SERVICE,
      timeoutMs: 10000
    }
    const location = await geoLocationManager.getCurrentLocation(request)
    return await this.rectifyCoordinate(
      { latitude: location.latitude, longitude: location.longitude },
      mapCommon.CoordinateType.WGS84
    )
  }

  private async rectifyCoordinate(
    location: mapCommon.LatLng,
    coordinateType: mapCommon.CoordinateType
  ): Promise<ResolvedCoordinate> {
    const input: mapCommon.CoordinateLatLng = {
      coordinateType: coordinateType,
      location: location
    }
    const result = await map.rectifyCoordinate(this.ensureContext(), [input])
    if (result.length === 0) {
      return new ResolvedCoordinate(location, coordinateType)
    }
    return new ResolvedCoordinate(result[0].location, result[0].coordinateType)
  }

  private async enrichSiteDetails(sites: site.Site[], language: string | undefined): Promise<void> {
    const context = this.ensureContext()
    const detailCount = Math.min(sites.length, 5)
    for (let i = 0; i < detailCount; i++) {
      if (sites[i].siteId.trim() === '') {
        continue
      }
      try {
        const params: site.SearchByIdParams = {
          siteId: sites[i].siteId,
          language: this.normalizeLanguage(language)
        }
        const detail = await site.searchById(context, params)
        if (detail.site !== undefined) {
          sites[i] = detail.site
        }
      } catch (error) {
        console.warn('MapKitService', `Failed to enrich site ${sites[i].siteId}: ${JSON.stringify(error)}`)
      }
    }
  }

  private toPlaceResult(value: site.Site): MapPlaceResult {
    const result = new MapPlaceResult()
    result.siteId = value.siteId
    result.name = value.name || ''
    result.address = value.formatAddress || ''
    if (value.location !== undefined) {
      result.latitude = value.location.latitude
      result.longitude = value.location.longitude
    }
    result.distanceMeters = value.distance
    result.reliability = value.reliability
    if (value.poi !== undefined) {
      result.rating = value.poi.rating ?? value.poi.starRating
      result.poiTypes = value.poi.poiTypes || []
      result.phone = value.poi.phone || value.poi.internationalPhone || ''
      result.openingHours = value.poi.openingHours?.texts || []
      result.businessStatus = value.poi.businessStatus || ''
      result.description = value.poi.description || value.poi.abstractText || ''
    }
    return result
  }

  private toCoordinatePlaceResult(location: mapCommon.LatLng, name: string, address: string = ''): MapPlaceResult {
    const result = new MapPlaceResult()
    result.name = name.trim() !== '' ? name.trim() : '目的地'
    result.address = address
    result.latitude = location.latitude
    result.longitude = location.longitude
    return result
  }

  private resolvePlaceName(value: ResolvedPlace, fallback: string): string {
    if (value.savedLabel.trim() !== '') {
      return value.savedLabel
    }
    if (value.savedName.trim() !== '') {
      return value.savedName
    }
    return this.resolveSiteName(value.site, fallback)
  }

  private toVisualPlace(location: mapCommon.LatLng, name: string, address: string): MapVisualPlace {
    return new MapVisualPlace(location.latitude, location.longitude, name, address)
  }

  private toVisualPlaceFromResult(value: MapPlaceResult): MapVisualPlace {
    return new MapVisualPlace(value.latitude, value.longitude, value.name, value.address)
  }

  private collectRoutePoints(route: navi.Route): MapVisualCoordinate[] {
    const points: MapVisualCoordinate[] = []
    const overview = route.overviewPolyline || []
    if (overview.length > 0) {
      for (let i = 0; i < overview.length; i++) {
        points.push(new MapVisualCoordinate(overview[i].latitude, overview[i].longitude))
      }
      return points
    }
    for (let i = 0; i < route.steps.length; i++) {
      for (let j = 0; j < route.steps[i].roads.length; j++) {
        const polyline = route.steps[i].roads[j].polyline
        for (let k = 0; k < polyline.length; k++) {
          points.push(new MapVisualCoordinate(polyline[k].latitude, polyline[k].longitude))
        }
      }
    }
    return points
  }

  private cacheVisualization(data: MapVisualizationData): string {
    this.visualizationCounter += 1
    const token = `map_visual_${Date.now()}_${this.visualizationCounter}`
    data.token = token
    const serialized = JSON.stringify(data)
    this.visualizationCache.set(token, serialized)
    this.visualizationCacheKeys.push(token)
    this.persistVisualization(token, serialized)
    while (this.visualizationCacheKeys.length > MAX_VISUALIZATION_CACHE_SIZE) {
      const expired = this.visualizationCacheKeys.shift()
      if (expired !== undefined) {
        this.visualizationCache.delete(expired)
      }
    }
    return token
  }

  private getVisualizationDirectory(): string {
    if (this.context === null) {
      return ''
    }
    return `${this.context.filesDir}/${VISUALIZATION_DIRECTORY_NAME}`
  }

  private isValidVisualizationToken(token: string): boolean {
    return /^map_visual_[0-9]+_[0-9]+$/.test(token)
  }

  private getVisualizationPath(token: string): string {
    const directory = this.getVisualizationDirectory()
    if (directory === '' || !this.isValidVisualizationToken(token)) {
      return ''
    }
    return `${directory}/${token}.json`
  }

  private persistVisualization(token: string, serialized: string): void {
    const path = this.getVisualizationPath(token)
    const directory = this.getVisualizationDirectory()
    if (path === '' || directory === '') {
      return
    }
    let file: fileIo.File | null = null
    try {
      if (!fileIo.accessSync(directory)) {
        fileIo.mkdirSync(directory, true)
      }
      file = fileIo.openSync(path,
        fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC)
      fileIo.writeSync(file.fd, serialized)
      this.trimPersistedVisualizations()
    } catch (error) {
      console.warn('MapKitService', `Failed to persist map visualization: ${JSON.stringify(error)}`)
    } finally {
      if (file !== null) {
        fileIo.closeSync(file)
      }
    }
  }

  private readPersistedVisualization(token: string): string {
    const path = this.getVisualizationPath(token)
    if (path === '') {
      return ''
    }
    try {
      if (!fileIo.accessSync(path)) {
        return ''
      }
      return fileIo.readTextSync(path)
    } catch (error) {
      console.warn('MapKitService', `Failed to read map visualization: ${JSON.stringify(error)}`)
      return ''
    }
  }

  private trimPersistedVisualizations(): void {
    const directory = this.getVisualizationDirectory()
    if (directory === '') {
      return
    }
    try {
      if (!fileIo.accessSync(directory)) {
        return
      }
      const fileNames = fileIo.listFileSync(directory)
        .filter((name: string): boolean => name.startsWith('map_visual_') && name.endsWith('.json'))
        .sort()
      while (fileNames.length > MAX_PERSISTED_VISUALIZATION_COUNT) {
        const expired = fileNames.shift()
        if (expired !== undefined) {
          fileIo.unlinkSync(`${directory}/${expired}`)
        }
      }
    } catch (error) {
      console.warn('MapKitService', `Failed to trim map visualizations: ${JSON.stringify(error)}`)
    }
  }

  private buildFallbackVisualization(result: MapSearchRouteResult): MapVisualizationData {
    const data = new MapVisualizationData()
    data.token = result.visualToken || ''
    data.action = result.action || ''
    data.summary = result.summary || ''
    data.query = result.query || ''
    data.travelMode = result.travelMode || ''
    data.usedCurrentLocation = result.usedCurrentLocation === true
    data.showCurrentLocation = data.usedCurrentLocation
    if (result.destination !== null && result.destination !== undefined) {
      data.destination = this.toVisualPlaceFromResult(result.destination)
    }
    const places = result.places || []
    for (let i = 0; i < places.length; i++) {
      data.places.push(this.toVisualPlaceFromResult(places[i]))
    }
    if (data.destination === null && data.places.length > 0) {
      data.destination = data.places[0]
    }
    const routes = result.routes || []
    if (routes.length > 0) {
      data.distanceMeters = routes[0].distanceMeters
      data.durationSeconds = routes[0].durationInTrafficSeconds ?? routes[0].durationSeconds
    }
    return data
  }

  private toRouteAlternative(route: navi.Route, index: number): MapRouteAlternative {
    const result = new MapRouteAlternative()
    result.index = index
    result.trafficLightCount = route.trafficLightCount
    result.hasTolls = route.hasTolls
    result.hasFerry = route.hasFerry
    result.hasStairs = route.hasStairs
    result.hasRestrictedRoad = route.hasRestrictedRoad
    let trafficDuration = 0
    let hasTrafficDuration = false
    for (let i = 0; i < route.steps.length; i++) {
      const step = route.steps[i]
      result.distanceMeters += step.distance || 0
      result.durationSeconds += step.duration || 0
      if (step.durationInTraffic !== undefined) {
        trafficDuration += step.durationInTraffic
        hasTrafficDuration = true
      }
      for (let j = 0; j < step.roads.length && result.roads.length < 12; j++) {
        const road = step.roads[j]
        const summary = new MapRoadSummary()
        summary.roadName = road.roadName || ''
        summary.action = road.action || ''
        summary.distanceMeters = road.distance
        summary.durationSeconds = road.duration
        result.roads.push(summary)
      }
    }
    if (hasTrafficDuration) {
      result.durationInTrafficSeconds = trafficDuration
    }
    return result
  }

  private firstCoordinate(
    camelValue: MapCoordinateArgs | undefined,
    snakeValue: MapCoordinateArgs | undefined
  ): MapCoordinateArgs | undefined {
    return camelValue !== undefined ? camelValue : snakeValue
  }

  private readCoordinate(value: MapCoordinateArgs | undefined): mapCommon.LatLng | null {
    if (value === undefined) {
      return null
    }
    const latitude = this.readNumber(value.latitude)
    const longitude = this.readNumber(value.longitude)
    if (latitude === undefined || longitude === undefined) {
      return null
    }
    if (latitude < -85.2 || latitude > 85.2 || longitude < -180 || longitude >= 180) {
      throw new Error('经纬度超出 Map Kit 支持范围')
    }
    return { latitude: latitude, longitude: longitude }
  }

  private readNumber(value: number | string | undefined): number | undefined {
    if (value === undefined || value === '') {
      return undefined
    }
    const result = typeof value === 'number' ? value : Number(value)
    return Number.isNaN(result) ? undefined : result
  }

  private readBoolean(value: boolean | string | undefined, fallback: boolean): boolean {
    if (value === undefined) {
      return fallback
    }
    if (typeof value === 'boolean') {
      return value
    }
    const normalized = value.trim().toLowerCase()
    if (normalized === 'true' || normalized === '1' || normalized === 'yes') {
      return true
    }
    if (normalized === 'false' || normalized === '0' || normalized === 'no') {
      return false
    }
    return fallback
  }

  private normalizeRadius(value: number | string | undefined): number {
    const parsed = this.readNumber(value)
    if (parsed === undefined) {
      return DEFAULT_SEARCH_RADIUS_METERS
    }
    return Math.floor(Math.min(50000, Math.max(1, parsed)))
  }

  private normalizeLimit(value: number | string | undefined): number {
    const parsed = this.readNumber(value)
    if (parsed === undefined) {
      return DEFAULT_RESULT_LIMIT
    }
    return Math.floor(Math.min(MAX_RESULT_LIMIT, Math.max(1, parsed)))
  }

  private normalizeLanguage(value: string | undefined): string {
    const language = (value || '').trim()
    return language !== '' ? language : 'zh_CN'
  }

  private normalizeCoordinateType(value: string | undefined): mapCommon.CoordinateType {
    return (value || '').trim().toLowerCase() === 'wgs84'
      ? mapCommon.CoordinateType.WGS84
      : mapCommon.CoordinateType.GCJ02
  }

  private normalizeOpenAction(value: string | undefined): string {
    const action = (value || '').trim().toLowerCase()
    return action === MAP_OPEN_ACTION_NAVIGATION || action === 'navi'
      ? MAP_OPEN_ACTION_NAVIGATION
      : MAP_OPEN_ACTION_ROUTE
  }

  private toVehicleType(value: string | undefined): petalMaps.VehicleType {
    const mode = normalizeMapTravelMode(value)
    if (mode === 'walking') {
      return petalMaps.VehicleType.WALKING
    }
    if (mode === 'cycling') {
      return petalMaps.VehicleType.CYCLING
    }
    if (mode === 'transit') {
      return petalMaps.VehicleType.TRANSIT
    }
    return petalMaps.VehicleType.DRIVING
  }

  private resolveSiteName(value: site.Site | null, fallback: string): string {
    if (value !== null && (value.name || '').trim() !== '') {
      return value.name || ''
    }
    return fallback.trim() !== '' ? fallback.trim() : '目的地'
  }

  private travelModeLabel(mode: string): string {
    if (mode === 'walking') {
      return '步行'
    }
    if (mode === 'cycling') {
      return '骑行'
    }
    return '驾车'
  }

  private ensureContext(): common.UIAbilityContext {
    if (this.context === null) {
      throw new Error('地图服务尚未初始化')
    }
    return this.context
  }

  private async ensurePreciseLocationPermission(): Promise<void> {
    // HarmonyOS API 9+ requires both permissions in one request to grant meter-level location.
    const precisePermission: Permissions = 'ohos.permission.LOCATION'
    const approximatePermission: Permissions = 'ohos.permission.APPROXIMATELY_LOCATION'
    const manager = abilityAccessCtrl.createAtManager()
    try {
      const result: PermissionRequestResult = await manager.requestPermissionsFromUser(
        this.ensureContext(),
        [precisePermission, approximatePermission]
      )
      if (result.authResults.length < 2 || result.authResults[0] !== 0 || result.authResults[1] !== 0) {
        throw new Error('用户未授权精确位置；请选择精确位置，或提供起点/搜索中心坐标后重试')
      }
    } catch (error) {
      if (error instanceof Error) {
        if (error.message.startsWith('用户未授权精确位置')) {
          throw error
        }
        throw new Error('申请精确位置权限失败: ' + error.message)
      }
      throw new Error('申请精确位置权限失败: ' + JSON.stringify(error))
    }
  }

  private toMapError(error: Object): Error {
    if (error instanceof Error) {
      const businessError = error as BusinessError
      if (businessError.code === 1002600004) {
        return new Error('地图服务未开通；请在 DevEco Studio 或 AppGallery Connect 中启用 Map Kit，并重新申请调试 Profile')
      }
      if (businessError.code === 1002600003) {
        return new Error('Map Kit 应用鉴权失败；请确认当前签名/Profile 对应已开通地图服务的应用')
      }
      if (businessError.code !== undefined && businessError.code !== 0) {
        return new Error(`地图服务调用失败（${businessError.code}）：${businessError.message}`)
      }
      return error
    }
    return new Error('地图服务调用失败: ' + JSON.stringify(error))
  }
}

export function getMapKitService(): MapKitService {
  return MapKitService.getInstance()
}
