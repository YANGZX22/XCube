import { MessageEvents, worker } from '@kit.ArkTS';
import { WorkerParam, WorkerParseReq, WorkerStringResp, WorkerTreeNodeResp } from '../model/WorkerParam';
import { Logger } from '../utils/Logger';

const TAG = 'LV-MARKDOWN-IN';

type WorkerMessage = WorkerTreeNodeResp | WorkerStringResp;
type WorkerTask = WorkerParam | WorkerStringResp | WorkerParseReq;
type WorkerListener = (message: WorkerMessage) => void;

export class WorkerManager {
  private static instance: WorkerManager = new WorkerManager();
  private workerInstance: worker.ThreadWorker | null = null;
  private listeners: Map<string, WorkerListener> = new Map();
  private workerCloseTimer: number | null = null;
  private readonly WORKER_IDLE_TIME = 500;

  private constructor() {
  }

  static getInstance(): WorkerManager {
    return WorkerManager.instance;
  }

  register(union: string, listener: WorkerListener): void {
    this.listeners.set(union, listener);
    this.clearCloseTimer();
    this.ensureWorkerAlive();
  }

  unregister(union: string): void {
    this.listeners.delete(union);
    if (this.listeners.size === 0) {
      this.resetWorkerCloseTimer();
    }
  }

  postMessage(task: WorkerTask): void {
    this.ensureWorkerAlive();
    this.workerInstance?.postMessage(task);
  }

  private ensureWorkerAlive(): void {
    if (this.workerInstance) {
      return;
    }
    this.createWorker();
    Logger.info(TAG, 'create shared worker success');
  }

  private createWorker(): void {
    this.workerInstance = new worker.ThreadWorker('../../workers/worker');

    this.workerInstance.onmessage = (e: MessageEvents) => {
      const message = e.data as WorkerMessage;
      const union = message.union;
      if (!union) {
        return;
      }
      const listener = this.listeners.get(union);
      if (!listener) {
        return;
      }
      listener(message);
    };

    this.workerInstance.onmessageerror = (err: MessageEvents) => {
      Logger.error(TAG, 'workerInstance onmessageerror is: ', JSON.stringify(err));
    };
  }

  private clearCloseTimer(): void {
    if (this.workerCloseTimer !== null) {
      clearTimeout(this.workerCloseTimer);
      this.workerCloseTimer = null;
    }
  }

  private resetWorkerCloseTimer(): void {
    this.clearCloseTimer();
    this.workerCloseTimer = setTimeout(() => {
      this.terminateWorker();
    }, this.WORKER_IDLE_TIME);
  }

  private terminateWorker(): void {
    if (!this.workerInstance) {
      return;
    }

    try {
      this.workerInstance.terminate();
      Logger.info(TAG, 'shared worker terminate success');
    } catch (e) {
      Logger.error(TAG, 'shared worker terminate failed:', JSON.stringify(e));
    }

    this.workerInstance = null;
    this.workerCloseTimer = null;
  }
}
