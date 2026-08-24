import { uiMaterial } from '@kit.ArkUI'
import { AsyncCallback, BusinessError } from '@kit.BasicServicesKit'
import { image } from '@kit.ImageKit'
import { MapComponent, map, mapCommon } from '@kit.MapKit'
import { MapCoordinateArgs, MapPlaceResult } from '../services/MapKitService'
import { cloneSavedPlace, SavedPlace } from '../services/SavedPlacesService'
import { ServiceRegistry } from '../services/ServiceRegistry'
import { getAppUiState } from '../state/AppUiState'
import { pickLocalizedText } from '../utils/LocalizedTextUtils'
import { showSnackBar, SnackBarDisplayOptions, SnackBarTone } from '../utils/ToastUtil'
import { ChatFloatingImmersiveButton } from './ChatFloatingImmersiveButton'
import { ImmersiveSheetHeader } from './ImmersiveSheetHeader'

const DEFAULT_PICKER_CENTER: mapCommon.LatLng = { latitude: 39.9042, longitude: 116.4074 }
const INVALID_COORDINATE: number = 1000
const PICKER_MARKER_WIDTH_VP: number = 26
const PICKER_MARKER_HEIGHT_VP: number = 33

function createSavedPlaceMaterial(interactive: boolean = false): uiMaterial.Material {
  return new uiMaterial.ImmersiveMaterial({
    style: uiMaterial.ImmersiveStyle.ULTRA_THIN,
    materialColor: Color.Transparent,
    applyShadow: true,
    interactive: interactive,
    lightEffect: { color: undefined }
  })
}

@ComponentV2
struct SavedPlaceMapPicker {
  @Param selectedLatitude: number = INVALID_COORDINATE
  @Param selectedLongitude: number = INVALID_COORDINATE
  @Param centerLatitude: number = INVALID_COORDINATE
  @Param centerLongitude: number = INVALID_COORDINATE
  @Event onSelect: (latitude: number, longitude: number) => void =
    (_latitude: number, _longitude: number): void => {}
  private mapOptions: mapCommon.MapOptions | undefined = undefined
  private mapCallback: AsyncCallback<map.MapComponentController> | undefined = undefined
  private mapController: map.MapComponentController | null = null
  private mapEventManager: map.MapEventManager | null = null
  private mapClickCallback: ((location: mapCommon.LatLng | undefined) => void) | null = null
  private marker: map.Marker | null = null
  private markerPixelMap: image.PixelMap | null = null
  private markerAdding: boolean = false
  private markerAddGeneration: number = 0

  private isValidCoordinate(latitude: number, longitude: number): boolean {
    return Number.isFinite(latitude) && Number.isFinite(longitude) &&
      latitude >= -90 && latitude <= 90 && longitude >= -180 && longitude <= 180
  }

  private getCenter(): mapCommon.LatLng {
    if (this.isValidCoordinate(this.centerLatitude, this.centerLongitude)) {
      return { latitude: this.centerLatitude, longitude: this.centerLongitude }
    }
    if (this.isValidCoordinate(this.selectedLatitude, this.selectedLongitude)) {
      return { latitude: this.selectedLatitude, longitude: this.selectedLongitude }
    }
    return DEFAULT_PICKER_CENTER
  }

  aboutToAppear(): void {
    this.mapOptions = {
      position: { target: this.getCenter(), zoom: 16 },
      rotateGesturesEnabled: true,
      scrollGesturesEnabled: true,
      zoomGesturesEnabled: true,
      tiltGesturesEnabled: false,
      zoomControlsEnabled: false,
      myLocationControlsEnabled: false,
      compassControlsEnabled: true,
      scaleControlsEnabled: true,
      dayNightMode: getAppUiState().isDarkMode ? mapCommon.DayNightMode.NIGHT : mapCommon.DayNightMode.DAY
    }
    this.mapCallback = (error: BusinessError, controller: map.MapComponentController): void => {
      if (error) {
        console.error('SavedPlaceMapPicker', `Map initialization failed: ${JSON.stringify(error)}`)
        return
      }
      this.mapController = controller
      this.mapEventManager = controller.getEventManager()
      this.mapClickCallback = (location: mapCommon.LatLng | undefined): void => {
        if (location === undefined) {
          return
        }
        this.onSelect(location.latitude, location.longitude)
      }
      this.mapEventManager.on('mapClick', this.mapClickCallback)
      this.updateMarker()
      controller.animateCamera(map.newLatLng(this.getCenter(), 16), 0)
    }
  }

