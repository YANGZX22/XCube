import { TextSelectionController } from '../controller/TextSelectionController'
import { BlockSelectionStartInfo } from '../model/TextSelectionInfo'

const MOUSE_SELECTION_DRAG_THRESHOLD = 2
let activeTextSelectionMouseTracker: TextSelectionMouseTracker | undefined = undefined

export function isPrimaryMouseButton(event: MouseEvent): boolean {
  return event.button == MouseButton.Left
}

export function clearActiveTextSelectionMouseTracker() {
  activeTextSelectionMouseTracker?.reset()
  activeTextSelectionMouseTracker = undefined
}

export class TextSelectionMouseTracker {
  private pressed: boolean = false
  private selecting: boolean = false
  private startLocalX: number = 0
  private startLocalY: number = 0
  private startGlobalX: number = 0
  private startGlobalY: number = 0

  handleBlockSelectionMouseEvent(selectionUnion: string, blockId: string, event: MouseEvent) {
    if (event.action == MouseAction.Press && isPrimaryMouseButton(event)) {
      if (activeTextSelectionMouseTracker != this) {
        clearActiveTextSelectionMouseTracker()
      }
      activeTextSelectionMouseTracker = this
      this.pressed = true
      this.selecting = false
      this.startLocalX = event.x
      this.startLocalY = event.y
      this.startGlobalX = event.windowX
      this.startGlobalY = event.windowY
      return
    }

    if (event.action == MouseAction.Move && this.pressed) {
      if (!this.selecting && !this.hasDragged(event.windowX, event.windowY)) {
        return
      }
      if (!this.selecting) {
        this.selecting = true
        TextSelectionController.getInstance(selectionUnion)
          .triggerStartSelection(new BlockSelectionStartInfo(blockId, this.startLocalX, this.startLocalY, false,
            this.startGlobalX, this.startGlobalY))
      }
      const handled = TextSelectionController.getInstance(selectionUnion)
        .triggerUpdateSelection(event.windowX, event.windowY)
      if (handled) {
        event.stopPropagation()
      }
      return
    }

    if (event.action == MouseAction.Release) {
      const selecting = this.selecting
      this.reset()
      if (selecting) {
        const handled = TextSelectionController.getInstance(selectionUnion).triggerEndSelection()
        if (handled) {
          event.stopPropagation()
        }
      }
    }
  }

  reset() {
    this.pressed = false
    this.selecting = false
    if (activeTextSelectionMouseTracker == this) {
      activeTextSelectionMouseTracker = undefined
    }
  }

  private hasDragged(globalX: number, globalY: number): boolean {
    return Math.abs(globalX - this.startGlobalX) >= MOUSE_SELECTION_DRAG_THRESHOLD ||
      Math.abs(globalY - this.startGlobalY) >= MOUSE_SELECTION_DRAG_THRESHOLD
  }
}
