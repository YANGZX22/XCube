import { matrix4, window } from '@kit.ArkUI';
import { image } from '@kit.ImageKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { runWithAnimation, windowSizeManager } from '../utils/WindowSizeUtil';
import { ScreenUtil } from '../utils/ScreenUtil';

const DOMAIN = 0x0000;
const TAG = 'ImageModel';
const FORMAT = '%{public}s';

@Observed
export class ImageModel {
  // Copy function of Matrix
  public matrix: matrix4.Matrix4Transit = matrix4.identity().copy();
  // The current scale
  public curScale: number = 1;
  // The current offset X
  public curOffsetX: number = 0;
  // The current offset is Y
  public curOffsetY: number = 0;
  // Record the last zoom
  public lastScale: number = 1;
  // Record the offset of the last X-axis
  public lastOffsetX: number = 0;
  // Records the last Y-axis offset
  public lastOffsetY: number = 0;
  // Minimum image zoom
  public minScale: number = 0.5;
  // Maximum zoom of the image
  public maxScale: number = 1;
  // Default zoom
  public defaultScaleValue: number = 1;
  // Maximum deviation of the X-axis
  public maxOffsetX: number = 999;
  // Minimum deviation of the X-axis
  public minOffsetX: number = -999;
  // Maximum deviation of the Y-axis
  public maxOffsetY: number = 999;
  // Minimum deviation of Y-axis
  public minOffsetY: number = -999;
  public centerX: number = 0.5;
  public centerY: number = 0.5;
  public center: number[] = [0.5, 0.5];
  public componentHeight: number = 0;
  public componentWidth: number = 0;
  // Picture Width
  public imageWidth: number = 100;
  // Picture Height
  public imageHeight: number | undefined = undefined;
  // Whether to allow swiper components to slide
  public isDisableSwipe: boolean = false;

  constructor(
    matrix: matrix4.Matrix4Transit = matrix4.identity().copy(),
    curScale: number = 1,
    curOffsetX: number = 0,
    curOffsetY: number = 0,
    lastScale: number = 1,
    lastOffsetX: number = 0,
    lastOffsetY: number = 0,
    minScale: number = 0.5,
    maxScale: number = 1,
    defaultScaleValue: number = 1,
    maxOffsetX: number = 999,
    minOffsetX: number = -999,
    maxOffsetY: number = 999,
    minOffsetY: number = -999,
    centerX: number = 0.5,
    centerY: number = 0.5,
    center: [number, number] = [0, 0],
    componentHeight: number = 0,
    componentWidth: number = 0,
    imageWidth: number = ScreenUtil.getInstance().getScreenWidth(),
    imageHeight: number | undefined = undefined,
    isDisableSwipe: boolean = false
  ) {
    this.matrix = matrix;
    this.curScale = curScale;
    this.curOffsetX = curOffsetX;
    this.curOffsetY = curOffsetY;
    this.lastScale = lastScale;
    this.lastOffsetX = lastOffsetX;
    this.lastOffsetY = lastOffsetY;
    this.minScale = minScale;
    this.maxScale = maxScale;
    this.maxScale = maxScale;
    this.defaultScaleValue = defaultScaleValue;
    this.maxOffsetX = maxOffsetX;
    this.minOffsetX = minOffsetX;
    this.maxOffsetY = maxOffsetY;
    this.minOffsetY = minOffsetY;
    this.centerX = centerX;
    this.centerY = centerY;
    this.center = center;
    this.componentHeight = componentHeight;
    this.componentWidth = componentWidth;
    this.imageWidth = imageWidth;
    this.imageHeight = imageHeight;
    this.isDisableSwipe = isDisableSwipe;
  }

  // Pan gestures callback during movement.
  gestureEnd(): void {
    this.lastScale = this.curScale;
    this.lastOffsetX = this.curOffsetX;
    this.lastOffsetY = this.curOffsetY;
  }

  // When switching images, reset the previous image.
  imageReset(): void {
    setTimeout(() => {
      this.matrix = matrix4.identity().scale({
        x: this.defaultScaleValue,
      }).copy();
      this.lastScale = this.defaultScaleValue;
      this.offsetReset();
    }, 200);
  }