  aboutToDisappear(): void {
    this.markerAddGeneration += 1
    this.markerAdding = false
    if (this.mapEventManager !== null && this.mapClickCallback !== null) {
      try {
        // Some Map Kit implementations also invoke this argument as a no-value
        // unsubscribe completion callback. The listener therefore accepts undefined.
        this.mapEventManager.off('mapClick', this.mapClickCallback)
      } catch (error) {
        console.warn('SavedPlaceMapPicker', `Failed to unsubscribe map click: ${JSON.stringify(error)}`)
      }
    }
    this.mapEventManager = null
    this.mapClickCallback = null
    if (this.marker !== null) {
      this.marker.remove()
      this.marker = null
    }
    if (this.markerPixelMap !== null) {
      this.markerPixelMap.release().catch((error: Error): void => {
        console.warn('SavedPlaceMapPicker', `Failed to release marker: ${JSON.stringify(error)}`)
      })
      this.markerPixelMap = null
    }
    this.mapController = null
  }

  @Monitor('selectedLatitude', 'selectedLongitude')
  onSelectedCoordinateChange(): void {
    this.updateMarker()
  }

  @Monitor('centerLatitude', 'centerLongitude')
  onCenterCoordinateChange(): void {
    if (this.mapController !== null && this.isValidCoordinate(this.centerLatitude, this.centerLongitude)) {
      this.mapController.animateCamera(map.newLatLng({
        latitude: this.centerLatitude,
        longitude: this.centerLongitude
      }, 16), 320)
    }
  }

  private updateMarker(): void {
    if (this.mapController === null || !this.isValidCoordinate(this.selectedLatitude, this.selectedLongitude)) {
      return
    }
    const position: mapCommon.LatLng = {
      latitude: this.selectedLatitude,
      longitude: this.selectedLongitude
    }
    if (this.marker !== null) {
      this.marker.setPosition(position)
      return
    }
    if (this.markerAdding) {
      return
    }
    this.markerAdding = true
    const markerAddGeneration = ++this.markerAddGeneration
    this.mapController.addMarker({
      position: position,
      icon: this.getMarkerPixelMap(),
      anchorU: 0.5,
      anchorV: 1,
      clickable: false
    }).then((marker: map.Marker): void => {
      if (markerAddGeneration !== this.markerAddGeneration || this.mapController === null) {
        marker.remove()
        return
      }
      this.marker = marker
      if (this.isValidCoordinate(this.selectedLatitude, this.selectedLongitude)) {
        marker.setPosition({
          latitude: this.selectedLatitude,
          longitude: this.selectedLongitude
        })
      }
    }).catch((error: Error): void => {
      console.error('SavedPlaceMapPicker', `Failed to add marker: ${JSON.stringify(error)}`)
    }).finally((): void => {
      if (markerAddGeneration === this.markerAddGeneration) {
        this.markerAdding = false
      }
    })
  }

