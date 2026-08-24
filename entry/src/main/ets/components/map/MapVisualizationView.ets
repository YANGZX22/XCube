import { AsyncCallback, BusinessError } from '@kit.BasicServicesKit'
import { MapComponent, map, mapCommon } from '@kit.MapKit'
import { image } from '@kit.ImageKit'
import {
  MapVisualCoordinate,
  MapVisualizationData,
  MapVisualPlace
} from '../../services/MapKitService'
import { getAppUiState } from '../../state/AppUiState'

const DEFAULT_MAP_CENTER: mapCommon.LatLng = { latitude: 39.9042, longitude: 116.4074 }
const ROUTE_COLOR: number = 0xFF7A68F0
const MARKER_WIDTH_VP: number = 28
const MARKER_HEIGHT_VP: number = 35

@ComponentV2
export struct MapVisualizationView {
  @Param visualizationJson: string = ''
  @Param compact: boolean = false
  @Param followMode: boolean = false
  @Param followRequestId: number = 0
  @Param overviewRequestId: number = 0
  @Param controlsTopInsetVp: number = 0
  @Param controlsBottomInsetVp: number = 0
  @Event onMapGesture: () => void = (): void => {}
  private data: MapVisualizationData = new MapVisualizationData()
  private mapOptions: mapCommon.MapOptions | undefined = undefined
  private mapCallback: AsyncCallback<map.MapComponentController> | undefined = undefined
  private mapController: map.MapComponentController | null = null
  private mapEventManager: map.MapEventManager | null = null
  private cameraMoveStartCallback: ((reason: number) => void) | null = null
  private markerPixelMap: image.PixelMap | null = null
  private fitRouteTimer: number = -1

  aboutToAppear(): void {
    this.data = this.parseVisualization(this.visualizationJson)
    const center = this.resolveInitialCenter()
    this.mapOptions = {
      position: {
        target: center,
        zoom: this.data.routePoints.length > 0 ? 13 : 15
      },
      rotateGesturesEnabled: !this.compact,
      scrollGesturesEnabled: true,
      zoomGesturesEnabled: true,
      tiltGesturesEnabled: !this.compact,
      zoomControlsEnabled: false,
      myLocationControlsEnabled: !this.compact && this.data.showCurrentLocation,
      compassControlsEnabled: true,
      scaleControlsEnabled: !this.compact,
      padding: this.getControlsPadding(),
      dayNightMode: getAppUiState().isDarkMode ? mapCommon.DayNightMode.NIGHT : mapCommon.DayNightMode.DAY
    }
    this.mapCallback = (error: BusinessError, controller: map.MapComponentController): void => {
      if (error) {
        console.error('MapVisualizationView', `Map initialization failed: ${JSON.stringify(error)}`)
        return
      }
      this.mapController = controller
      this.initializeController(controller).catch((reason: Error): void => {
        console.error('MapVisualizationView', `Map overlay initialization failed: ${JSON.stringify(reason)}`)
      })
    }
  }

  aboutToDisappear(): void {
    if (this.fitRouteTimer >= 0) {
      clearTimeout(this.fitRouteTimer)
      this.fitRouteTimer = -1
    }
    if (this.mapController !== null && this.data.showCurrentLocation) {
      try {
        this.mapController.setMyLocationEnabled(false)
      } catch (_error) {
      }
    }
    if (this.mapEventManager !== null && this.cameraMoveStartCallback !== null) {
      this.mapEventManager.off('cameraMoveStart', this.cameraMoveStartCallback)
    }
    this.mapEventManager = null
    this.cameraMoveStartCallback = null
    if (this.markerPixelMap !== null) {
      this.markerPixelMap.release().catch((error: Error): void => {
        console.warn('MapVisualizationView', `Failed to release marker PixelMap: ${JSON.stringify(error)}`)
      })
      this.markerPixelMap = null
    }
    this.mapController = null
  }

  @Monitor('followMode')
  onFollowModeChange(): void {
    if (this.mapController === null || !this.data.showCurrentLocation) {
      return
    }
    this.applyLocationStyle(this.mapController).catch((error: Error): void => {
      console.error('MapVisualizationView', `Failed to update follow mode: ${JSON.stringify(error)}`)
    })
  }

