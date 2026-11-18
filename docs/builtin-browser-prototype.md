# 浏览器（In-APP Browser）原型

当前实现：每个对话拥有一个独立的 ArkWeb 页面，当前对话的用户与主智能体共用该页面。聊天输入区的“工作区”后新增“浏览器”入口；工具选择中启用 **浏览器 / In-APP Browser** 后，支持视觉输入的模型可以打开网页、截图、点击、按位置滚动、输入，以及自主切换手机版/电脑版。各入口统一使用 `worldclock` 图标；有打开的页面或记忆网址时，工具栏按钮显示主题色，只有模型使用浏览器期间才显示双边边缘流光，用户接管、暂停或请求结束后停止流光。

按钮和网页共用 `BrowserEdgeFlowLight` 透明叠加层，使用不带背景蒙层的双边边缘 shader，显式指定青色和粉色。按活动状态创建，挂载后主动播放、销毁时停止，不依赖按钮按压。按钮发光层位于文字下方，沿胶囊内侧裁剪，不绘制实色底板，保留底层沉浸光感材质。

浏览器网页区域铺到窗口底部，不再额外添加底部避让留白。网页容器与流光共用 32 vp 圆角，四角保持一致。模型操控且浏览器可见时，网页周边显示中央透明的原生双边流光；保留柔和光晕与青粉配色，通过连续透明度渐变让向内扩散在 24 vp 内自然消退。渐隐遮罩使用完整的内缩圆角轮廓，圆弧与直边连续相切，不再拼接四边和四角的独立渐变块，也不裁成细线。静态渐隐遮罩只在尺寸变化时重绘，循环动画为 6 秒。工具栏按钮沿用原有范围与 4 秒循环。用户接管、暂停、任务结束或返回聊天后停止。流光独立于 Web 节点，不占布局空间、不接收触摸，也不进入发送给模型的网页截图。

## 使用流程