  private getMarkerPixelMap(): image.PixelMap {
    if (this.markerPixelMap !== null) {
      return this.markerPixelMap
    }
    const density = this.getUIContext().getHostContext()?.resourceManager
      .getDeviceCapabilitySync().screenDensity ?? 480
    const densityScale = Math.max(1, density / 160)
    const markerWidth = Math.round(PICKER_MARKER_WIDTH_VP * densityScale)
    const markerHeight = Math.round(PICKER_MARKER_HEIGHT_VP * densityScale)
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
    if (dx * dx + dy * dy <= headRadius * headRadius) {
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

  build() {
    Stack() {
      if (this.mapOptions !== undefined && this.mapCallback !== undefined) {
        MapComponent({ mapOptions: this.mapOptions, mapCallback: this.mapCallback })
          .width('100%')
          .height('100%')
      } else {
        LoadingProgress()
          .width(28)
          .height(28)
          .color(getAppUiState().themePrimary)
      }
    }
    .width('100%')
    .height('100%')
    .borderRadius(20)
    .clip(true)
  }
}

@ComponentV2
struct SavedPlaceEditorSheetContent {
  @Param placeJson: string = ''
  @Event onClose: () => void = (): void => {}
  @Event onSaved: (place: SavedPlace) => void = (_place: SavedPlace): void => {}
  @Local label: string = ''
  @Local searchQuery: string = ''
  @Local searchResults: MapPlaceResult[] = []
  @Local selectedName: string = ''
  @Local selectedAddress: string = ''
  @Local selectedSiteId: string = ''
  @Local selectedLatitude: number = INVALID_COORDINATE
  @Local selectedLongitude: number = INVALID_COORDINATE
  @Local centerLatitude: number = INVALID_COORDINATE
  @Local centerLongitude: number = INVALID_COORDINATE
  @Local isSearching: boolean = false
  @Local isResolving: boolean = false
  @Local isLocating: boolean = false
  @Local isSaving: boolean = false
  @Local errorMessage: string = ''
  private originalPlace: SavedPlace = new SavedPlace()
  private resolveSequence: number = 0

  private get themePrimary(): string {
    return getAppUiState().themePrimary
  }

  aboutToAppear(): void {
    this.resolveSequence += 1
    this.originalPlace = new SavedPlace()
    this.label = ''
    this.searchQuery = ''
    this.searchResults = []
    this.selectedName = ''
    this.selectedAddress = ''
    this.selectedSiteId = ''
    this.selectedLatitude = INVALID_COORDINATE
    this.selectedLongitude = INVALID_COORDINATE
    this.centerLatitude = INVALID_COORDINATE
    this.centerLongitude = INVALID_COORDINATE
    this.isSearching = false
    this.isResolving = false
    this.isLocating = false
    this.isSaving = false
    this.errorMessage = ''
    if (this.placeJson.trim() !== '') {
      try {
        this.originalPlace = JSON.parse(this.placeJson) as SavedPlace
      } catch (_error) {
        this.originalPlace = new SavedPlace()
      }
    }
    this.label = this.originalPlace.label || ''
    if (this.originalPlace.id !== '' &&
      this.isValidCoordinate(this.originalPlace.latitude, this.originalPlace.longitude)) {
      this.selectedName = this.originalPlace.name || ''
      this.selectedAddress = this.originalPlace.address || ''
      this.selectedSiteId = this.originalPlace.siteId || ''
      this.selectedLatitude = this.originalPlace.latitude
      this.selectedLongitude = this.originalPlace.longitude
      this.centerLatitude = this.originalPlace.latitude
      this.centerLongitude = this.originalPlace.longitude
    }
  }

  private isValidCoordinate(latitude: number, longitude: number): boolean {
    return Number.isFinite(latitude) && Number.isFinite(longitude) &&
      latitude >= -90 && latitude <= 90 && longitude >= -180 && longitude <= 180
  }

  private canSave(): boolean {
    return this.label.trim() !== '' && this.isValidCoordinate(this.selectedLatitude, this.selectedLongitude) &&
      !this.isResolving
  }

  private handleSearch(): void {
    const query = this.searchQuery.trim()
    if (query === '' || this.isSearching) {
      return
    }
    this.isSearching = true
    this.errorMessage = ''
    let bias: MapCoordinateArgs | undefined = undefined
    if (this.isValidCoordinate(this.centerLatitude, this.centerLongitude)) {
      bias = { latitude: this.centerLatitude, longitude: this.centerLongitude }
    }
    ServiceRegistry.mapKit().searchPlaceCandidates(query, 8, 'zh_CN', bias)
      .then((results: MapPlaceResult[]): void => {
        this.searchResults = [...results]
        if (results.length === 0) {
          this.errorMessage = pickLocalizedText('没有找到相关地点', 'No matching places found')
        }
      })
      .catch((error: Error): void => {
        this.errorMessage = error.message
      })
      .finally((): void => {
        this.isSearching = false
      })
  }

  private selectSearchResult(place: MapPlaceResult): void {
    this.applyPlace(place)
    this.searchResults = []
    try {
      this.getUIContext().getFocusController().clearFocus()
    } catch (_error) {
    }
  }

  private applyPlace(place: MapPlaceResult): void {
    this.selectedName = place.name
    this.selectedAddress = place.address
    this.selectedSiteId = place.siteId
    this.selectedLatitude = place.latitude
    this.selectedLongitude = place.longitude
    this.centerLatitude = place.latitude
    this.centerLongitude = place.longitude
    this.errorMessage = ''
  }

  private handleMapSelect(latitude: number, longitude: number): void {
    this.resolveSequence += 1
    const sequence = this.resolveSequence
    this.selectedLatitude = latitude
    this.selectedLongitude = longitude
    this.centerLatitude = latitude
    this.centerLongitude = longitude
    this.selectedName = pickLocalizedText('地图选点', 'Map selection')
    this.selectedAddress = `${latitude.toFixed(6)}, ${longitude.toFixed(6)}`
    this.selectedSiteId = ''
    this.isResolving = true
    this.errorMessage = ''
    ServiceRegistry.mapKit().reverseGeocodePlace({ latitude: latitude, longitude: longitude }, 'zh_CN')
      .then((place: MapPlaceResult): void => {
        if (sequence === this.resolveSequence) {
          this.applyPlace(place)
        }
      })
      .catch((error: Error): void => {
        if (sequence === this.resolveSequence) {
          this.errorMessage = pickLocalizedText(`已选择坐标，地址解析失败：${error.message}`,
            `Coordinate selected; address lookup failed: ${error.message}`)
        }
      })
      .finally((): void => {
        if (sequence === this.resolveSequence) {
          this.isResolving = false
        }
      })
  }

  private handleUseCurrentLocation(): void {
    if (this.isLocating) {
      return
    }
    this.isLocating = true
    this.errorMessage = ''
    ServiceRegistry.mapKit().getCurrentPlace('zh_CN')
      .then((place: MapPlaceResult): void => {
        this.applyPlace(place)
      })
      .catch((error: Error): void => {
        this.errorMessage = error.message
      })
      .finally((): void => {
        this.isLocating = false
      })
  }

  private handleSave(): void {
    if (!this.canSave() || this.isSaving) {
      return
    }
    const place = cloneSavedPlace(this.originalPlace)
    place.label = this.label
    place.name = this.selectedName
    place.address = this.selectedAddress
    place.siteId = this.selectedSiteId
    place.latitude = this.selectedLatitude
    place.longitude = this.selectedLongitude
    place.coordinateType = 'gcj02'
    this.isSaving = true
    this.errorMessage = ''
    ServiceRegistry.savedPlaces().savePlace(place)
      .then((saved: SavedPlace): void => {
        this.onSaved(saved)
      })
      .catch((error: Error): void => {
        this.errorMessage = error.message
      })
      .finally((): void => {
        this.isSaving = false
      })
  }

  build() {
    Column() {
      ImmersiveSheetHeader({
        title: this.originalPlace.id !== ''
          ? pickLocalizedText('编辑常用地点', 'Edit Saved Place')
          : pickLocalizedText('添加常用地点', 'Add Saved Place'),
        showTrailing: true,
        trailingColor: this.themePrimary,
        trailingButtonEnabled: this.canSave(),
        trailingLoading: this.isSaving,
        onLeadingClick: (): void => this.onClose(),
        onTrailingClick: (): void => this.handleSave()
      })

      Column({ space: 12 }) {
        TextInput({
          text: this.label,
          placeholder: pickLocalizedText('标签，例如：家、公司', 'Label, such as Home or Work')
        })
          .height(44)
          .fontSize(14)
          .backgroundColor(Color.Transparent)
          .borderRadius(14)
          .systemMaterial(createSavedPlaceMaterial(true))
          .onChange((value: string): void => {
            this.label = value
            this.errorMessage = ''
          })

        Row({ space: 8 }) {
          Search({
            value: this.searchQuery,
            placeholder: pickLocalizedText('搜索地址或地点', 'Search address or place')
          })
            .layoutWeight(1)
            .height(44)
            .backgroundColor(Color.Transparent)
            .borderRadius(22)
            .systemMaterial(createSavedPlaceMaterial(true))
            .onChange((value: string): void => {
              this.searchQuery = value
              this.errorMessage = ''
            })
            .onSubmit((_value: string): void => this.handleSearch())

          Button({ type: ButtonType.Circle, stateEffect: false }) {
            if (this.isSearching) {
              LoadingProgress().width(18).height(18).color(this.themePrimary)
            } else {
              SymbolGlyph($r('sys.symbol.magnifyingglass'))
                .fontSize(18)
                .fontColor([this.themePrimary])
            }
          }
          .width(44)
          .height(44)
          .padding(0)
          .backgroundColor(Color.Transparent)
          .systemMaterial(createSavedPlaceMaterial(true))
          .onClick((): void => this.handleSearch())

          Button({ type: ButtonType.Circle, stateEffect: false }) {
            if (this.isLocating) {
              LoadingProgress().width(18).height(18).color(this.themePrimary)
            } else {
              SymbolGlyph($r('sys.symbol.location_north_up_right'))
                .fontSize(18)
                .fontColor([this.themePrimary])
            }
          }
          .width(44)
          .height(44)
          .padding(0)
          .backgroundColor(Color.Transparent)
          .systemMaterial(createSavedPlaceMaterial(true))
          .onClick((): void => this.handleUseCurrentLocation())
        }
        .width('100%')

        if (this.searchResults.length > 0) {
          Scroll() {
            Row({ space: 8 }) {
              ForEach(this.searchResults, (place: MapPlaceResult) => {
                Column({ space: 4 }) {
                  Text(place.name)
                    .fontSize(13)
                    .fontWeight(FontWeight.Medium)
                    .fontColor($r('app.color.text_primary'))
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                    .width('100%')
                  Text(place.address)
                    .fontSize(11)
                    .fontColor($r('app.color.text_secondary'))
                    .maxLines(2)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                    .width('100%')
                }
                .width(220)
                .height(72)
                .padding(10)
                .borderRadius(14)
                .backgroundColor(Color.Transparent)
                .systemMaterial(createSavedPlaceMaterial(true))
                .alignItems(HorizontalAlign.Start)
                .onClick((): void => this.selectSearchResult(place))
              }, (place: MapPlaceResult) => `${place.siteId}_${place.latitude}_${place.longitude}`)
            }
            .height(88)
            .padding({ left: 4, right: 4, top: 8, bottom: 8 })
          }
          .width('100%')
          .height(88)
          .scrollable(ScrollDirection.Horizontal)
          .scrollBar(BarState.Off)
          .clip(false)
        }

        Stack({ alignContent: Alignment.TopStart }) {
          SavedPlaceMapPicker({
            selectedLatitude: this.selectedLatitude,
            selectedLongitude: this.selectedLongitude,
            centerLatitude: this.centerLatitude,
            centerLongitude: this.centerLongitude,
            onSelect: (latitude: number, longitude: number): void => this.handleMapSelect(latitude, longitude)
          })
            .width('100%')
            .height('100%')

          Text(pickLocalizedText('点击地图选择位置', 'Tap the map to choose a location'))
            .fontSize(11)
            .fontColor($r('app.color.text_primary'))
            .padding({ left: 10, right: 10, top: 6, bottom: 6 })
            .borderRadius(14)
            .backgroundColor(Color.Transparent)
            .systemMaterial(createSavedPlaceMaterial(false))
            .margin({ left: 10, top: 10 })
        }
        .width('100%')
        .layoutWeight(1)
        .constraintSize({ minHeight: 220 })

        if (this.isValidCoordinate(this.selectedLatitude, this.selectedLongitude)) {
          Row({ space: 10 }) {
            SymbolGlyph($r('sys.symbol.map'))
              .fontSize(18)
              .fontColor([this.themePrimary])
            Column({ space: 3 }) {
              Text(this.selectedName !== '' ? this.selectedName : pickLocalizedText('已选择地点', 'Selected place'))
                .fontSize(13)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.text_primary'))
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .width('100%')
              Text(this.isResolving ? pickLocalizedText('正在解析地址…', 'Looking up address…') :
                (this.selectedAddress !== '' ? this.selectedAddress :
                  `${this.selectedLatitude.toFixed(6)}, ${this.selectedLongitude.toFixed(6)}`))
                .fontSize(11)
                .fontColor($r('app.color.text_secondary'))
                .maxLines(2)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .width('100%')
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)
          }
          .width('100%')
          .padding(10)
          .borderRadius(14)
          .backgroundColor(Color.Transparent)
          .systemMaterial(createSavedPlaceMaterial(false))
        }

        if (this.errorMessage !== '') {
          Text(this.errorMessage)
            .fontSize(11)
            .fontColor($r('app.color.status_error'))
            .width('100%')
        }
      }
      .width('100%')
      .layoutWeight(1)
      .padding({ left: 16, right: 16, bottom: 16 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(getAppUiState().themeBackground)
  }
}

@ComponentV2
export struct SavedPlacesCard {
  @Param toolEnabled: boolean = false
  @Event onToggle: (enabled: boolean) => void = (_enabled: boolean): void => {}
  @Local places: SavedPlace[] = []
  @Local showEditorSheet: boolean = false
  @Local editingPlaceJson: string = ''

  private get themePrimary(): string {
    return getAppUiState().themePrimary
  }

  aboutToAppear(): void {
    this.loadPlaces()
  }

  private loadPlaces(): void {
    ServiceRegistry.savedPlaces().loadPlaces()
      .then((places: SavedPlace[]): void => {
        this.places = [...places]
      })
      .catch((error: Error): void => {
        console.error('SavedPlacesCard', `Failed to load places: ${JSON.stringify(error)}`)
      })
  }

  private openAdd(): void {
    this.editingPlaceJson = ''
    this.showEditorSheet = true
  }

  private openEdit(place: SavedPlace): void {
    this.editingPlaceJson = JSON.stringify(place)
    this.showEditorSheet = true
  }

  private handleSaved(_place: SavedPlace): void {
    this.showEditorSheet = false
    if (!this.toolEnabled) {
      this.onToggle(true)
    }
    this.loadPlaces()
    this.showSnack(pickLocalizedText('常用地点已保存', 'Saved place updated'), SnackBarTone.SUCCESS)
  }

  private confirmDelete(place: SavedPlace): void {
    this.getUIContext().showAlertDialog({
      title: pickLocalizedText(`删除“${place.label}”`, `Delete “${place.label}”`),
      message: pickLocalizedText('删除后模型将无法再通过该标签使用此位置。',
        'The model will no longer be able to use this location by its label.'),
      primaryButton: { value: $r('app.string.cancel'), action: (): void => {} },
      secondaryButton: {
        value: $r('app.string.delete'),
        fontColor: Color.Red,
        action: (): void => {
          ServiceRegistry.savedPlaces().deletePlace(place.id)
            .then((): void => {
              this.loadPlaces()
              this.showSnack(pickLocalizedText('常用地点已删除', 'Saved place deleted'), SnackBarTone.SUCCESS)
            })
            .catch((error: Error): void => {
              this.showSnack(error.message, SnackBarTone.ERROR)
            })
        }
      }
    })
  }

  private showSnack(message: string, tone: SnackBarTone): void {
    const options = new SnackBarDisplayOptions()
    options.message = message
    options.duration = 2000
    options.tone = tone
    showSnackBar(this.getUIContext(), options)
  }

  private getPlaceSummary(place: SavedPlace): string {
    if (place.address.trim() !== '') {
      return place.address
    }
    if (place.name.trim() !== '') {
      return place.name
    }
    return `${place.latitude.toFixed(6)}, ${place.longitude.toFixed(6)}`
  }

  @Builder
  private EditorSheetBuilder() {
    SavedPlaceEditorSheetContent({
      placeJson: this.editingPlaceJson,
      onClose: (): void => {
        this.showEditorSheet = false
      },
      onSaved: (place: SavedPlace): void => this.handleSaved(place)
    })
  }

  build() {
    Stack() {
      Column({ space: 12 }) {
        Row({ space: 12 }) {
          ChatFloatingImmersiveButton({
            barWidth: 44,
            barHeight: 44,
            iconResource: $r('sys.symbol.map'),
            iconSize: 20,
            iconColor: [this.themePrimary],
            responsePadding: 0,
            onButtonClick: (): void => this.openAdd()
          }) {
            SymbolGlyph($r('sys.symbol.map'))
              .fontSize(20)
              .fontColor([this.themePrimary])
          }

          Column({ space: 5 }) {
            Text(pickLocalizedText('常用地点', 'Saved Places'))
              .fontSize(17)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.text_primary'))
              .width('100%')
            Text(pickLocalizedText(
              this.places.length > 0 ? `已保存 ${this.places.length} 个地点，模型可按标签使用` : '保存“家”“公司”等地点标签',
              this.places.length > 0 ? `${this.places.length} places available to the model by label` :
                'Save labels such as Home and Work'
            ))
              .fontSize(12)
              .fontColor($r('app.color.text_secondary'))
              .width('100%')
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)

          Toggle({ type: ToggleType.Switch, isOn: this.toolEnabled })
            .selectedColor(this.themePrimary)
            .systemMaterial(new uiMaterial.Material())
            .switchPointColor(Color.White)
            .onChange((value: boolean): void => this.onToggle(value))
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)

        Text(pickLocalizedText(
          '地点仅保存在本机。开启后，模型可读取标签、地址和坐标，并将标签直接用于地图路线或花瓣导航。',
          'Places stay on this device. When enabled, the model can read their labels, addresses, and coordinates and use labels directly in map routes or Petal Navigation.'
        ))
          .fontSize(12)
          .lineHeight(18)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')

        if (this.places.length > 0) {
          Column() {
            ForEach(this.places, (place: SavedPlace, index: number) => {
              Row({ space: 10 }) {
                Text(place.label)
                  .fontSize(12)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(this.themePrimary)
                  .padding({ left: 9, right: 9, top: 5, bottom: 5 })
                  .borderRadius(12)
                  .backgroundColor(getAppUiState().themePrimaryLight)

                Text(this.getPlaceSummary(place))
                  .fontSize(12)
                  .fontColor($r('app.color.text_secondary'))
                  .layoutWeight(1)
                  .maxLines(2)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })

                Button({ type: ButtonType.Circle, stateEffect: false }) {
                  SymbolGlyph($r('sys.symbol.square_and_pencil'))
                    .fontSize(15)
                    .fontColor([this.themePrimary])
                }
                .width(34)
                .height(34)
                .padding(0)
                .backgroundColor(Color.Transparent)
                .systemMaterial(createSavedPlaceMaterial(true))
                .onClick((): void => this.openEdit(place))

                Button({ type: ButtonType.Circle, stateEffect: false }) {
                  SymbolGlyph($r('sys.symbol.trash'))
                    .fontSize(15)
                    .fontColor([$r('app.color.status_error')])
                }
                .width(34)
                .height(34)
                .padding(0)
                .backgroundColor(Color.Transparent)
                .systemMaterial(createSavedPlaceMaterial(true))
                .onClick((): void => this.confirmDelete(place))
              }
              .width('100%')
              .padding({ top: 9, bottom: 9 })
              .alignItems(VerticalAlign.Center)

              if (index < this.places.length - 1) {
                Divider()
                  .strokeWidth(0.5)
                  .color($r('app.color.divider'))
              }
            }, (place: SavedPlace) => place.id)
          }
          .width('100%')
        }

        Button({ type: ButtonType.Capsule, stateEffect: false }) {
          Row({ space: 6 }) {
            SymbolGlyph($r('sys.symbol.plus'))
              .fontSize(14)
              .fontColor([this.themePrimary])
            Text(pickLocalizedText('添加地点', 'Add Place'))
              .fontSize(12)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.themePrimary)
          }
        }
        .width('100%')
        .height(38)
        .backgroundColor(Color.Transparent)
        .systemMaterial(createSavedPlaceMaterial(true))
        .onClick((): void => this.openAdd())
      }
      .width('100%')
      .padding(16)
      .borderRadius(16)
      .backgroundColor(Color.Transparent)
      .border({ width: 0.5, color: getAppUiState().themePrimaryLight })
      .systemMaterial(createSavedPlaceMaterial(false))

      Column()
        .width(0)
        .height(0)
        .bindSheet($$this.showEditorSheet, this.EditorSheetBuilder(), {
          height: SheetSize.LARGE,
          detents: [SheetSize.LARGE],
          showClose: false,
          dragBar: true,
          blurStyle: BlurStyle.Regular,
          onDisappear: (): void => {
            this.showEditorSheet = false
          }
        })
    }
    .width('100%')
  }
}