  @Monitor('followRequestId')
  onFollowRequestIdChange(): void {
    this.followCurrentLocation().catch((error: Error): void => {
      console.error('MapVisualizationView', `Failed to return to current location: ${JSON.stringify(error)}`)
    })
  }

  @Monitor('overviewRequestId')
  onOverviewRequestIdChange(): void {
    if (this.mapController === null) {
      this.scheduleFitRoute()
      return
    }
    if (this.fitRouteTimer >= 0) {
      clearTimeout(this.fitRouteTimer)
      this.fitRouteTimer = -1
    }
    this.fitVisiblePoints()
  }

  @Monitor('controlsTopInsetVp', 'controlsBottomInsetVp')
  onControlsInsetChange(): void {
    if (this.mapController !== null) {
      this.mapController.setPadding(this.getControlsPadding())
    }
  }

  private getControlsPadding(): mapCommon.Padding {
    if (this.compact) {
      return { left: 0, top: 0, right: 0, bottom: 0 }
    }
    const uiContext = this.getUIContext()
    return {
      left: uiContext.vp2px(12),
      top: uiContext.vp2px(Math.max(0, this.controlsTopInsetVp)),
      right: uiContext.vp2px(12),
      bottom: uiContext.vp2px(Math.max(0, this.controlsBottomInsetVp))
    }
  }

  private parseVisualization(value: string): MapVisualizationData {
    if (value.trim() === '') {
      return new MapVisualizationData()
    }
    try {
      return JSON.parse(value) as MapVisualizationData
    } catch (_error) {
      return new MapVisualizationData()
    }
  }

  private resolveInitialCenter(): mapCommon.LatLng {
    if (this.data.origin !== null) {
      return this.toLatLng(this.data.origin)
    }
    if (this.data.currentLocation !== null) {
      return this.toLatLng(this.data.currentLocation)
    }
    if (this.data.destination !== null) {
      return this.toLatLng(this.data.destination)
    }
    if (this.data.places.length > 0) {
      return this.toLatLng(this.data.places[0])
    }
    if (this.data.routePoints.length > 0) {
      return this.toLatLng(this.data.routePoints[0])
    }
    return DEFAULT_MAP_CENTER
  }

  private async initializeController(controller: map.MapComponentController): Promise<void> {
    if (!this.compact) {
      this.mapEventManager = controller.getEventManager()
      this.cameraMoveStartCallback = (reason: number): void => {
        if (reason === 1 && this.followMode) {
          this.onMapGesture()
        }
      }
      this.mapEventManager.on('cameraMoveStart', this.cameraMoveStartCallback)
    }
    controller.setCompassControlsEnabled(true)
    controller.setMyLocationControlsEnabled(!this.compact && this.data.showCurrentLocation)
    controller.setPadding(this.getControlsPadding())
    if (this.data.routePoints.length > 1) {
      const routePoints: mapCommon.LatLng[] = []
      for (let i = 0; i < this.data.routePoints.length; i++) {
        routePoints.push(this.toLatLng(this.data.routePoints[i]))
      }
      await controller.addPolyline({
        points: routePoints,
        color: ROUTE_COLOR,
        width: this.compact ? 8 : 12,
        startCap: mapCommon.CapStyle.ROUND,
        endCap: mapCommon.CapStyle.ROUND,
        jointType: mapCommon.JointType.ROUND,
        clickable: false
      })
    }

    if (this.data.origin !== null && !this.data.usedCurrentLocation) {
      await this.addPlaceMarker(controller, this.data.origin, '起点')
    }
    if (this.data.action === 'search_places') {
      const markerCount = Math.min(this.data.places.length, 8)
      for (let i = 0; i < markerCount; i++) {
        await this.addPlaceMarker(controller, this.data.places[i], `候选 ${i + 1}`)
      }
    } else if (this.data.destination !== null) {
      await this.addPlaceMarker(controller, this.data.destination, '目的地')
    }

    if (this.data.showCurrentLocation) {
      await this.applyLocationStyle(controller)
      controller.setMyLocationEnabled(true)
    }
    if (!this.followMode || this.compact) {
      this.scheduleFitRoute()
    }
  }

