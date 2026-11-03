import { http } from '@kit.NetworkKit';

/** 统一的 HTTP 响应载体 */
export class HttpResult {
  status: number = 0;
  body: string = '';
}

/**
 * 轻量 HTTP 封装（日历订阅等外发请求使用）。
 * 每次 send 独立 createHttp，用完即毁，避免连接对象复用带来的状态残留。
 */
export class HttpUtil {
  static async send(method: http.RequestMethod, url: string,
    headers: Record<string, string> | undefined, body: string | undefined): Promise<HttpResult> {
    const client: http.HttpRequest = http.createHttp();
    const result: HttpResult = new HttpResult();
    try {
      const options: http.HttpRequestOptions = {
        method: method,
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: 20000,
        readTimeout: 30000
      };
      if (headers !== undefined) {
        options.header = headers;
      }
      if (body !== undefined) {
        options.extraData = body;
      }
      const resp: http.HttpResponse = await client.request(url, options);
      result.status = resp.responseCode;
      const raw: string | Object | ArrayBuffer = resp.result;
      result.body = typeof raw === 'string' ? raw : '';
      if (resp.responseCode < 200 || resp.responseCode >= 300) {
        throw new Error(`HTTP ${resp.responseCode}：${HttpUtil.snippet(result.body)}`);
      }
      return result;
    } catch (err) {
      throw new Error(`网络请求失败：${(err as Error).message}`);
    } finally {
      client.destroy();
    }
  }

  /** 错误信息截断：响应体可能很长，只留前 160 字符用于提示 */
  private static snippet(body: string): string {
    if (body.length <= 160) {
      return body;
    }
    return `${body.substring(0, 160)}…`;
  }
}
