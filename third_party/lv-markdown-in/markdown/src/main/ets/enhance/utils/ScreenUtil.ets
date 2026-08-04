import { display, window } from "@kit.ArkUI"

@ObservedV2
export class ScreenUtil {
  private static instance: ScreenUtil
  private notificationBarHeight: number = 0
  private navigationBarHeight: number = 0
  @Trace windowBreakPoint: string = ""

  setNotificationBarHeight(notificationBarHeight: number) {
    this.notificationBarHeight = notificationBarHeight
  }

  setNavigationBarHeight(navigationBarHeight: number) {
    this.navigationBarHeight = navigationBarHeight
  }

  getNotificationBarHeight() {
    return this.notificationBarHeight
  }

  getNavigationBarHeight() {
    return this.navigationBarHeight
  }

  getScreenHeight() {
    return px2vp(display.getDefaultDisplaySync().height)
  }

  getScreenWidth() {
    return px2vp(display.getDefaultDisplaySync().width)
  }

  /**
   * 检查是否是大屏设备
   * @returns
   */
  checkIsLargeScreen() {
    return (this.windowBreakPoint == "lg" || this.windowBreakPoint == "xxl")
  }

  async init() {
    const windowClass = await window.getLastWindow(getContext())
    // 3. 保存窗口通知栏与导航栏高度
    let notification_avoidArea = windowClass.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM); // 通知栏
    let navigation_avoidArea = windowClass.getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR); // 导航栏

    ScreenUtil.getInstance().setNotificationBarHeight(px2vp(notification_avoidArea.topRect.height))
    ScreenUtil.getInstance().setNavigationBarHeight(px2vp(navigation_avoidArea.bottomRect.height))
  }

  static getInstance(): ScreenUtil {
    if (!ScreenUtil.instance) {
      ScreenUtil.instance = new ScreenUtil();
    }
    return ScreenUtil.instance;
  }
}