  // Offset reset.
  offsetReset(): void {
    this.curOffsetX = 0;
    this.curOffsetY = 0;
    this.lastOffsetX = 0;
    this.lastOffsetY = 0;
  }

  // [Start get_window_size]
  // Get window size.
  windowSize(): void {
    window.getLastWindow(getContext()).then((window: window.Window) => {
      try {
        this.componentWidth = px2vp(window.getWindowProperties().windowRect.width);
        this.componentHeight = px2vp(window.getWindowProperties().windowRect.height);
      } catch (err) {
        hilog.error(DOMAIN, TAG, FORMAT,
          `GetWindowProperties failed. Cause code: ${err.code}, message: ${err.message}`);
      }
    }).catch((err: BusinessError) => {
      hilog.error(DOMAIN, TAG, FORMAT, `GetLastWindow failed. Cause code: ${err.code}, message: ${err.message}`);
    });
  }

  // [StartExclude get_window_size]
  // [Start picture_scaling]
  // General picture scaling value method.
  pictureScaling(scale: number): void {
    this.matrix = matrix4.identity().scale({
      x: scale,
      y: scale
    }).copy();
  }

  // [EndExclude get_window_size]

  // [StartExclude picture_scaling]
  // Calculate the range of the picture boundary.
  evaluateOffsetRange(): void {
    // [Start attribute_max_offsetX]
    this.maxOffsetX = Math.abs(Math.min(((1 - this.curScale) * this.componentWidth) / 2, 0));
    // [End attribute_max_offsetX]
    // [Start attribute_min_offsetX]
    this.minOffsetX = -Math.abs(Math.max((this.componentWidth * (this.curScale - 1)) / 2, 0));
    // [End attribute_min_offsetX]
    // [Start attribute_offsetY]
    if (this.imageHeight) {
      this.maxOffsetY = Math.abs(Math.min((this.componentHeight -
        this.curScale * this.imageHeight * this.componentWidth / this.imageWidth) / 2, 0));
      this.minOffsetY = -Math.abs(Math.max((this.curScale * this.imageHeight * this.componentWidth / this.imageWidth -
      this.componentHeight) / 2, 0));
    }
    // [End attribute_offsetY]
  }

  // [End get_window_size]

  // [Start evaluate_center]
  // Calculates the percentage position of the current zoom center relative to the picture
  evaluateCenter(centerX: number, centerY: number): [number, number] {
    let imgDisplayWidth = this.imageWidth * this.lastScale;
    let imgDisplayHeight = 100
    if (this.imageHeight) {
      imgDisplayHeight = this.imageHeight * this.lastScale;
    }
    let imgX = (this.componentWidth - imgDisplayWidth) / 2 + this.lastOffsetX;
    let imgY = (this.componentHeight - imgDisplayWidth) / 2 + this.lastOffsetY;
    let cX = Math.max((centerX - imgX) / imgDisplayWidth, 0);
    let cY = Math.max((centerY - imgY) / imgDisplayHeight, 0);
    return [cX, cY];
  }

  // [StartExclude evaluate_center]
  // Calculate the maximum zoom value of the picture.
  calcFitScaleRatio(imageSize: image.Size, windowSize: window.Size): number {
    let ratio: number = 1.0;
    if (windowSize.width > imageSize.width) {
      ratio = windowSize.width / imageSize.width;
    } else {
      ratio = windowSize.height / imageSize.height;
    }
    return ratio + 0.5;
  }

  // [Start pan_gesture_update]
  // Pan gestures callback during movement.
  panGestureUpdate(event: GestureEvent): boolean {
    this.onScale(event.scale, event.offsetX, event.offsetY);
    this.pictureBoundaryRestriction();
    return this.isDisableSwipe;
  }

  // [EndExclude evaluate_center]

  // [StartExclude pan_gesture_update]
  // Pinch gesture recognition successful callback.
  pinchGestureStart(event: GestureEvent): void {
    this.center = this.evaluateCenter(event.pinchCenterX, event.pinchCenterY);
    this.centerX = 1 - this.center[0];
    this.centerY = 1 - this.center[1];
  }

  // [End evaluate_center]

