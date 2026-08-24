import { getAppUiState } from '../../state/AppUiState'
import {
  getMapKitService,
  MapSearchRouteResult,
  MapVisualizationData
} from '../../services/MapKitService'
import { pickLocalizedText } from '../../utils/LocalizedTextUtils'
import { MapVisualizationView } from './MapVisualizationView'

@ComponentV2
export struct MapResultCard {
  @Param toolResultContent: string = ''
  @Event onOpenMap: (visualizationJson: string) => void = (_visualizationJson: string): void => {}
  @Local visualizationJson: string = ''
  private result: MapSearchRouteResult = new MapSearchRouteResult()
  private visualization: MapVisualizationData = new MapVisualizationData()

  private get themePrimary(): string {
    return getAppUiState().themePrimary
  }

  private get themePrimaryLight(): string {
    return getAppUiState().themePrimaryLight
  }

  private get cardBackground(): string {
    return getAppUiState().isDarkMode ? '#202127' : '#FFFFFF'
  }

  aboutToAppear(): void {
    try {
      this.result = JSON.parse(this.toolResultContent) as MapSearchRouteResult
    } catch (_error) {
      this.result = new MapSearchRouteResult()
    }
    this.visualizationJson = getMapKitService().getVisualizationJson(this.toolResultContent)
    if (this.visualizationJson !== '') {
      try {
        this.visualization = JSON.parse(this.visualizationJson) as MapVisualizationData
      } catch (_error) {
        this.visualization = new MapVisualizationData()
      }
    }
  }

  private getTitle(): string {
    if (this.visualization.destination !== null && this.visualization.destination.name.trim() !== '') {
      return this.visualization.destination.name
    }
    if ((this.result.query || '').trim() !== '') {
      return this.result.query
    }
    return pickLocalizedText('地图结果', 'Map result')
  }

  private formatDistance(value: number): string {
    if (value <= 0) {
      return ''
    }
    if (value >= 1000) {
      return `${(value / 1000).toFixed(1)} km`
    }
    return `${Math.round(value)} m`
  }

  private formatDuration(value: number): string {
    if (value <= 0) {
      return ''
    }
    const minutes = Math.max(1, Math.round(value / 60))
    if (minutes >= 60) {
      const hours = Math.floor(minutes / 60)
      const rest = minutes % 60
      return rest > 0 ? `${hours} h ${rest} min` : `${hours} h`
    }
    return `${minutes} min`
  }

  private getRouteMeta(): string {
    const parts: string[] = []
    const distance = this.formatDistance(this.visualization.distanceMeters)
    const duration = this.formatDuration(this.visualization.durationSeconds)
    if (distance !== '') {
      parts.push(distance)
    }
    if (duration !== '') {
      parts.push(duration)
    }
    if (this.visualization.showCurrentLocation) {
      parts.push(pickLocalizedText('含实时位置', 'Live location'))
    }
    return parts.join(' · ')
  }

  build() {
    Column() {
      Stack({ alignContent: Alignment.TopEnd }) {
        MapVisualizationView({
          visualizationJson: this.visualizationJson,
          compact: true,
          followMode: false
        })
          .width('100%')
          .height(184)

        if (this.visualization.showCurrentLocation) {
          Row({ space: 4 }) {
            SymbolGlyph($r('sys.symbol.location_north_up_right'))
              .fontSize(11)
              .fontColor([this.themePrimary])

            Text(pickLocalizedText('当前位置', 'Current location'))
              .fontSize(10)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.themePrimary)
          }
          .padding({ left: 8, right: 8, top: 5, bottom: 5 })
          .borderRadius(12)
          .backgroundColor(this.cardBackground)
          .margin({ top: 10, right: 10 })
        }
      }
      .width('100%')
      .height(184)
      .clip(true)

      Row() {
        Column({ space: 3 }) {
          Text(this.getTitle())
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')

          if (this.getRouteMeta() !== '') {
            Text(this.getRouteMeta())
              .fontSize(11)
              .fontColor($r('app.color.text_secondary'))
              .maxLines(1)
              .width('100%')
          } else if (this.visualization.summary.trim() !== '') {
            Text(this.visualization.summary)
              .fontSize(11)
              .fontColor($r('app.color.text_secondary'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
          }
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        Row({ space: 4 }) {
          Text(pickLocalizedText('查看地图', 'Open map'))
            .fontSize(12)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.themePrimary)

          SymbolGlyph($r('sys.symbol.chevron_right'))
            .fontSize(12)
            .fontColor([this.themePrimary])
        }
        .margin({ left: 12 })
        .onClick((): void => {
          if (this.visualizationJson !== '') {
            this.onOpenMap(this.visualizationJson)
          }
        })
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 10, bottom: 10 })
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .borderRadius(14)
    .clip(true)
    .backgroundColor(this.cardBackground)
    .border({ width: 0.5, color: this.themePrimaryLight })
  }
}
