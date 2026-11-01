import { http } from '@kit.NetworkKit';

/** 统一的 HTTP 响应载体 */
export class MsHttpResult {
  status: number = 0;
  body: string = '';
}

/**
 * Microsoft Graph / 登录端点的 HTTP 封装。
 * 每次 send 独立 createHttp，用完即毁，避免连接对象复用带来的状态残留。
 */
export class MsHttp {
  static async send(method: http.RequestMethod, url: string,
    headers: Record<string, string> | undefined, body: string | undefined): Promise<MsHttpResult> {
    const client: http.HttpRequest = http.createHttp();
    const result: MsHttpResult = new MsHttpResult();
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
        throw new Error(`HTTP ${resp.responseCode}：${MsHttp.snippet(result.body)}`);
      }
      return result;
    } catch (err) {
      throw new Error(`网络请求失败：${(err as Error).message}`);
    } finally {
      client.destroy();
    }
  }

  static async getJson(url: string, token: string): Promise<string> {
    const headers: Record<string, string> = {
      'Authorization': `Bearer ${token}`,
      'Accept': 'application/json'
    };
    const resp: MsHttpResult = await MsHttp.send(http.RequestMethod.GET, url, headers, undefined);
    return resp.body;
  }

  static async sendJson(method: http.RequestMethod, url: string, token: string,
    payload: string | undefined): Promise<string> {
    const headers: Record<string, string> = {
      'Authorization': `Bearer ${token}`,
      'Content-Type': 'application/json',
      'Accept': 'application/json'
    };
    const resp: MsHttpResult = await MsHttp.send(method, url, headers, payload);
    return resp.body;
  }

  static async postForm(url: string, form: Record<string, string>): Promise<string> {
    const parts: string[] = [];
    const keys: string[] = Object.keys(form);
    for (let i = 0; i < keys.length; i++) {
      parts.push(`${encodeURIComponent(keys[i])}=${encodeURIComponent(form[keys[i]])}`);
    }
    const headers: Record<string, string> = {
      'Content-Type': 'application/x-www-form-urlencoded'
    };
    const resp: MsHttpResult = await MsHttp.send(http.RequestMethod.POST, url, headers, parts.join('&'));
    return resp.body;
  }

  /** 错误信息截断：响应体可能很长，只留前 160 字符用于 toast */
  private static snippet(body: string): string {
    if (body.length <= 160) {
      return body;
    }
    return `${body.substring(0, 160)}…`;
  }
}
