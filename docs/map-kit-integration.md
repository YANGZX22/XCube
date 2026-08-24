# HarmonyOS Map Kit 调研与 AI 工具集成

## 结论

XCube 可以直接通过 `@kit.MapKit` 接入地点搜索、附近搜索、驾车/步行/骑行路线规划，并通过花瓣地图完成路线展示或导航。本项目采用两个 AI 工具分离只读查询与外部动作：

- `map_search_route`：搜索和推荐 POI，或在应用内计算路线；权限级别为 `READ`。
- `open_map_route`：打开花瓣地图路线页或发起导航；权限级别为 `WRITE`，执行前复用现有工具审批界面。

这种划分允许 AI 在不打断用户的情况下比较候选地点，同时避免“推荐地点”被误解为立即切换应用或开始导航。

## Map Kit 能力与本项目 API 映射

| 场景 | Map Kit API | 工具动作 | 说明 |
| --- | --- | --- | --- |
| 关键词搜索 | `site.searchByText` | `search_places` | 返回名称、地址、坐标、距离、评分等公开 POI 信息 |
| 周边推荐 | `site.nearbySearch` | `search_places` + `nearby=true` | 可使用当前位置或显式中心点和半径 |
| POI 详情 | `site.searchById` | `include_details=true` | 最多补充前 5 个候选，避免无必要的额外请求 |
| 驾车路线 | `navi.getDrivingRoutes` | `plan_route` | 可返回多条备选和实时交通耗时 |
| 步行路线 | `navi.getWalkingRoutes` | `plan_route` | 返回道路级摘要 |
| 骑行路线 | `navi.getCyclingRoutes` | `plan_route` | 返回道路级摘要 |
| 聊天内地图 | `MapComponent` + `addMarker` + `addPolyline` | 工具结果卡片 | 直接展示当前位置、候选地点、起终点和首选路线 |
| 实时跟随 | `setMyLocationEnabled` + `FOLLOW_ROTATE` | 全屏地图页 | 持续更新精确位置、设备朝向和相机中心 |
| 路线页 | `petalMaps.openMapRoutePlan` | `route_plan` | 打开花瓣地图，由用户继续操作 |
| 导航 | `petalMaps.openMapNavi` | `navigation` | 仅在用户明确要求导航时调用 |
| 坐标纠偏 | `map.rectifyCoordinate` | 两个工具内部 | 根据服务区域在 WGS84/GCJ02 之间自动处理 |

`@kit.MapKit` 属于系统 SDK Kit，本项目 API 26 已满足使用条件，不需要增加 OHPM 依赖。

## 数据流与隐私边界

```text
用户自然语言
  -> 模型选择地图工具
  -> ToolExecutionService
      -> map_search_route (READ)
          -> 可选的一次性精确定位
          -> Map Kit POI/路线服务
          -> 结构化候选/路线摘要返回模型
          -> 本地 MapComponent 卡片（地点、起终点、路线折线）
              -> 全屏 MapRoutePage
              -> 实时精确位置、朝向和地图跟随
      -> open_map_route (WRITE)
          -> 用户审批
          -> 花瓣地图路线页/导航
```

只有用户表达“附近”“从这里出发”等位置相关意图时，工具描述才要求模型设置 `use_current_location=true`。应用同时声明并动态申请 `ohos.permission.LOCATION` 与 `ohos.permission.APPROXIMATELY_LOCATION`，以获得米级精确位置；授权只在真正需要当前位置时触发。

当前位置会在设备端转换后用于 Map Kit 查询，但不会作为原始坐标写回给模型；返回给模型的是公开 POI 坐标、候选详情和路线摘要，以支持比较候选与后续打开准确地点。精确起点和路线几何通过随机 `visualToken` 关联，只写入应用沙箱的 `filesDir/map_visualizations`，最多保留 128 份，避免将精确位置放入模型上下文。Map Kit 的个人数据处理说明应同步纳入应用隐私政策。

聊天地图卡片使用 `TRACK_ROTATE` 显示实时蓝点与朝向，但不自动移动相机；全屏 `MapRoutePage` 默认使用 `FOLLOW_ROTATE`，用户也可以切换“路线概览”查看完整折线。页面退出时会关闭该 `MapComponent` 的“我的位置”图层。

## 已集成的工程位置

