import { ImageModel } from '../model/ImageModel';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { image } from '@kit.ImageKit';
import { windowSizeManager } from '../utils/WindowSizeUtil';
import { ImageDialogController } from '../controller/ImageDialogController';
import { ImageImpl } from '../impl/ImageImpl';
import { Logger } from '../utils/Logger';

const TAG = 'ImageView';

@Builder
export function ImageDialogBuilder() {
  ImageView()
}

@Component
export struct ImageView {
  @Provide isDisableSwipe: boolean = false;
  @Provide isImageReset: boolean = false;
  private thumbnailSwipeController: SwiperController = new SwiperController();

  @Builder
  ImageSwiper() {
    Swiper(this.thumbnailSwipeController) {
      ForEach([ImageDialogController.getInstance().src],
        (img: string) => {
          ImageItemView({
            imageData: ImageImpl.handleImageSrc(ImageDialogController.getInstance().markdownUnion, img)
          })
            .width('100%')
            .height('100%')
        }, (img: Resource, index: number) => JSON.stringify(img) + index)
    }
    .effectMode(EdgeEffect.None)
    .loop(false)
    .width('100%')
    .height('100%')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .autoPlay(false)
    .disableSwipe(this.isDisableSwipe)
    .indicator(false)
    .cachedCount(20)
    .onChange((index: number) => {
    })
    .onGestureSwipe(() => {
      this.isImageReset = false;
    })
    .onAnimationStart((index: number, targetIndex: number) => {
      if (index !== targetIndex) {
        this.isImageReset = true;
      }
    })
  }

  aboutToAppear(): void {
    setTimeout(() => {
      animateTo({ duration: 250 }, () => {
        ImageDialogController.getInstance().imageViewShowState = true
        ImageDialogController.getInstance().bgc = "#66000000"
        ImageDialogController.getInstance().pageOpacity = 1
      })
    }, 10)
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      if (ImageDialogController.getInstance().imageViewShowState) {
        this.ImageSwiper()
      }
    }
    .backgroundColor(ImageDialogController.getInstance().bgc)
    .opacity(ImageDialogController.getInstance().pageOpacity)
    .width("100%")
    .height("100%")
  }
}

@Component
export struct ImageItemView {
  @State imageData: ResourceStr = "";
  @State imageModel: ImageModel = new ImageModel();
  // Swipe whether to switch
  @Consume isDisableSwipe: boolean;
  @Consume @Watch('onImageReset') isImageReset: boolean;
  private context: common.UIAbilityContext = getContext() as common.UIAbilityContext;
  private imageWHRatio: number = 0;

  aboutToAppear(): void {
    this.imageModel.windowSize();
    setTimeout(() => {
      this.initCurrentImageInfo();
    }, 10);
  }

  // When switching images, reset the previous image
  onImageReset(): void {
    if (this.isImageReset) {
      this.imageModel.imageReset();
    }
  }

  /**
   * Set information about the current image: uri, whRatio, pixelMap, defaultSize, maxScaleValue
   * Obtain the Image information in advance for the size setting of
   * the image component and subsequent related calculations
   */
  initCurrentImageInfo(): void {
    if (typeof this.imageData == "object") {
      try {
        let img = this.context.resourceManager.getRawFileContentSync(this.imageData?.params?.[0] || "");
        let imageSource = image.createImageSource(img.buffer.slice(0));
        imageSource.getImageInfo(0).then((data: image.ImageInfo) => {
          this.imageWHRatio = data.size.width / data.size.height;
          this.imageModel.imageWidth = this.imageModel.componentWidth;
          this.imageModel.imageHeight = this.imageModel.imageWidth / this.imageWHRatio;
        }).catch((err: BusinessError) => {
          Logger.info(TAG, `[error][getImageInfo]${err.message}`);
        });
      } catch (err) {
        Logger.info(TAG, `GetMediaContentSync failed. Cause code: ${err.code}, message: ${err.message}`);
      }
    } else {
      Logger.info(TAG, `get network image info.`);
    }
  }

  build() {
    Stack() {
      Column()
        .width("100%")
        .height("100%")
        .onClick(() => {
          ImageDialogController.getInstance().closeBindSheet()
        })
      Image(this.imageData)
        .width(this.imageModel.imageWidth)
        .height(this.imageModel.imageHeight)
        .aspectRatio(this.imageWHRatio)
        .objectFit(ImageFit.Cover)
        .autoResize(false)
        .defaultFocus(true)
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
        .transform(this.imageModel.matrix)// Control picture scaling with matrix
        .translate({
          x: this.imageModel.curOffsetX,
          y: this.imageModel.curOffsetY
        })
        .onComplete((event) => {
          if (event && !this.imageModel.imageHeight) {
            this.imageWHRatio = event.width / event.height;
            this.imageModel.imageHeight = this.imageModel.imageWidth / this.imageWHRatio;
          }
          this.imageModel.maxScale = this.imageModel.calcFitScaleRatio({
            width: this.imageModel.imageWidth,
            height: this.imageModel.imageHeight || 100
          }, windowSizeManager.get());
        })
    }
    .alignContent(Alignment.Center)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .width('100%')
    .height('100%')
    .parallelGesture(
      GestureGroup(
        GestureMode.Exclusive,
        // [Start pan_gesture_fingers_one]
        // Slide picture
        // Swiping left and right under the default size should switch images
        // [Start component_pan_gesture]
        PanGesture({ fingers: 1, distance: this.isDisableSwipe ? 3 : 50 })// [End component_pan_gesture]
          .onActionUpdate((event: GestureEvent) => {
            this.isDisableSwipe = this.imageModel.panGestureUpdate(event);
          })
          .onActionEnd(() => {
            this.imageModel.gestureEnd();
          }),
        // [End pan_gesture_fingers_one]
        // [Start pan_gesture_fingers_two]
        // Two-finger scaling
        PinchGesture({ fingers: 2, distance: 1 })
          .onActionStart((event: GestureEvent) => {
            this.imageModel.pinchGestureStart(event);

          })
          .onActionUpdate((event: GestureEvent) => {
            this.isDisableSwipe = this.imageModel.pinchGestureUpdate(event);
          })
          .onActionEnd(() => {
            this.imageModel.pinchGestureEnd();
          }),
        // [End pan_gesture_fingers_two]
        // Double click picture
        TapGesture({ count: 2 })
          .onAction((event: GestureEvent) => {
            this.isDisableSwipe = this.imageModel.doubleTapGesture(event);
          }),
        // Click Switch picture toolbar
        TapGesture({ count: 1 })
          .onAction(() => {

          })
        // Pinching and scaling images with two fingers
      ), GestureMask.Normal
    )
  }
}