import { MapVisualizationView } from '../components/map/MapVisualizationView'
import { MapVisualizationData } from '../services/MapKitService'
import { getAppUiState } from '../state/AppUiState'
import { pickLocalizedText } from '../utils/LocalizedTextUtils'
import { uiMaterial } from '@kit.ArkUI'

export interface MapRoutePageParams {
  visualizationJson?: string
}

let mapRoutePagePathStack: NavPathStack | null = null

function resolveMapRoutePageParams(param: Object): MapRoutePageParams {
  return param as MapRoutePageParams
}

function popMapRoutePage(): boolean {
  if (mapRoutePagePathStack === null || mapRoutePagePathStack.size() <= 0) {
    return false
  }
  mapRoutePagePathStack.pop()
  return true
}

@ComponentV2
struct MapRoutePageContent {
  @Param visualizationJson: string = ''
  @Event onClose: () => void = (): void => {}
  @Local isFollowing: boolean = false
  @Local followRequestId: number = 0
  @Local overviewRequestId: number = 0
  @Local topPanelHeightVp: number = 164
  private data: MapVisualizationData = new MapVisualizationData()

  private get themePrimary(): string {
    return getAppUiState().themePrimary
  }

  private get topInsetVp(): number {
    return this.px2vp(getAppUiState().topAvoidHeight)
  }

  private get bottomInsetVp(): number {
    return this.px2vp(getAppUiState().bottomAvoidHeight)
  }

  private get mapControlsTopInsetVp(): number {
    return this.topInsetVp + 8 + this.topPanelHeightVp + 12
  }

  private get mapControlsBottomInsetVp(): number {
    return this.bottomInsetVp + 12
  }

  private getTopPanelMaterial(): uiMaterial.Material {
    return new uiMaterial.ImmersiveMaterial({
      style: uiMaterial.ImmersiveStyle.REGULAR,
      materialColor: Color.Transparent,
      applyShadow: true,
      interactive: true,
      lightEffect: { color: undefined }
    })
  }

  private getButtonMaterial(): uiMaterial.Material {
    return new uiMaterial.ImmersiveMaterial({
      style: uiMaterial.ImmersiveStyle.REGULAR,
      materialColor: Color.Transparent,
      applyShadow: false,
      interactive: true,
      lightEffect: { color: undefined }
    })
  }

  aboutToAppear(): void {
    try {
      this.data = JSON.parse(this.visualizationJson) as MapVisualizationData
      this.isFollowing = this.data.showCurrentLocation === true
    } catch (_error) {
      this.data = new MapVisualizationData()
      this.isFollowing = false
    }
  }

  private px2vp(value: number): number {
    const density = this.getUIContext().getHostContext()?.resourceManager.getDeviceCapabilitySync().screenDensity ?? 3
    return value / density * 160
  }

  private getTitle(): string {
    if (this.data.destination !== null && (this.data.destination.name || '').trim() !== '') {
      return this.data.destination.name
    }
    if ((this.data.query || '').trim() !== '') {
      return this.data.query
    }
    return pickLocalizedText('地图', 'Map')
  }

  private formatDistance(value: number): string {
    if (value <= 0) {
      return ''
    }
    return value >= 1000 ? `${(value / 1000).toFixed(1)} km` : `${Math.round(value)} m`
  }

  private formatDuration(value: number): string {
    if (value <= 0) {
      return ''
    }
    const minutes = Math.max(1, Math.round(value / 60))
    if (minutes < 60) {
      return `${minutes} min`
    }
    const hours = Math.floor(minutes / 60)
    const rest = minutes % 60
    return rest > 0 ? `${hours} h ${rest} min` : `${hours} h`
  }

  private getRouteMeta(): string {
    const values: string[] = []
    const distance = this.formatDistance(this.data.distanceMeters || 0)
    const duration = this.formatDuration(this.data.durationSeconds || 0)
    if (distance !== '') {
      values.push(distance)
    }
    if (duration !== '') {
      values.push(duration)
    }
    return values.join(' · ')
  }

  private handleTopPanelAreaChange(area: Area): void {
    const height = Number(area.height)
    if (!Number.isFinite(height) || height <= 0 || Math.abs(height - this.topPanelHeightVp) < 0.5) {
      return
    }
    this.topPanelHeightVp = height
  }