  private async addPlaceMarker(
    controller: map.MapComponentController,
    place: MapVisualPlace,
    fallbackTitle: string
  ): Promise<void> {
    const options: mapCommon.MarkerOptions = {
      position: this.toLatLng(place),
      title: place.name.trim() !== '' ? place.name : fallbackTitle,
      snippet: place.address,
      clickable: true
    }
    options.icon = this.getMarkerPixelMap()
    options.anchorU = 0.5
    options.anchorV = 1
    await controller.addMarker(options)
  }

  private getMarkerPixelMap(): image.PixelMap {
    if (this.markerPixelMap !== null) {
      return this.markerPixelMap
    }
    const density = this.getUIContext().getHostContext()?.resourceManager
      .getDeviceCapabilitySync().screenDensity ?? 480
    const densityScale = Math.max(1, density / 160)
    const markerWidth = Math.round(MARKER_WIDTH_VP * densityScale)
    const markerHeight = Math.round(MARKER_HEIGHT_VP * densityScale)
    const color = this.parseThemeColor(getAppUiState().themePrimary)
    const pixels = new Uint8Array(markerWidth * markerHeight * 4)
    const sampleOffsets: number[] = [0.125, 0.375, 0.625, 0.875]
    const centerX = markerWidth / 2
    const headCenterY = markerHeight * 0.3625
    const innerRadius = markerWidth * 0.1875
    for (let y = 0; y < markerHeight; y++) {
      for (let x = 0; x < markerWidth; x++) {
        let outerSamples = 0
        let innerSamples = 0
        for (let sy = 0; sy < sampleOffsets.length; sy++) {
          for (let sx = 0; sx < sampleOffsets.length; sx++) {
            const sampleX = x + sampleOffsets[sx]
            const sampleY = y + sampleOffsets[sy]
            if (this.isInsideMarker(sampleX, sampleY, markerWidth, markerHeight)) {
              outerSamples += 1
            }
            const innerDx = sampleX - centerX
            const innerDy = sampleY - headCenterY
            if (innerDx * innerDx + innerDy * innerDy <= innerRadius * innerRadius) {
              innerSamples += 1
            }
          }
        }
        const sampleCount = sampleOffsets.length * sampleOffsets.length
        const outerAlpha = outerSamples / sampleCount
        const innerAlpha = innerSamples / sampleCount
        const themeAlpha = Math.max(0, outerAlpha - innerAlpha)
        const index = (y * markerWidth + x) * 4
        pixels[index] = Math.round(color[2] * themeAlpha + 255 * innerAlpha)
        pixels[index + 1] = Math.round(color[1] * themeAlpha + 255 * innerAlpha)
        pixels[index + 2] = Math.round(color[0] * themeAlpha + 255 * innerAlpha)
        pixels[index + 3] = Math.round(outerAlpha * 255)
      }
    }
    this.markerPixelMap = image.createPixelMapSync(pixels.buffer, {
      size: { width: markerWidth, height: markerHeight },
      srcPixelFormat: image.PixelMapFormat.BGRA_8888,
      pixelFormat: image.PixelMapFormat.RGBA_8888,
      editable: false
    })
    return this.markerPixelMap
  }

  private isInsideMarker(x: number, y: number, width: number, height: number): boolean {
    const centerX = width / 2
    const headCenterY = height * 0.3625
    const headRadius = width * 0.453125
    const dx = x - centerX
    const dy = y - headCenterY
    const insideHead = dx * dx + dy * dy <= headRadius * headRadius
    if (insideHead) {
      return true
    }
    const markerBottom = height - 0.5
    if (y < headCenterY || y > markerBottom) {
      return false
    }
    const halfWidth = (markerBottom - y) * width / height * 0.48
    return Math.abs(dx) <= halfWidth
  }

