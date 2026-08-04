import { buffer } from '@kit.ArkTS';
import { TreeNode } from '../model/TreeNode';
import { WorkerParam, WorkerParseReq, WorkerStringResp, WorkerTreeNodeResp } from '../model/WorkerParam';
import { parseMarkdown } from '../utils/ast';
import { htmlToMarkdown } from '../utils/html2md';
import { isHtmlLike } from '../utils/HtmlDetectionUtil';
import { fileIo as fs, ReadTextOptions } from '@kit.CoreFileKit';
import { Logger } from '../utils/Logger';
import { BusinessError } from '@kit.BasicServicesKit';

const TAG = "MainReader"

/**
 * 主线程数据读取
 */
export class MainReader {
  static reader(e: WorkerParam | WorkerStringResp | WorkerParseReq): Promise<WorkerTreeNodeResp | WorkerStringResp> {
    return new Promise((resolve, reject) => {
      Logger.info(TAG, "reader param key is " + JSON.stringify(e.key))
      // Logger.info(TAG, "reader param data is " + JSON.stringify(e.data))
      if (e.key == "parse") {
        Logger.info(TAG, "parse")
        try {
          const parseReq = e as WorkerParseReq
          const original = parseReq.data.text?.toString() ?? ""

          let parsedText = original
          const isHtml = isHtmlLike(original)
          if (isHtml) {
            const converted = htmlToMarkdown(original) as string
            if (converted && converted.trim().length > 0) {
              parsedText = converted
            }
          }
          let treeNode = parseMarkdown(parsedText, parseReq.data.plugins, parseReq.data.parseOptions) as TreeNode[]
          let obj: WorkerTreeNodeResp = {
            key: "parse",
            data: treeNode,
            union: e.union,
            requestId: parseReq.requestId
          }
          resolve(obj)
        } catch (error) {
          reject(error)
        }
      }

      if (e.key == "readerRawfile") {
        Logger.info(TAG, "readerRawfile")
        let data = e as WorkerParam;
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
            resolve(obj)
          })
            .catch((err: BusinessError) => {
              Logger.error(TAG, "readerRawfile err is " + JSON.stringify(err))
            })
        } catch (error) {
          reject(error)
        }
      }

      if (e.key == "readerSandbox") {
        Logger.info(TAG, "readerSandbox")
        let data = e as WorkerStringResp;
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
          resolve(obj)
        } catch (error) {
          reject(error)
        }
      }
    })
  }
}