1. 选择支持工具调用和图片输入的模型，在工具面板选中“浏览器”（英文为 In-APP Browser）。
2. 让模型打开指定网页。首次打开或当前为空白页时，`open` 先请求确认。批准后打开当前对话的页面，并把网页视口截图作为原生图片输入交给模型；其他对话在后台打开的页面不会覆盖当前界面。
3. 模型按截图调用 `click`、`scroll` 或 `type`，每次操作后获得新截图。`scroll` 的 `x/y` 指定目标滚动区域内的起点，可命中内层容器、弹窗、侧栏或 iframe；省略时在截图中心滑动。`type` 前需要点击输入框，`focused_editable` 检查网页实际焦点，不要求系统键盘弹出。`submit=true` 发送原生 Enter；只按回车时使用 `text=""`，也可作用于已聚焦的按钮。提交结果必须查看新截图，Enter 无效时可点击页面提交按钮；文字已输入就不再重复输入，派发异常时先确认是否已生效。
4. **只有点击浏览器顶部“接管页面”按钮，才进入用户控制。** 模型注入事件、网页事件、输入框焦点和打开浏览器入口均不会自动接管。接管后启用网页操作、地址栏、前进/后退/刷新和手机版/电脑版按钮；用户使用系统输入法，模型优先使用 ArkWeb 的键盘控制器，没有键盘回调时使用固定的焦点输入脚本。
5. 用户点击“交给模型”后，`wait_for_user` 返回新截图；旧操作不会自动重放。等待用户、取消等暂停状态提供“继续模型”按钮，任务结束显示“就绪”，不会显示为用户接管。等待最多两分钟，可通过聊天的停止按钮取消。等待超时后模型应结束等待并告知用户，后续可继续发消息。
6. 顶部操作统一放在右上角，按“红色关闭—黄色隐藏—主题色接管”排列。按钮高度为 32 vp，图标统一为 19 vp；沿用聊天发送按钮的薄沉浸光感材质和约 75% 透明底色，图标与文字保持不透明。材质直接作用于接收触摸的原生按钮，开启按压形变和光照；接管按钮按中英文文案测量宽度。黄色隐藏按钮和系统返回键只返回聊天，模型继续操作后台浏览器；再次点“浏览器”可回到同一页面。切换到其他应用也不会主动暂停模型控制。红色关闭按钮销毁当前标签；删除所属会话也会销毁页面。接管后主题色按钮显示“交给模型”。
7. 用户主动接管后，隐藏浏览器或切换应用不会把控制权交回模型，仍需用户点击“交给模型”。
8. 模型可在 `open` 指定 `page_mode`，或用 `set_page_mode` 切换当前页面。切换模式重新加载当前页面，可能丢失未提交输入；同一模式不会重复刷新。新标签默认手机版，同一标签内导航沿用模式。网站是否提供对应版式取决于网站自身。
9. 长文档可先用 `read_page` 分页读取已渲染的正文，再用 `find` 查找章节标题或关键词并定位到页面。正文读取不滚动页面，不产生新截图；需要点击时仍使用有效截图。不要根据章节名称猜测网站的锚点 ID。
10. 切换对话会隐藏上一对话的页面，保留其内容和控制状态；后台模型可继续操作自己的页面。再次点击该对话的“浏览器”回到原页面。各对话的截图编号、前进后退和接管状态互不影响。
11. 工具设置中点击浏览器的“配置 >”，在自适应高度的沉浸光感弹窗内设置“保存 Cookie”，默认关闭。Cookie 图标、说明和开关直接显示在弹窗上，不添加行底板。开启后所有对话使用 ArkWeb 的共享 Cookie 存储，可保留站点登录状态；关闭时切回隐私模式并清除已保存的 Cookie。切换开关会重建并重新加载已有页面。Cookie 由 ArkWeb 管理，不复制到应用偏好或工具结果。登录是否持续仍受网站过期策略影响。
12. 应用记忆未关闭页面的网址及手机版/电脑版模式，退出后再次打开该对话的浏览器时加载；不会恢复表单输入、滚动位置或历史记录。隐藏保留记忆，红色关闭和删除对话清除对应网址。重启应用时不会一次性加载所有记忆的页面。
13. 配置弹窗的“清空浏览器数据”会关闭所有对话的网页，清空记忆网址、网页缓存、站点存储和普通/隐私 Cookie；保留“保存 Cookie”的开关选择。弹窗说明登录状态与未提交内容会丢失。清空期间拒绝新浏览器操作，旧截图和页面回调失效，完成后按钮恢复默认颜色；部分清理失败会提示重试。

## 工具协议

工具名：`builtin_browser`。参数为扁平 JSON 对象。

| action | 参数 | 行为 |
| --- | --- | --- |
| `open` | `url`，可选 `page_mode` | 打开完整 HTTP/HTTPS 地址，可先选择 `mobile` 或 `desktop` |
| `snapshot` | 无 | 获取网页视口截图，支持浏览器隐藏时调用 |
| `read_page` | 可选 `start`、`max_chars` | 分页读取当前页面正文，默认从 0 开始、最多 8000 字符，单次上限 16000；不生成截图 |
| `find` | `snapshot_id`, `text` | 原生页内查找并高亮，返回截图及 `find_matches` / `find_complete`；相同关键词再次调用跳至下一个匹配 |
| `click` | `snapshot_id`, `x`, `y` | 按截图像素点击，原点是网页截图左上角 |
| `scroll` | `snapshot_id`，非零 `delta_x` 或 `delta_y`，可选成对的 `x/y` | 从指定位置派发原生滑动，命中嵌套滚动区域；距离正值向下/向右，单位为截图像素 |
| `type` | `snapshot_id`, `text`，可选 `submit` | 向已聚焦输入框插入文字；`submit=true` 通过原生键盘或定向 Web 按键通道发送 Enter，空 `text` 可只按回车 |
| `back` / `forward` / `reload` | `snapshot_id` | 后退、前进、刷新 |
| `set_page_mode` | `snapshot_id`, `page_mode` | 切换为 `mobile` 或 `desktop` 并重新加载，返回新截图 |
| `wait_for_user` | 无 | 让出控制并等待用户交还；如用户已交还则直接返回新截图 |