  // [Start picture_boundary_restriction]
  // Picture Boundary Restriction
  pictureBoundaryRestriction(): void {
    if (this.curOffsetX >= this.maxOffsetX) {
      this.curOffsetX = this.maxOffsetX;
      this.isDisableSwipe = false;
    }
    if (this.curOffsetX <= this.minOffsetX) {
      this.curOffsetX = this.minOffsetX;
      this.isDisableSwipe = false;
    }
    if (this.curOffsetY >= this.maxOffsetY) {
      this.curOffsetY = this.maxOffsetY;
    }
    if (this.curOffsetY <= this.minOffsetY) {
      this.curOffsetY = this.minOffsetY;
    }
  }

  // [End picture_boundary_restriction]
  // [EndExclude picture_scaling]

  // Pinch gestures callback during a move.
  pinchGestureUpdate(event: GestureEvent): boolean {
    this.onScale(event.scale, event.offsetX, event.offsetY);
    this.pictureScaling(this.curScale);
    if (this.curScale > this.defaultScaleValue) {
      this.isDisableSwipe = true;
    }
    this.pictureBoundaryRestriction();
    return this.isDisableSwipe;
  }

  // [StartExclude picture_scaling]
  // The Pinch gesture is recognized successfully, and the callback is triggered when the finger is lifted.
  pinchGestureEnd(): void {
    runWithAnimation(() => {
      // When the scale is less than 1
      if (this.curScale <= this.defaultScaleValue) {
        this.pictureScaling(this.defaultScaleValue);
        this.imageReset();
      } else if (this.curScale >= this.maxScale) {
        this.curScale -= 0.1;
        this.pictureScaling(this.curScale);
      }
      this.gestureEnd();
    });
  }

  // Tap gesture recognition callback succeeded.
  doubleTapGesture(event: GestureEvent): boolean {
    let curRatio: number = 1;
    this.center = this.evaluateCenter(event.fingerList[0].displayX, event.fingerList[0].displayY);
    this.centerX = 1 - this.center[0];
    this.centerY = 1 - this.center[1];
    // When the last scale is greater than 1, the default scale is restored
    if (this.lastScale > this.defaultScaleValue) {
      runWithAnimation(() => {
        windowSizeManager.get();
        this.pictureScaling(this.defaultScaleValue);
        this.offsetReset();
      });
      curRatio = this.defaultScaleValue;
      this.isDisableSwipe = false;
    } else {
      runWithAnimation(() => {
        this.onScale(event.scale, event.offsetX, event.offsetY);
        windowSizeManager.get();
        this.pictureScaling(this.maxScale);
        this.offsetReset();
      });
      curRatio = this.maxScale;
      this.isDisableSwipe = true;
    }
    this.lastScale = curRatio;
    return this.isDisableSwipe;
  }

  // [EndExclude pan_gesture_update]
  // [StartExclude picture_scaling]

  // Calculates the offset X and offset Y of the current picture and the scaling value of the current picture.
  onScale(scale: number, offX: number, offY: number): void {
    // [StartExclude pan_gesture_update]
    if (this.lastScale * scale > this.maxScale) {
      this.curScale = this.maxScale;
    } else if (this.lastScale * scale < this.minScale) {
      this.curScale = this.minScale;
    } else {
      this.curScale = this.lastScale * scale;
    }
    if (this.lastScale * scale === this.maxScale) {
      this.curScale -= 0.001;
    }
    this.evaluateOffsetRange();
    // [EndExclude pan_gesture_update]
    if (this.curScale < this.maxScale) {
      if (this.imageHeight) {
        this.curOffsetY =
          (this.lastOffsetY + offY) + (0.5 - this.centerY) * this.imageHeight * (1 - scale) * this.lastScale;
      }
      this.curOffsetX =
        (this.lastOffsetX + offX) + (0.5 - this.centerX) * this.imageWidth * (1 - scale) * this.lastScale;
    }
  }

  // [End pan_gesture_update]
  // [End picture_scaling]
}

/**
 * Status bar title and icon.
 */
export class ImageInfo {
  icon?: Resource;
  name?: Resource;

  constructor(icon: Resource, name: Resource) {
    this.icon = icon;
    this.name = name;
  }
}