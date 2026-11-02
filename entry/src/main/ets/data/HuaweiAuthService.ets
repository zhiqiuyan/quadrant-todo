import { authentication } from '@kit.AccountKit';
import { bundleManager, common } from '@kit.AbilityKit';
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
 * 关键点：AuthenticationController **必须**用 UIAbilityContext 构造。
 * 构造时不传 context 时，一旦需要拉起华为账号登录/授权页面，系统会直接返回
 * 401（参数校验失败），表现出来就是「登录时发生异常」。
 *
 * 运行前提（一次性配置，缺一时会抛出可读错误）：
 * 1. 在 AppGallery Connect 创建应用并开启「账号服务」（Account Kit）；
 * 2. 把 AGC 分配的 client_id 填进 entry/src/main/module.json5 的 metadata；
 * 3. 应用使用带 Profile 的有效签名（DevEco 自动签名），且证书指纹与 AGC 登记一致。
 */
export class HuaweiAuthService {
  private static readonly KEY_OPEN_ID: string = 'hw_open_id';
  private static readonly KEY_UNION_ID: string = 'hw_union_id';
  private static readonly KEY_NICK: string = 'hw_nick_name';
  private static readonly KEY_AVATAR: string = 'hw_avatar_uri';

  /** 最近一次失败的原始错误码与可读提示，供界面展示排查 */
  static lastCode: number = 0;
  static lastHint: string = '';

  /** 把系统错误码翻译成人话 */
  private static describe(code: number, raw: string): string {
    if (code === 401) {
      return '参数校验失败：授权页面没有拿到界面上下文';
    }
    if (code === 1001500001) {
      return '应用信息校验失败：AGC 应用 / client_id / 签名证书指纹三者可能不一致';
    }
    if (code === 1001500003) {
      return '这台设备还没有登录华为账号，请先在系统「设置」里登录';
    }
    if (code === 1001502014) {
      return '你取消了华为账号授权';
    }
    if (code === 1001502002) {
      return '网络异常，请检查网络后重试';
    }
    const extra: string = raw.length > 0 ? `：${raw}` : '';
    return `未识别的错误${extra}`;
  }

  /** 读 module.json5 里的 client_id 是否已填 */
  static async clientIdConfigured(): Promise<boolean> {
    try {
      const info: bundleManager.BundleInfo = await bundleManager.getBundleInfoForSelf(
        bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_HAP_MODULE);
      const modules: Array<bundleManager.HapModuleInfo> | undefined = info.hapModulesInfo;
      if (modules === undefined) {
        return true;
      }
      for (let i = 0; i < modules.length; i++) {
        const meta: Array<bundleManager.Metadata> | undefined = modules[i].metadata;
        if (meta === undefined) {
          continue;
        }
        for (let j = 0; j < meta.length; j++) {
          if (meta[j].name === 'client_id') {
            const value: string = meta[j].value ?? '';
            if (value.length > 0) {
              return true;
            }
          }
        }
      }
      return false;
    } catch (err) {
      // 读不到元数据时不阻塞登录，交给系统去判断
      return true;
    }
  }

  /**
   * 授权登录：拿到 openID / unionID / 昵称 / 头像。
   * @param context 必须是 UIAbilityContext（不能是 UIExtensionContext）
   */
  static async login(context: common.UIAbilityContext): Promise<HuaweiIdProfile> {
    HuaweiAuthService.lastCode = 0;
    HuaweiAuthService.lastHint = '';
    const provider: authentication.HuaweiIDProvider = new authentication.HuaweiIDProvider();
    const request: authentication.AuthorizationWithHuaweiIDRequest =
      provider.createAuthorizationWithHuaweiIDRequest();
    request.scopes = ['openid', 'profile'];
    request.state = util.generateRandomUUID(true);
    request.forceAuthorization = false;

    const controller: authentication.AuthenticationController =
      new authentication.AuthenticationController(context);
    let response: authentication.AuthorizationWithHuaweiIDResponse;
    try {
      response = await controller.executeRequest(request) as authentication.AuthorizationWithHuaweiIDResponse;
    } catch (err) {
      const be: BusinessError = err as BusinessError;
      const code: number = be.code ?? 0;
      const raw: string = be.message ?? '';
      hilog.error(DOMAIN, TAG, 'login failed: %{public}d %{public}s', code, raw);
      HuaweiAuthService.lastCode = code;
      HuaweiAuthService.lastHint = HuaweiAuthService.describe(code, raw);
      throw new Error(HuaweiAuthService.lastHint);
    }

    const credential: authentication.AuthorizationWithHuaweiIDCredential | undefined = response.data;
    if (credential === undefined || (credential.openID ?? '').length === 0) {
      HuaweiAuthService.lastHint = '系统没有返回华为账号标识，请稍后重试';
      throw new Error(HuaweiAuthService.lastHint);
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

  /** 静默确认本机已登录且授权过的华为账号（不弹窗） */
  static async silentCheck(context: common.UIAbilityContext): Promise<HuaweiIdProfile | undefined> {
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
        new authentication.AuthenticationController(context);
      const response: authentication.LoginWithHuaweiIDResponse =
        await controller.executeRequest(request) as authentication.LoginWithHuaweiIDResponse;
      if (response.data === undefined || (response.data.openID ?? '').length === 0) {
        return undefined;
      }
      return stored;
    } catch (err) {
      return undefined;
    }
  }

  /** 取消授权并清除本地记录 */
  static async logout(context: common.UIAbilityContext): Promise<void> {
    try {
      const provider: authentication.HuaweiIDProvider = new authentication.HuaweiIDProvider();
      const request: authentication.CancelAuthorizationRequest =
        provider.createCancelAuthorizationRequest();
      request.state = util.generateRandomUUID(true);
      const controller: authentication.AuthenticationController =
        new authentication.AuthenticationController(context);
      await controller.executeRequest(request);
    } catch (err) {
      // 取消授权失败不阻断本地清理
      hilog.warn(DOMAIN, TAG, 'cancel auth failed: %{public}s', (err as Error).message);
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