`find/click/scroll/type/back/forward/reload/set_page_mode` 必须使用上一次截图返回的 `snapshot_id`。返回值包含 `action_executed`、`status`、`url`、`title`、当前 `page_mode`、`snapshot_id`、截图 `width/height`、`page_loading`、`focused_editable`，以及表示浏览器界面是否展示的 `browser_visible` 和应用是否在前台的 `app_foreground`。截图原始字节通过 `ToolExecutionContext.inputAttachments` 传输，不写入工具 JSON 或会话历史。

`read_page` 返回 `page_text`，包含实际 `url`、`title`、`text`、`start`、`next_start`、`has_more` 和 `limited`。可用 `next_start` 继续读取；达到提取上限时 `limited=true`。输入控件、可编辑草稿和隐藏内容不包含在正文中；未加载、折叠、Canvas、跨域 iframe 的文字可能缺失。仅执行应用固定的读取脚本，不接受模型提供的选择器或任意脚本。用户接管或会话取消后不交付读取结果。

`type` 还返回 `input_method`（`native_keyboard` / `focused_element`）、`text_inserted` 与 `submit_sent`。`submit_sent` 表示按键派发完成，不保证网页已提交成功。派发异常保留已插入文字的状态，并提示操作可能已发生，避免自动重复提交或写入。实际提交结果仍需根据后续页面判断。

工具列表显示“需确认”：当前对话首次打开浏览器、关闭后重开或当前为空白页时，`open` 请求用户确认。已有非空白页面时，导航、截图、读取、查找、点击、滚动、输入和模式切换直接执行。`wait_for_user` 直接进入等待交还流程，无需先确认；用户接管仍只由顶部“接管页面”按钮触发。参数、会话归属和截图有效性始终由执行器校验。

同一对话内的操作串行执行；过期或跨对话截图、越界坐标、同一页面的并行调用和子智能体争用都会被拒绝。不同对话可以同时操作各自页面。同一批次不能发多个浏览器操作，即使执行器依次执行，后续请求携带的旧截图也不能用于新页面状态。网页跳转、滚动、尺寸变化、用户接管均会使旧截图失效。发生错误时操作可能已经执行，模型应先截图确认，不能盲目重试提交。原生触摸派发失败不能用来断言网页空白或浮层遮挡；cookie、Feedback 等网页控件仍须按截图操作，不自动删除或接受。

## 实现与范围

