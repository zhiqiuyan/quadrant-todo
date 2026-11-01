import { PrefStore } from './PrefStore';
import { MsHttp } from './MsHttp';
import { challengeOf, newCodeVerifier } from '../common/Pkce';
import {
  MS_AUTH_ENDPOINT, MS_REDIRECT_URI, MS_SCOPES, MS_TOKEN_ENDPOINT,
  RawProfileResponse, RawTokenResponse
} from '../model/MsTodo';
import { GRAPH_API } from '../model/MsTodo';

/** Client ID 是设备级配置（一个 Azure 应用可服务所有本地账号） */
const KEY_CLIENT_ID: string = 'ms_client_id';

/** 登录流程中的一次性数据，只存内存 */
export class MsLoginFlow {
  verifier: string = '';
  state: string = '';
}

/**
 * Microsoft OAuth 2.0 授权码 + PKCE 流程与 token 生命周期管理。
 *
 * 关键设计：
 * - token / 刷新 token 按本地账号隔离（前缀 ms.{accountId}.），不同本地账号可绑不同微软账号；
 * - Client ID 由用户在设置里填自己的 Azure 应用注册（公共客户端），不内置他人 ID；
 * - access token 过期前 60 秒即视为失效，自动用 refresh token 换新。
 */
export class MsAuthService {
  private static accountId: number = 1;
  private static flow: MsLoginFlow = new MsLoginFlow();

  /** 运行期切换数据维度：之后所有 token 读写都指向该本地账号 */
  static bind(accountId: number): void {
    MsAuthService.accountId = accountId;
  }

  static currentAccountId(): number {
    return MsAuthService.accountId;
  }

  private static key(suffix: string): string {
    return `ms.${MsAuthService.accountId}.${suffix}`;
  }

  static clientId(): string {
    return PrefStore.getString(KEY_CLIENT_ID, '');
  }

  static async setClientId(id: string): Promise<void> {
    await PrefStore.put(KEY_CLIENT_ID, id.trim());
  }

  static hasClientId(): boolean {
    return MsAuthService.clientId().length > 0;
  }

  static connected(): boolean {
    return PrefStore.getString(MsAuthService.key('refresh_token'), '').length > 0;
  }

  static profileName(): string {
    return PrefStore.getString(MsAuthService.key('display_name'), '');
  }

  static profileEmail(): string {
    return PrefStore.getString(MsAuthService.key('upn'), '');
  }

  static async setAutoSync(on: boolean): Promise<void> {
    await PrefStore.put(MsAuthService.key('auto_sync'), on);
  }

  static autoSync(): boolean {
    return PrefStore.getBool(MsAuthService.key('auto_sync'), true);
  }

  static async setLastSync(text: string): Promise<void> {
    await PrefStore.put(MsAuthService.key('last_sync'), text);
  }

  static lastSync(): string {
    return PrefStore.getString(MsAuthService.key('last_sync'), '');
  }

  /**
   * 生成授权页地址。verifier/state 只存内存；
   * 授权完成后必须回到同一进程完成 token 交换（应用内 Web 登录满足这一点）。
   */
  static authorizeUrl(): string {
    MsAuthService.flow.verifier = newCodeVerifier();
    MsAuthService.flow.state = challengeOf(`${Date.now()}-${MsAuthService.flow.verifier}`)
      .substring(0, 22);
    const query: string[] = [
      'client_id=' + encodeURIComponent(MsAuthService.clientId()),
      'response_type=code',
      'redirect_uri=' + encodeURIComponent(MS_REDIRECT_URI),
      'response_mode=query',
      'scope=' + encodeURIComponent(MS_SCOPES),
      'state=' + encodeURIComponent(MsAuthService.flow.state),
      'code_challenge=' + encodeURIComponent(challengeOf(MsAuthService.flow.verifier)),
      'code_challenge_method=S256',
      'prompt=select_account'
    ];
    return `${MS_AUTH_ENDPOINT}?${query.join('&')}`;
  }

  /** 校验回跳地址是否是授权回调（供 Web 拦截器快速判断） */
  static isRedirectUrl(url: string): boolean {
    return url.startsWith(MS_REDIRECT_URI);
  }