  build() {
    Stack({ alignContent: Alignment.Top }) {
      MapVisualizationView({
        visualizationJson: this.visualizationJson,
        compact: false,
        followMode: this.isFollowing,
        followRequestId: this.followRequestId,
        overviewRequestId: this.overviewRequestId,
        controlsTopInsetVp: this.mapControlsTopInsetVp,
        controlsBottomInsetVp: this.mapControlsBottomInsetVp,
        onMapGesture: (): void => {
          this.isFollowing = false
        }
      })
        .width('100%')
        .height('100%')

      Column({ space: 8 }) {
        Row({ space: 6 }) {
          Button({ type: ButtonType.Circle, stateEffect: true }) {
            SymbolGlyph($r('sys.symbol.chevron_left'))
              .fontSize(20)
              .fontColor([$r('app.color.text_primary')])
          }
          .width(44)
          .height(44)
          .padding(0)
          .backgroundColor(Color.Transparent)
          .border({ width: 0, color: Color.Transparent })
          .systemMaterial(this.getButtonMaterial())
          .onClick((): void => {
            this.onClose()
          })

          Column({ space: 2 }) {
            Text(pickLocalizedText('搜索结果', 'Search results'))
              .fontSize(15)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_primary'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')

            Text(this.isFollowing
              ? pickLocalizedText('正在跟随实时位置与朝向', 'Following live location and heading')
              : pickLocalizedText('结果概览', 'Result overview'))
              .fontSize(11)
              .fontColor($r('app.color.text_secondary'))
              .maxLines(1)
              .width('100%')
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)
          .padding({ right: 12 })
        }
        .width('100%')
        .height(44)
        .alignItems(VerticalAlign.Center)

        Column({ space: 3 }) {
          if (this.getRouteMeta() !== '') {
            Text(this.getRouteMeta())
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_primary'))
              .width('100%')
          }

          Text((this.data.summary || '').trim() !== '' ? this.data.summary : this.getTitle())
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)

        Row({ space: 10 }) {
          if (this.data.showCurrentLocation) {
            Button() {
              Row({ space: 6 }) {
                SymbolGlyph($r('sys.symbol.navigation'))
                  .fontSize(16)
                  .fontColor([this.isFollowing ? this.themePrimary : $r('app.color.text_secondary')])
                Text(pickLocalizedText('回到当前位置', 'My location'))
                  .fontSize(13)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(this.isFollowing ? this.themePrimary : $r('app.color.text_secondary'))
              }
            }
            .height(40)
            .layoutWeight(1)
            .borderRadius(20)
            .backgroundColor(Color.Transparent)
            .border({ width: 0, color: Color.Transparent })
            .systemMaterial(this.getButtonMaterial())
            .onClick((): void => {
              this.isFollowing = true
              this.followRequestId += 1
            })
          }

          Button() {
            Row({ space: 6 }) {
              SymbolGlyph($r('sys.symbol.map'))
                .fontSize(16)
                .fontColor([!this.isFollowing ? this.themePrimary : $r('app.color.text_secondary')])
              Text(pickLocalizedText('结果概览', 'Result overview'))
                .fontSize(13)
                .fontWeight(FontWeight.Medium)
                .fontColor(!this.isFollowing ? this.themePrimary : $r('app.color.text_secondary'))
            }
          }
          .height(40)
          .layoutWeight(1)
          .borderRadius(20)
          .backgroundColor(Color.Transparent)
          .border({ width: 0, color: Color.Transparent })
          .systemMaterial(this.getButtonMaterial())
          .onClick((): void => {
            this.isFollowing = false
            this.overviewRequestId += 1
          })
        }
        .width('100%')
      }
      .width('calc(100% - 24vp)')
      .padding(12)
      .borderRadius(24)
      .backgroundColor(Color.Transparent)
      .systemMaterial(this.getTopPanelMaterial())
      .margin({ top: this.topInsetVp + 8 })
      .hitTestBehavior(HitTestMode.Default)
      .onAreaChange((_oldArea: Area, newArea: Area): void => {
        this.handleTopPanelAreaChange(newArea)
      })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(getAppUiState().themeBackground)
  }
}

@Builder
export function MapRoutePageBuilder(name: string, param: Object) {
  NavDestination() {
    MapRoutePageContent({
      visualizationJson: resolveMapRoutePageParams(param).visualizationJson ?? '',
      onClose: (): void => {
        popMapRoutePage()
      }
    })
  }
  .hideTitleBar(true)
  .hideBackButton(true)
  .onReady((context: NavDestinationContext): void => {
    mapRoutePagePathStack = context.pathStack
  })
  .onBackPressed((): boolean => popMapRoutePage())
}