  private parseThemeColor(value: string): number[] {
    const normalized = /^#[0-9A-Fa-f]{6}$/.test(value) ? value.substring(1) : '7A68F0'
    return [
      Number.parseInt(normalized.substring(0, 2), 16),
      Number.parseInt(normalized.substring(2, 4), 16),
      Number.parseInt(normalized.substring(4, 6), 16)
    ]
  }

  private async applyLocationStyle(controller: map.MapComponentController): Promise<void> {
    const displayType = this.followMode && !this.compact
      ? mapCommon.MyLocationDisplayType.FOLLOW_ROTATE
      : mapCommon.MyLocationDisplayType.TRACK_ROTATE
    await controller.setMyLocationStyle({
      displayType: displayType,
      radiusFillColor: 0x337A68F0
    })
  }

  private async followCurrentLocation(): Promise<void> {
    if (this.mapController === null || !this.data.showCurrentLocation) {
      return
    }
    this.mapController.setMyLocationEnabled(true)
    await this.applyLocationStyle(this.mapController)
    const currentLocation = this.data.currentLocation ??
      (this.data.usedCurrentLocation ? this.data.origin : null)
    if (currentLocation === null) {
      return
    }
    const cameraPosition = this.mapController.getCameraPosition()
    this.mapController.animateCamera(
      map.newLatLng(this.toLatLng(currentLocation), Math.max(cameraPosition.zoom, 16)),
      400
    )
  }

  private scheduleFitRoute(): void {
    if (this.fitRouteTimer >= 0) {
      clearTimeout(this.fitRouteTimer)
    }
    this.fitRouteTimer = setTimeout((): void => {
      this.fitRouteTimer = -1
      this.fitVisiblePoints()
    }, 180)
  }

  private fitVisiblePoints(): void {
    if (this.mapController === null) {
      return
    }
    const points = this.collectVisiblePoints()
    if (points.length === 0) {
      return
    }
    if (points.length === 1) {
      this.mapController.animateCamera(map.newLatLng(points[0], 15), 300)
      return
    }
    let minLatitude = points[0].latitude
    let maxLatitude = points[0].latitude
    let minLongitude = points[0].longitude
    let maxLongitude = points[0].longitude
    for (let i = 1; i < points.length; i++) {
      minLatitude = Math.min(minLatitude, points[i].latitude)
      maxLatitude = Math.max(maxLatitude, points[i].latitude)
      minLongitude = Math.min(minLongitude, points[i].longitude)
      maxLongitude = Math.max(maxLongitude, points[i].longitude)
    }
    const bounds: mapCommon.LatLngBounds = {
      northeast: { latitude: maxLatitude, longitude: maxLongitude },
      southwest: { latitude: minLatitude, longitude: minLongitude }
    }
    this.mapController.animateCamera(map.newLatLngBounds(bounds, this.compact ? 32 : 96), 400)
  }

  private collectVisiblePoints(): mapCommon.LatLng[] {
    const points: mapCommon.LatLng[] = []
    for (let i = 0; i < this.data.routePoints.length; i++) {
      points.push(this.toLatLng(this.data.routePoints[i]))
    }
    if (points.length === 0 && this.data.origin !== null) {
      points.push(this.toLatLng(this.data.origin))
    }
    if (this.data.currentLocation !== null) {
      points.push(this.toLatLng(this.data.currentLocation))
    }
    if (this.data.destination !== null) {
      points.push(this.toLatLng(this.data.destination))
    }
    if (this.data.action === 'search_places') {
      const pointCount = Math.min(this.data.places.length, 8)
      for (let i = 0; i < pointCount; i++) {
        points.push(this.toLatLng(this.data.places[i]))
      }
    }
    return points
  }

  private toLatLng(value: MapVisualCoordinate): mapCommon.LatLng {
    return { latitude: value.latitude, longitude: value.longitude }
  }

  build() {
    Stack() {
      if (this.mapOptions !== undefined && this.mapCallback !== undefined) {
        MapComponent({
          mapOptions: this.mapOptions,
          mapCallback: this.mapCallback
        })
          .width('100%')
          .height('100%')
      } else {
        Column() {
          LoadingProgress()
            .width(28)
            .height(28)
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
      }
    }
    .width('100%')
    .height('100%')
  }
}