  /** 从回跳 URL 提取 code 并完成 token 交换；失败抛错 */
  static async completeLogin(url: string): Promise<void> {
    const code: string = MsAuthService.queryParam(url, 'code');
    const state: string = MsAuthService.queryParam(url, 'state');
    if (code.length === 0) {
      const error: string = MsAuthService.queryParam(url, 'error');
      throw new Error(error.length > 0 ? `授权失败：${error}` : '授权回调缺少 code');
    }
    if (state !== MsAuthService.flow.state) {
      throw new Error('授权状态校验失败，请重试');
    }
    await MsAuthService.exchange(code, MsAuthService.flow.verifier);
    MsAuthService.flow.verifier = '';
    MsAuthService.flow.state = '';

    const name: string = PrefStore.getString(MsAuthService.key('display_name'), '');
    if (name.length === 0) {
      await MsAuthService.fetchAndStoreProfile();
    }
  }

  private static queryParam(url: string, name: string): string {
    const qIndex: number = url.indexOf('?');
    if (qIndex < 0) {
      return '';
    }
    const query: string = url.substring(qIndex + 1);
    const pairs: string[] = query.split('&');
    for (let i = 0; i < pairs.length; i++) {
      const kv: string[] = pairs[i].split('=');
      if (kv.length >= 2 && kv[0] === name) {
        return decodeURIComponent(kv[1]);
      }
    }
    return '';
  }

  private static async exchange(code: string, verifier: string): Promise<void> {
    const form: Record<string, string> = {
      'client_id': MsAuthService.clientId(),
      'grant_type': 'authorization_code',
      'code': code,
      'redirect_uri': MS_REDIRECT_URI,
      'code_verifier': verifier,
      'scope': MS_SCOPES
    };
    await MsAuthService.storeTokenResponse(form);
  }

  /** 取可用 access token；临期或失效时自动刷新 */
  static async token(): Promise<string> {
    const expiresAt: number = PrefStore.getNumber(MsAuthService.key('expires_at'), 0);
    let access: string = PrefStore.getString(MsAuthService.key('access_token'), '');
    if (access.length > 0 && Date.now() < expiresAt) {
      return access;
    }
    const refresh: string = PrefStore.getString(MsAuthService.key('refresh_token'), '');
    if (refresh.length === 0) {
      throw new Error('尚未连接微软账号');
    }
    access = await MsAuthService.refresh(refresh);
    return access;
  }

  private static async refresh(refreshToken: string): Promise<string> {
    const form: Record<string, string> = {
      'client_id': MsAuthService.clientId(),
      'grant_type': 'refresh_token',
      'refresh_token': refreshToken,
      'scope': MS_SCOPES
    };
    await MsAuthService.storeTokenResponse(form);
    return PrefStore.getString(MsAuthService.key('access_token'), '');
  }

  private static async storeTokenResponse(form: Record<string, string>): Promise<void> {
    const body: string = await MsHttp.postForm(MS_TOKEN_ENDPOINT, form);
    const parsed = JSON.parse(body) as RawTokenResponse;
    if (parsed.access_token === undefined || parsed.access_token.length === 0) {
      throw new Error('token 响应缺少 access_token');
    }
    // 提前 60 秒过期，规避时钟偏差
    await PrefStore.put(MsAuthService.key('access_token'), parsed.access_token);
    await PrefStore.put(MsAuthService.key('expires_at'), Date.now() + parsed.expires_in * 1000 - 60000);
    if (parsed.refresh_token !== undefined && parsed.refresh_token.length > 0) {
      await PrefStore.put(MsAuthService.key('refresh_token'), parsed.refresh_token);
    }
  }

  private static async fetchAndStoreProfile(): Promise<void> {
    const body: string = await MsHttp.getJson(`${GRAPH_API}/me`, await MsAuthService.token());
    const parsed = JSON.parse(body) as RawProfileResponse;
    await PrefStore.put(MsAuthService.key('display_name'), parsed.displayName ?? '');
    await PrefStore.put(MsAuthService.key('upn'), parsed.userPrincipalName ?? '');
  }

  /** 断开连接：清除该本地账号的全部微软凭据 */
  static async disconnect(): Promise<void> {
    const suffixes: string[] = ['access_token', 'refresh_token', 'expires_at', 'display_name', 'upn', 'last_sync'];
    for (let i = 0; i < suffixes.length; i++) {
      await PrefStore.remove(MsAuthService.key(suffixes[i]));
    }
  }
}
