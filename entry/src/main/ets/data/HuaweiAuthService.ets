import { authentication } from '@kit.AccountKit';
import { util } from '@kit.ArkTS';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { PrefStore } from './PrefStore';

const DOMAIN: number = 0x0000;
const TAG: string = 'HuaweiAuth';

/** 华为账号授权后可用的资料 */
export class HuaweiIdProfile {
  openId: string = '';
  unionId: string = '';
  nickName: string = '';
  avatarUri: string = '';
}

/**
 * 华为账号登录（Account Kit）。
 *
 * 运行前提（一次性配置，缺一时会抛出可读错误）：
 * 1. 在 AppGallery Connect 创建应用并开启「账号服务」（Account Kit）；
 * 2. 把 AGC 分配的 client_id 填进 entry/src/main/module.json5 的 metadata；
 * 3. 应用必须使用带 Profile 的有效签名（DevEco 自动签名即可）。
 */
export class HuaweiAuthService {
  private static readonly KEY_OPEN_ID: string = 'hw_open_id';
  private static readonly KEY_UNION_ID: string = 'hw_union_id';
  private static readonly KEY_NICK: string = 'hw_nick_name';
  private static readonly KEY_AVATAR: string = 'hw_avatar_uri';

  /** 用授权接口（而非静默登录）拿到昵称与头像 */
  static async login(): Promise<HuaweiIdProfile> {
    const provider: authentication.HuaweiIDProvider = new authentication.HuaweiIDProvider();
    const request: authentication.AuthorizationWithHuaweiIDRequest =
      provider.createAuthorizationWithHuaweiIDRequest();
    request.scopes = ['openid', 'profile'];
    request.state = util.generateRandomUUID(true);

    const controller: authentication.AuthenticationController =
      new authentication.AuthenticationController();
    let response: authentication.AuthorizationWithHuaweiIDResponse;
    try {
      response = await controller.executeRequest(request) as authentication.AuthorizationWithHuaweiIDResponse;
    } catch (err) {
      const be: BusinessError = err as BusinessError;
      const code: number = be.code ?? 0;
      hilog.error(DOMAIN, TAG, 'login failed: %{public}d %{public}s', code, be.message ?? '');
      if (code === 1001500001) {
        throw new Error('应用未在 AGC 配置 client_id，无法使用华为账号（见 README「华为账号与云备份」）');
      }
      if (code === 1001502014 || code === 1001500003) {
        throw new Error('AGC 未开通「账号服务」或 scopes 未申请');
      }
      throw new Error(`华为账号授权失败：${(err as Error).message}`);
    }

    const credential = response.data;
    if (credential === undefined || credential.openID === undefined) {
      throw new Error('未获得华为账号授权');
    }

    const profile: HuaweiIdProfile = new HuaweiIdProfile();
    profile.openId = credential.openID ?? '';
    profile.unionId = credential.unionID ?? '';
    profile.nickName = credential.nickName ?? '';
    profile.avatarUri = credential.avatarUri ?? '';

    await PrefStore.put(HuaweiAuthService.KEY_OPEN_ID, profile.openId);
    await PrefStore.put(HuaweiAuthService.KEY_UNION_ID, profile.unionId);
    await PrefStore.put(HuaweiAuthService.KEY_NICK, profile.nickName);
    await PrefStore.put(HuaweiAuthService.KEY_AVATAR, profile.avatarUri);
    return profile;
  }

  /** 静默查询本机已登录且授权过的华为账号（不弹窗） */
  static async silentCheck(): Promise<HuaweiIdProfile | undefined> {
    const stored: HuaweiIdProfile | undefined = HuaweiAuthService.stored();
    if (stored === undefined) {
      return undefined;
    }
    try {
      const provider: authentication.HuaweiIDProvider = new authentication.HuaweiIDProvider();
      const request: authentication.LoginWithHuaweiIDRequest =
        provider.createLoginWithHuaweiIDRequest();
      request.state = util.generateRandomUUID(true);
      const controller: authentication.AuthenticationController =
        new authentication.AuthenticationController();
      const response: authentication.LoginWithHuaweiIDResponse =
        await controller.executeRequest(request) as authentication.LoginWithHuaweiIDResponse;
      if (response.data === undefined || response.data.openID === undefined) {
        return undefined;
      }
      return stored;
    } catch (err) {
      return undefined;
    }
  }

  /** 取消授权并清除本地记录 */
  static async logout(): Promise<void> {
    try {
      const provider: authentication.HuaweiIDProvider = new authentication.HuaweiIDProvider();
      const request: authentication.CancelAuthorizationRequest =
        provider.createCancelAuthorizationRequest();
      request.state = util.generateRandomUUID(true);
      const controller: authentication.AuthenticationController =
        new authentication.AuthenticationController();
      await controller.executeRequest(request);
    } catch (err) {
      // 取消授权失败不阻断本地清理
    }
    await PrefStore.put(HuaweiAuthService.KEY_OPEN_ID, '');
    await PrefStore.put(HuaweiAuthService.KEY_UNION_ID, '');
    await PrefStore.put(HuaweiAuthService.KEY_NICK, '');
    await PrefStore.put(HuaweiAuthService.KEY_AVATAR, '');
  }

  static loggedIn(): boolean {
    return PrefStore.getString(HuaweiAuthService.KEY_OPEN_ID, '').length > 0;
  }

  static stored(): HuaweiIdProfile | undefined {
    const openId: string = PrefStore.getString(HuaweiAuthService.KEY_OPEN_ID, '');
    if (openId.length === 0) {
      return undefined;
    }
    const profile: HuaweiIdProfile = new HuaweiIdProfile();
    profile.openId = openId;
    profile.unionId = PrefStore.getString(HuaweiAuthService.KEY_UNION_ID, '');
    profile.nickName = PrefStore.getString(HuaweiAuthService.KEY_NICK, '');
    profile.avatarUri = PrefStore.getString(HuaweiAuthService.KEY_AVATAR, '');
    return profile;
  }

  /** 云备份路径用：稳定的用户命名空间 */
  static cloudNamespace(): string {
    const openId: string = PrefStore.getString(HuaweiAuthService.KEY_OPEN_ID, '');
    if (openId.length > 0) {
      return `hw-${openId.substring(0, 12)}`;
    }
    return '';
  }
}
