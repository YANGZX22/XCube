// HiLogUtil.ets
import hilog from '@ohos.hilog';

// import BuildProfile from 'BuildProfile';

// import AppConfig from '../../../../../appCommon/BuildProfile';

/**
 * 日志级别枚举
 */
export enum LogLevel {
  DEBUG = hilog.LogLevel.DEBUG,
  INFO = hilog.LogLevel.INFO,
  WARN = hilog.LogLevel.WARN,
  ERROR = hilog.LogLevel.ERROR,
  FATAL = hilog.LogLevel.FATAL,
}

/**
 * HiLog工具类 - 支持长日志换行、多级别日志和强制打印
 */
export class LogUtil {
  // 日志最大长度
  private static MAX_LOG_LENGTH: number = 800;
  // 强制打印标志 - 用于release环境
  private isForcePrint: boolean | undefined = AppStorage.get<boolean>("MarkdownForcePrint");

  // private isForcePrint: boolean = true;

  /**
   * 打印DEBUG级别日志 - 支持多参数
   * @param tag 日志标签
   * @param messages 日志内容参数列表   */
  public debug(tag: string, ...messages: ESObject[]): void {
    this.printLog(LogLevel.DEBUG, tag, messages);
  }

  /**
   * 打印INFO级别日志 - 支持多参数
   * @param tag 日志标签
   * @param messages 日志内容参数列表
   */
  public info(tag: string, ...messages: ESObject[]): void {
    this.printLog(LogLevel.INFO, tag, messages);
  }

  /**
   * 打印WARN级别日志 - 支持多参数
   * @param tag 日志标签
   * @param messages 日志内容参数列表
   */
  public warn(tag: string, ...messages: ESObject[]): void {
    this.printLog(LogLevel.WARN, tag, messages);
  }

  /**
   * 打印ERROR级别日志 - 支持多参数
   * @param tag 日志标签
   * @param messages 日志内容参数列表
   */
  public error(tag: string, ...messages: ESObject[]): void {
    this.printLog(LogLevel.ERROR, tag, messages, true);
  }

  /**
   * 打印FATAL级别日志 - 支持多参数
   * @param tag 日志标签
   * @param messages 日志内容参数列表
   */
  public fatal(tag: string, ...messages: ESObject[]): void {
    this.printLog(LogLevel.FATAL, tag, messages);
  }

  /**
   * 强制打印日志（无视release环境限制）- 支持多参数
   * @param tag 日志标签
   * @param messages 日志内容参数列表
   */
  public infoForce(tag: string, ...messages: ESObject[]): void {
    this.printLog(LogLevel.INFO, tag, messages, true);
  }

  /**
   * 强制打印日志（无视release环境限制）- 支持多参数
   * @param tag 日志标签
   * @param messages 日志内容参数列表
   */
  public errorForce(tag: string, ...messages: ESObject[]): void {
    this.printLog(LogLevel.ERROR, tag, messages, true);
  }

  /**
   * 核心日志打印方法
   * @param level 日志级别
   * @param tag 日志标签
   * @param messages 日志内容参数列表
   * @param force 是否强制打印
   */
  private printLog(
    level: LogLevel,
    tag: string,
    messages: ESObject[],
    force: boolean = false
  ): void {
    // 检查是否需要打印日志（release环境下强制打印）
    if (!force && !this.isForcePrint) {
      return;
    }

    // 将多个参数转换为格式化字符串
    const message = this.formatMessages(messages);

    // 处理长日志换行
    if (message.length <= LogUtil.MAX_LOG_LENGTH) {
      this.printSingleLog(level, tag, `${tag} 👉 ${message}`);
      return;
    }

    // 分割长日志并逐段打印
    let start = 0;
    while (start < message.length) {
      const end = Math.min(start + LogUtil.MAX_LOG_LENGTH, message.length);
      const subMessage = message.substring(start, end);
      this.printSingleLog(level, tag,
        start === 0 ? `${tag} 👉 ${subMessage}` : `    ${subMessage}`
      );
      start = end;
    }
  }

  /**
   * 将多个参数格式化为单个日志字符串
   * @param messages 参数列表
   */
  private formatMessages(messages: ESObject[]): string {
    return messages.map((item: ESObject) => {
      if (typeof item === 'string' || typeof item === 'number' || typeof item === 'boolean') {
        return item.toString();
      } else if (item instanceof Error) {
        return `${item.name}: ${item.message}\n${item.stack || ''}`;
      } else {
        try {
          return JSON.stringify(item);
        } catch (e) {
          return '[Object]';
        }
      }
    }).join(' ');
  }

  /**
   * 打印单条日志
   * @param level 日志级别
   * @param tag 日志标签
   * @param message 日志内容
   */
  private printSingleLog(level: LogLevel, tag: string, message: string): void {
    // 获取调用者信息 - 增强日志可读性
    const callerInfo = this.getCallerInfo();
    const fullTag = `lv-markdown-in ${callerInfo ? `(${callerInfo})` : ''}`;

    // 使用hilog
    switch (level) {
      case LogLevel.INFO: // info
        hilog.info(0x0000, fullTag, `${message}`)
        break
      case LogLevel.WARN: // WARN
        hilog.warn(0x0000, fullTag, `${message}`)
        break
      case LogLevel.DEBUG: // DEBUG
        hilog.debug(0x0000, fullTag, `${message}`)
        break
      case LogLevel.ERROR: // ERROR
        hilog.error(0x0000, fullTag, `${message}`)
        break
      case LogLevel.FATAL: // FATAL
        hilog.fatal(0x0000, fullTag, `${message}`)
        break
    }
  }

  /**
   * 获取调用者信息
   * @returns 调用者类名和方法名
   */
  private getCallerInfo(): string | null {
    try {
      // 通过错误堆栈获取调用者信息
      const error = new Error();
      const stack = error.stack || '';

      // 解析堆栈信息，找到调用者
      const stackLines = stack.split('\n');
      for (let i = 2; i < stackLines.length; i++) {
        const line = stackLines[i].trim();
        if (line.startsWith('at ')) {
          // 提取类名和方法名
          const match = line.match(/at\s+(.+?)\s*\(/);
          if (match && match[1]) {
            const parts = match[1].split('.');
            if (parts.length > 1) {
              const className = parts[parts.length - 2];
              const methodName = parts[parts.length - 1];
              return `${className}.${methodName}`;
            }
          }
        }
      }
    } catch (e) {
      // 忽略获取调用者信息时的异常
    }
    return null;
  }

  public setDebugState(debug: boolean) {
    this.isForcePrint = debug
  }
}

export const Logger = new LogUtil()