- `BuiltinBrowserHost.ets`：根页面常驻的浏览器容器，按标签代号创建/销毁 Web。`RenderMode.SYNC_RENDER` 将网页纳入组件截图。`BuilderNode.postTouchEvent` 成对派发原生 DOWN/UP，按下后等待 50ms 再抬起，使用严格递增的单调时钟时间戳。截图坐标换算为 Web 节点的局部物理像素，窗口/屏幕坐标作为事件元数据保留；父容器的位移和进出动画不改变局部触点，也不再因单纯窗口偏移中止手势。取消、接管、视口尺寸变化或派发失败时使用 CANCEL，避免补发 UP 误点确认按钮。模型/空闲/暂停状态通过 Web 之外的透明层阻挡真实指针操作，模型事件直接派发到 Web 子树，不依赖异步事件的 pointer id 来判断接管。没有使用测试专用输入注入 API 或模型任意 JavaScript 执行器。
- 首次 `open` 的目标地址直接作为该标签的 `Web.src`，避免初始化空白页与首次 `loadUrl` 相互覆盖。迟到的空白页回调不覆盖已请求的地址；截图结果读取控制器的实际 URL 和标题，仍为 `about:blank` 时明确报告导航未确认。同文档 `#fragment` 使用固定脚本更新片段并查找实际的 `id`/`name`，不重新加载页面；不存在的锚点明确提示改用 `find`，不假设章节英文名就是锚点 ID。
- `scroll` 不再调用只操作整页的 `WebviewController.scrollBy`，而是在选定点派发 DOWN/MOVE/UP，依靠原生命中检测交给内层滚动区域处理。每步间隔 16ms；结束前短暂停留以减小惯性。一次请求只派发一次手势，超出视口的距离按比例缩短；实际滚动位移仍由页面决定，模型必须看新截图。起点太靠边或位移不足以形成滑动时直接报错，不把操作变成点击。用户接管、请求取消、视口变化、关闭页面或派发失败时发送 CANCEL 释放触点。坐标与事件完整性依据 [BuilderNode 官方文档](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/js-apis-arkui-buildernode/)。
- 输入控制器不再被每次点击或同一 URL 的加载完成回调清空，避免重复点击同一输入框后没有新键盘回调而失去输入能力。焦点检测只返回状态，不读取字段内容给模型；可进入同源 iframe 和开放 Shadow DOM。没有原生键盘通道时，固定脚本向当前聚焦的文本框/编辑器写入，支持选区替换、光标、多行及输入事件。脚本不接受模型代码或选择器，文本以 JSON 编码，超时或结果不明时不自动换通道重发。跨域 iframe/封闭组件仍需原生控制器，否则明确报错。API 行为参见 [WebKeyboardController 官方文档](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/arkts-basic-components-web-webkeyboardcontroller/)。
- 模型自定义键盘的 `@Builder` 属于实际标签组件，并绑定该组件后交给 ArkWeb；不能直接传递无上下文的全局构建器，否则原生回调会触发 `observeComponentCreation2 of undefined` 崩溃。标签销毁时释放绑定，已关闭输入框、旧标签或用户接管后的延迟构建回调不再创建键盘；用户接管仍使用系统输入法。
- Enter 优先通过 `WebKeyboardController.sendFunctionKey(EnterKeyType.DONE)` 发送，避免使用未指定动作的 `UNSPECIFIED`。没有键盘控制器时，使用 `UIContext.dispatchKeyEvent` 向当前 Web 节点发送 Enter 的 DOWN/UP，不要求拉起软键盘、前置浏览器或抢占聊天焦点；派发期间仅放行这一次 Enter，其他实体键仍需用户接管。输入后短暂等待页面处理，再发送提交动作；派发返回“未消费”或发生异常时不自动切换通道重试。
- 手机版/电脑版使用当前 ArkWeb 的默认 UA，保留引擎/系统版本，调整 Phone/PC 与 Mobile 标记，并为该实例设置对应的 User-Agent Client Hints；不修改其他 WebView。初次挂载先设置 UA，切换时刷新，`open` 指定模式时只导航一次。ArkWeb 根据 Mobile 标记决定移动端 meta-viewport 行为；设备和站点仍可有自己的布局规则。参见 [ArkWeb User-Agent 官方说明](https://developer.huawei.com/consumer/en/doc/harmonyos-guides/web-default-useragent/)。
- 浏览器隐藏时保留完整尺寸的 Web 节点，移到不透明主界面的后面，不使用 `Visibility.Hidden`、零尺寸或透明度清空网页绘制；同时关闭外层触摸和无障碍焦点。显示/隐藏不重新创建 Web，也不强制拉起浏览器或应用。
- `BuiltinBrowserService.ets`：单个会话的控制权、截图版本、取消和超时；`BuiltinBrowserManager.ets` 按会话管理实例、显示、网址记忆和 Cookie 设置。截图编号包含实例编号，不能跨对话使用。显示状态与控制权分离，后台/隐藏均保留模型控制；显式用户接管、取消和渲染故障不会因前后台切换被解除。截图期间如果页面变化或用户接管，不会交付该帧。
- 模型操作和截图前激活当前 ArkWeb 实例，后台失焦保留模型已聚焦输入框的键盘控制器，并使用 `DISABLE_AUTO_KEYBOARD_ON_ACTIVE` 避免激活时自动弹出系统输入法。任务结束后，隐藏的空闲页面恢复非激活状态。使用的是单个实例的生命周期 API，不全局恢复其他 WebView 的定时器。参见 [WebviewController 官方文档](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/arkts-apis-webview-webviewcontroller)。
- 应用后台运行复用现有聊天任务的 `BackgroundRunGuardService`。系统仍可能拒绝后台运行、挂起或回收进程；本实现不会把这种限制伪装成用户接管，也不承诺进程被系统停止后仍可执行。后台原生输入与持续截图须真机验收。
- `BuiltinBrowserTool.ets`：工具 Schema、视觉能力检查、主智能体限制和原生图片输入侧通道。
- 截图最长边为 1600 像素，JPEG 80；释放 PixelMap/ImagePacker，仅在本轮内存中保留最新两张浏览器图片。
- 页面只允许 HTTP/HTTPS 顶层导航，关闭本地文件访问及自动网页权限授权。网页内容作为外部数据，不能改变系统/工具指令。
- 关闭或删除会话销毁其 Web 节点、删除网址记忆并使截图编号失效，其他会话不受影响；截图从未落盘。Cookie 开关关闭时使用 [ArkWeb 隐私模式](https://developer.huawei.com/consumer/cn/doc/doccenter-capabilities/web-incognito-mode)，开启时使用默认共享存储，并在应用进入后台时通过 [WebCookieManager](https://developer.huawei.com/consumer/en/doc/harmonyos-references/arkts-apis-webview-webcookiemanager/) 持久化。关闭开关会清除共享 Cookie；关闭单个页面不清除其他页面正在共用的 Cookie。
- 一键清空先销毁页面并持久化空网址列表，再清除普通/隐私 Cookie 和站点存储，最后调用 [WebviewController.removeAllCache(true)](https://developer.huawei.com/consumer/en/doc/harmonyos-references/arkts-apis-webview-webviewcontroller/) 删除内存及磁盘资源缓存。该 API 清除同应用 Web 组件共享的资源缓存，内部网页下次加载时也可能重新下载资源；不删除聊天记录、附件或 Python 工作区文件。偏好写入失败会向清理流程报错，不能误报清空成功。
- 每个对话只有一个页面，不提供对话内多标签、文件上传下载或系统弹窗操作。嵌套滚动依靠模型在截图中选择起点，不读取 DOM；网页拦截触摸、设置 `touch-action: none` 或滚动区域到达边界时，仍可能不发生位移。

## 验证

自动检查：

```sh
node tools/test-builtin-browser.cjs
node tools/test-builtin-browser-manager.cjs
node tools/test-builtin-browser-input.cjs
python3 tools/validate-tool-schemas.py
DEVECO_SDK_HOME=/Applications/DevEco-Studio.app/Contents/sdk /Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw assembleHap --mode module -p product=default -p module=entry@default -p buildMode=debug --no-daemon --no-incremental
node tools/test-builtin-browser-keyboard.cjs
```

Node 测试执行生产参数解析、控制权/会话状态机和原生适配器方法，ArkUI 边界使用模拟对象。它不替代真机的 Web 渲染、原生事件和输入法验证。

`test-builtin-browser-keyboard.cjs` 必须在完整 ArkTS 构建后执行。它加载编译后的标签组件和原生适配器，以无接收对象的方式调用键盘构建器，覆盖组件上下文、后台、用户接管、输入框关闭、标签销毁及会话切换；可用 `XCUBE_COMPILED_BROWSER_HOST` 指定其他构建产物路径。

`test-builtin-browser-input.cjs` 使用独立临时配置的无头 Chromium 执行生产输入脚本，验证中文/多行/选区替换、受控输入事件、contenteditable、同源 iframe、Shadow DOM、后台标签以及不可编辑/跨域/取消/过期情况。标准表单用本地 LuCI 风格控件验证插入后回车、点击提交及按钮焦点回车只提交一次，不连接路由器或发送登录请求。可用 `XCUBE_PLAYWRIGHT_PATH` 和 `XCUBE_CHROMIUM_PATH` 指定本地依赖和浏览器；不访问用户已有浏览器资料。

真机验收可在开发机运行 `python3 -m http.server 8765 --directory tools/fixtures`，由同一网络中的 HarmonyOS 设备打开 `http://开发机局域网地址:8765/builtin-browser.html`：

1. 模型 `open`，确认它收到的截图与设备显示一致且不包含浏览器地址栏。
2. 点击页面按钮，确认计数恰好增加一次，页面报告原生事件 `isTrusted=true`。
3. 点击输入框，输入中英混合文本并 `submit=true`，检查 `text_inserted` 和 `submit_sent`；无原生 Enter 时点击页面提交按钮，确认回显完整文本。重复点击同一输入框后再次输入，并在加载完成回调之后、切换到后台之后验证，确认不会丢失输入通道或重复文字。
4. 在测试页内层列表中指定 `x/y` 向下/向上滚动，再把起点移到外层区域滚动，核对页面上的内层/外层/整页位移。测试横向滚动、iframe 内滚动，以及不传起点时的截图中心滚动。检查滚动过程中没有误触按钮；长距离手势不得越出网页视口。
5. 点击顶部“接管页面”，确认旧截图不可用、没有隐式重放；用户输入中文后交回，模型应读到最新画面。直接触摸页面、输入框自动获取焦点、模型点击/输入和请求结束都不得显示“用户接管中”。
6. 分屏/旋转后用新截图点击，检查坐标换算；旧截图应被拒绝。
7. 模型控制时返回聊天，让模型继续截图、点击、滚动和输入，再打开浏览器核对页面变化，确认没有抢占聊天触摸、弹出系统键盘或把浏览器拉回前台。切换到其他应用后分别检查后台截图更新、点击和中英文输入。
8. 用户接管后返回聊天、进入后台再回来，确认控制权仍属于用户。等待用户期间停止生成或关闭/删除会话，确认不再继续点击或发送截图。
9. 断网、慢页面、渲染进程退出时确认错误可见、不会无限等待；用另一会话和不支持视觉的模型确认隔离/能力检查。
10. `open` 指定电脑版，再用 `set_page_mode` 切换手机版，确认测试页的 UA、Client Hints、视口宽度与工具返回的 `page_mode` 相符；切换后旧截图无效，同模式请求不增加加载计数。用户接管后用顶部模式按钮切换，交还模型时应看到新模式。两个模式均检查嵌套滚动和后台操作。
11. 两个对话分别打开不同页面，切换后各自恢复原页面，后台点击不改变另一对话。关闭其中一个页面、删除其中一个对话，另一页面仍能使用。退出并重启应用，逐个打开浏览器核对记忆的网址；已关闭或已删除的页面不恢复。
12. 开启“保存 Cookie”，在一个对话的页面登录，在另一个对话打开同站点核对共享登录，重启应用后再次核对。关闭开关后检查页面重新加载、已保存 Cookie 清除；私密页面退出后不保留登录。站点自身不允许持久登录的情况单独记录。
13. 核对浏览器按钮的默认、已有页面/记忆网址、模型操作三种状态。配置弹窗应按内容自适应高度、透出沉浸光感材质；Cookie 行无单独底板。清空后所有浏览器关闭、按钮恢复默认，重启后原网址不再恢复，登录状态及网页缓存均已清除。

自动检查不能替代以上真机验收，尤其是原生键盘、后台输入和视觉链路。
