/**
 * Microsoft To Do（Graph API）相关数据类型。
 * 字段名与 Graph 返回保持一致，便于 JSON.parse 直接断言。
 */

export const GRAPH_API: string = 'https://graph.microsoft.com/v1.0';

/** 登录端点：consumers 租户只允许个人微软账号，避免企业租户策略拦截 */
export const MS_AUTH_ENDPOINT: string =
  'https://login.microsoftonline.com/consumers/oauth2/v2.0/authorize';
export const MS_TOKEN_ENDPOINT: string =
  'https://login.microsoftonline.com/consumers/oauth2/v2.0/token';

/** 公共客户端的默认回跳地址（Azure「移动和桌面应用程序」平台自带） */
export const MS_REDIRECT_URI: string =
  'https://login.microsoftonline.com/common/oauth2/nativeclient';

/** 最小权限集：读写待办 + 离线刷新 + 读基本资料 */
export const MS_SCOPES: string = 'offline_access Tasks.ReadWrite User.Read';

export class MsProfile {
  displayName: string = '';
  userPrincipalName: string = '';
}

export class MsList {
  id: string = '';
  displayName: string = '';
}

export class MsDateTime {
  dateTime: string = '';
  timeZone: string = '';
}

export class MsTask {
  id: string = '';
  title: string = '';
  /** notStarted / completed */
  status: string = '';
  /** low / normal / high */
  importance: string = '';
  dueDateTime: MsDateTime | undefined = undefined;
  lastModifiedDateTime: string = '';
}

/** 本地推送到 Graph 的任务载荷；dueDateTime 为 null 表示清除截止日 */
export class MsTaskPayload {
  title: string = '';
  importance: string = 'normal';
  status: string = 'notStarted';
  dueDateTime: MsDateTime | null = null;
}

/** 同步结果，用于界面提示与日志 */
export class MsSyncResult {
  pulled: number = 0;
  pushed: number = 0;
  moved: number = 0;
  deleted: number = 0;
  failed: number = 0;
  message: string = '';
}

/** 远端删除墓碑：本地删了、远端还没删成功的记录 */
export class MsTombstone {
  msId: string = '';
  listId: string = '';
}

/** JSON.parse 断言用的原始响应形状 */
export interface RawListPage {
  value: MsList[];
}

export interface RawTaskPage {
  value: MsTask[];
}

export interface RawTokenResponse {
  access_token: string;
  refresh_token: string;
  expires_in: number;
}

export interface RawProfileResponse {
  displayName: string;
  userPrincipalName: string;
}
