export enum HandAdaptiveFollowTarget {
  TASKBAR = 'taskbar',
  PLUS = 'plus'
}

// 保持现有的加号跟随行为作为默认值；旧布尔开关不再控制新的互斥选择。
export function normalizeHandAdaptiveFollowTarget(value: string): HandAdaptiveFollowTarget {
  return value === HandAdaptiveFollowTarget.TASKBAR ? HandAdaptiveFollowTarget.TASKBAR : HandAdaptiveFollowTarget.PLUS
}