- `entry/src/main/ets/services/MapKitService.ets`：Map Kit、Location Kit 和花瓣地图调用，参数校验、坐标纠偏、结果脱敏和错误转换。
- `entry/src/main/ets/components/map/MapVisualizationView.ets`：`MapComponent`、候选/起终点 Marker、路线 Polyline、实时位置和朝向跟随。
- `entry/src/main/ets/components/map/MapResultCard.ets`：聊天消息内的内嵌地图结果卡片。
- `entry/src/main/ets/pages/MapRoutePage.ets`：全屏地图、跟随位置和路线概览交互。
- `entry/src/main/ets/components/MessageBubble.ets`、`components/chat/ChatMessageList*.ets`：识别地图工具结果并接入聊天渲染与页面跳转。
- `entry/src/main/ets/config/MapTool.ets`：两个模型可调用工具的 JSON Schema、提示和权限级别。
- `entry/src/main/ets/config/BuiltinTools.ets`：内置工具注册与目录。
- `entry/src/main/ets/entryability/EntryAbility.ets`、`services/ServiceRegistry.ets`：服务生命周期初始化。
- `entry/src/main/module.json5`：精确位置所需的 `LOCATION`、`APPROXIMATELY_LOCATION`，以及旋转跟随所需的 `ACCELEROMETER` 权限声明。
- `entry/src/main/ets/utils/ToolDisplayTextUtils.ets`、`components/chat/ChatToolPickerSheetContent.ets`：工具面板文案和图标。

## 上线前必须完成的控制台配置

当前版本不再需要配置公钥指纹或 Client ID，但仍必须为应用开通 Map Kit 能力：

1. 在 DevEco Studio 打开 `File > Project Structure > Signing Configs`。
2. 进入 `Enable open capabilities`，启用 `Map Kit` 并应用；也可在 AppGallery Connect 的“开放能力管理”中启用。
3. 若当前调试 Profile 在启用 Map Kit 前生成，重新申请/下载调试证书、设备和 Profile，再更新签名配置。
4. 使用具有 HMS Core/花瓣地图能力的真机验证地点搜索、路线规划与应用拉起。

能力未开通通常返回 `1002600004`，签名或 Profile 不匹配通常返回 `1002600003`。服务层已将这两个错误转换为可操作的中文提示。

## AI 调用示例

推荐附近咖啡店：

```json
{
  "action": "search_places",
  "query": "安静的咖啡店",
  "nearby": true,
  "use_current_location": true,
  "radius_meters": 3000,
  "limit": 5,
  "include_details": true
}
```

规划从当前位置到候选目的地的步行路线：

```json
{
  "action": "plan_route",
  "destination": "候选地点完整名称和地址",
  "destination_location": {
    "latitude": 31.2304,
    "longitude": 121.4737
  },
  "use_current_location": true,
  "travel_mode": "walking"
}
```

经用户确认后打开导航：

```json
{
  "action": "navigation",
  "destination": "候选地点名称",
  "destination_site_id": "map_search_route 返回的 siteId",
  "destination_location": {
    "latitude": 31.2304,
    "longitude": 121.4737
  },
  "travel_mode": "driving"
}
```

## 限制与后续扩展

- 当前应用内页面是“路线展示与位置跟随”，不是完整 Turn-by-Turn 导航引擎。偏航重算、逐路口指令、车道级引导、路口放大图和导航语音仍交给花瓣地图的 `openMapNavi`。
- 公共交通暂通过花瓣地图路线页处理，工具内路线计算只开放驾车、步行和骑行。
- 大陆、香港和澳门地图使用 GCJ02，台湾和海外使用 WGS84。服务层通过 `map.rectifyCoordinate` 统一处理调用方传入坐标，仍应在外部数据进入时明确 `coordinate_type`。

## 官方资料

- [Map Kit 简介](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/map-introduction)
- [开发准备](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/map-config-agc)
- [位置搜索](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/map-location-services)
- [路径规划](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/map-navi)
- [MapComponent](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/map-mapcomponent)
- [地图控件与交互](https://developer.huawei.com/consumer/cn/doc/doccenter-capabilities/map-controls-and-interaction)
- [在地图上绘制线](https://developer.huawei.com/consumer/cn/doc/doccenter-capabilities/map-polyline)
- [拉起花瓣地图](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/map-petalmaps)
- [个人数据处理说明](https://developer.huawei.com/consumer/cn/doc/doccenter-capabilities/map-personal-privacy)
