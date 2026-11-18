import { ModelInfo, ModelProvider } from '../models/ChatModels'
import { PickerModelGroup, buildPickerModelGroups } from './ProviderDetailShared'

export enum ModelRowGroupPosition {
  SINGLE = 'single',
  FIRST = 'first',
  MIDDLE = 'middle',
  LAST = 'last'
}

export interface ModelRowRadius {
  topLeft: number
  topRight: number
  bottomLeft: number
  bottomRight: number
}

export enum ModelSelectorRowType {
  PROVIDER_HEADER = 'provider_header',
  MODEL_ITEM = 'model_item'
}

export interface ModelSelectorProviderHeaderRow {
  type: ModelSelectorRowType.PROVIDER_HEADER
  key: string
  provider: ModelProvider
}

export interface ModelSelectorModelRow {
  type: ModelSelectorRowType.MODEL_ITEM
  key: string
  provider: ModelProvider
  model: ModelInfo
  isFavorite: boolean
  groupPosition: ModelRowGroupPosition
}

export type ModelSelectorRow = ModelSelectorProviderHeaderRow | ModelSelectorModelRow

export interface ModelSelectorProviderGroup {
  provider: ModelProvider
  modelRows: ModelSelectorModelRow[]
}

export interface ModelSelectorBuildResult {
  rows: ModelSelectorRow[]
  groups: ModelSelectorProviderGroup[]
  enabledModelCount: number
  favoriteEnabledCount: number
  matchedModelCount: number
  hasEnabledModels: boolean
  hasFavoriteModels: boolean
  hasFilteredModels: boolean
}

export function buildModelSelectorRows(
  providers: ModelProvider[],
  searchKeywords: string,
  favoriteKeys: Set<string>,
  showFavoritesOnly: boolean,
  includeModelIdInSearch: boolean
): ModelSelectorBuildResult {
  const rows: ModelSelectorRow[] = []
  const groups: ModelSelectorProviderGroup[] = []
  const trimmedKeyword = searchKeywords.trim().toLowerCase()
  let enabledModelCount = 0
  let favoriteEnabledCount = 0
  let matchedModelCount = 0

  for (let i = 0; i < providers.length; i++) {
    const provider = providers[i]
    const modelRows: ModelSelectorModelRow[] = []

    for (let j = 0; j < provider.models.length; j++) {
      const model = provider.models[j]
      if (!model.isEnabled) {
        continue
      }

      enabledModelCount++
      const isFavorite = favoriteKeys.has(`${provider.id}::${model.id}`)
      if (isFavorite) {
        favoriteEnabledCount++
      }

      if (trimmedKeyword !== '') {
        const matchesName = model.name.toLowerCase().includes(trimmedKeyword)
        const matchesId = includeModelIdInSearch && model.id.toLowerCase().includes(trimmedKeyword)
        if (!matchesName && !matchesId) {
          continue
        }
      }

      if (showFavoritesOnly && !isFavorite) {
        continue
      }

      if (modelRows.length === 0) {
        rows.push({
          type: ModelSelectorRowType.PROVIDER_HEADER,
          key: `${provider.id}::header`,
          provider: provider
        } as ModelSelectorProviderHeaderRow)
      }
      const row: ModelSelectorModelRow = {
        type: ModelSelectorRowType.MODEL_ITEM,
        key: `${provider.id}::model::${model.id}`,
        provider: provider,
        model: model,
        isFavorite: isFavorite,
        groupPosition: ModelRowGroupPosition.MIDDLE
      }
      modelRows.push(row)
      rows.push(row)
    }
    if (modelRows.length > 0) {
      const lastIndex = modelRows.length - 1
      modelRows[0].groupPosition = resolveGroupPosition(0, modelRows.length)
      modelRows[lastIndex].groupPosition = resolveGroupPosition(lastIndex, modelRows.length)
      groups.push({ provider: provider, modelRows: modelRows })
      matchedModelCount += modelRows.length
    }
  }

  return {
    rows: rows,
    groups: groups,
    enabledModelCount: enabledModelCount,
    favoriteEnabledCount: favoriteEnabledCount,
    matchedModelCount: matchedModelCount,
    hasEnabledModels: enabledModelCount > 0,
    hasFavoriteModels: favoriteEnabledCount > 0,
    hasFilteredModels: matchedModelCount > 0
  } as ModelSelectorBuildResult
}

export interface ModelPickerModelRow {
  groupName: string
  modelId: string
  isExisting: boolean
  groupPosition: ModelRowGroupPosition
}

export interface ModelPickerBuildResult {
  filteredModelIds: string[]
  visibleModelIds: string[]
  groups: PickerModelGroup[]
}

export function buildModelPickerRows(
  availableModels: string[],
  selectedModelIds: Set<string>,
  searchKeywords: string,
  showSelectedOnly: boolean
): ModelPickerBuildResult {
  const filteredModelIds = filterAvailableModels(availableModels, searchKeywords)
  const visibleModelIds = showSelectedOnly
    ? collectSelectedModelIds(filteredModelIds, selectedModelIds)
    : filteredModelIds
  const groups = buildPickerModelGroups(visibleModelIds)

  return {
    filteredModelIds: filteredModelIds,
    visibleModelIds: visibleModelIds,
    groups: groups
  } as ModelPickerBuildResult
}

function filterAvailableModels(availableModels: string[], searchKeywords: string): string[] {
  const trimmedKeyword = searchKeywords.trim().toLowerCase()
  if (trimmedKeyword === '') {
    return availableModels.slice()
  }

  const result: string[] = []
  for (let i = 0; i < availableModels.length; i++) {
    const modelId = availableModels[i]
    if (modelId.toLowerCase().includes(trimmedKeyword)) {
      result.push(modelId)
    }
  }
  return result
}

function collectSelectedModelIds(modelIds: string[], selectedModelIds: Set<string>): string[] {
  const selected: string[] = []
  for (let i = 0; i < modelIds.length; i++) {
    const modelId = modelIds[i]
    if (selectedModelIds.has(modelId)) {
      selected.push(modelId)
    }
  }
  return selected
}

export function resolveGroupPosition(index: number, totalCount: number): ModelRowGroupPosition {
  if (totalCount <= 1) {
    return ModelRowGroupPosition.SINGLE
  }
  if (index === 0) {
    return ModelRowGroupPosition.FIRST
  }
  if (index === totalCount - 1) {
    return ModelRowGroupPosition.LAST
  }
  return ModelRowGroupPosition.MIDDLE
}
