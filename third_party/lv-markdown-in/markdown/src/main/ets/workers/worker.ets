// worker.ets
import { buffer, ErrorEvent, MessageEvents, ThreadWorkerGlobalScope, worker } from '@kit.ArkTS';
import { TreeNode } from '../enhance/model/TreeNode';
import { WorkerParam, WorkerParseReq, WorkerStringResp, WorkerTreeNodeResp } from '../enhance/model/WorkerParam';
import { parseMarkdown } from '../enhance/utils/ast';
import { htmlToMarkdown } from '../enhance/utils/html2md';
import { isHtmlLike } from '../enhance/utils/HtmlDetectionUtil';
import { fileIo as fs, ReadTextOptions } from '@kit.CoreFileKit';

const TAG = "workerPort"
const workerPort: ThreadWorkerGlobalScope = worker.workerPort;

// 注册onmessage回调，当Worker线程收到来自其宿主线程通过postMessage接口发送的消息时被调用，在Worker线程执行
workerPort.onmessage = (e: MessageEvents) => {
  if (e.data.key == "parse") {
    try {
      let data = e.data as WorkerParseReq;

      const original = data.data.text?.toString() ?? ""

      let parsedText = original
      const isHtml = isHtmlLike(original)
      if (isHtml) {
        const converted = htmlToMarkdown(original) as string
        if (converted && converted.trim().length > 0) {
          parsedText = converted
        }
      }
      let treeNode = parseMarkdown(parsedText, data.data.plugins, data.data.parseOptions) as TreeNode[]
      let obj: WorkerTreeNodeResp = {
        key: "parse",
        data: treeNode,
        union: data.union,
        requestId: data.requestId
      }
      // 向宿主线程发送消息
      workerPort.postMessage(obj);
    } catch (err) {
      console.error(TAG + " parseMarkdown error > " + JSON.stringify(err));
      // 即使解析抛错也必须回包(带 requestId/union), 否则宿主侧 latest-wins 闸门(parseInFlight)收不到
      // 响应会永久卡死、渲染冻结。标记 error 让宿主结算闸门但不覆盖上一次有效渲染。
      let req = e.data as WorkerParseReq;
      let errObj: WorkerTreeNodeResp = {
        key: "parse",
        data: [],
        union: req.union,
        requestId: req.requestId,
        error: true
      }
      workerPort.postMessage(errObj);
    }
  }

  if (e.data.key == "readerRawfile") {
    let data = e.data as WorkerParam;
    try {
      let uint8Array =
        data.data.ctx.resourceManager.getRawFileContentSync(data.data.rawfilePath);
      let bf = buffer.from(uint8Array).buffer;
      let bf2 = new buffer.Blob([bf]);
      let pro = bf2.text();
      pro.then((str: string) => {
        let obj: WorkerStringResp = {
          key: "readerRawfile",
          data: str,
          union: data.union
        }
        // 向宿主线程发送消息
        workerPort.postMessage(obj);
      });
    } catch (error) {
    }
  }

  if (e.data.key == "readerSandbox") {
    let data = e.data as WorkerStringResp;
    try {
      let readTextOptions: ReadTextOptions = {
        offset: 0,
        length: 0,
        encoding: 'utf-8'
      };
      let stat = fs.statSync(data.data);
      readTextOptions.length = stat.size;
      let text = fs.readTextSync(data.data, readTextOptions);
      let obj: WorkerStringResp = {
        key: "readerSandbox",
        data: text,
        union: data.union
      }
      // 向宿主线程发送消息
      workerPort.postMessage(obj);
    } catch (error) {

    }
  }
}

// 注册onmessageerror回调，当Worker对象接收到一条无法被序列化的消息时被调用，在Worker线程执行
workerPort.onmessageerror = () => {
  console.error('workerPort onmessageerror');
}

// 注册onerror回调，捕获Worker在执行过程中发生的异常，在Worker线程执行
workerPort.onerror = (err: ErrorEvent) => {
  console.error('workerPort onerror err is: ', err.message);
}
