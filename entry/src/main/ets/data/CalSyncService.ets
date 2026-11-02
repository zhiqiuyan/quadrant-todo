import { util } from '@kit.ArkTS';
import { http } from '@kit.NetworkKit';
import { common } from '@kit.AbilityKit';
import { TaskRepository } from './TaskRepository';
import { TaskItem, quadrantMeta } from '../model/TaskItem';
import { PrefStore } from './PrefStore';
import { MsHttp } from './MsHttp';

const KEY_ENABLED: string = 'cal_enabled';
const KEY_OWNER: string = 'cal_owner';
const KEY_REPO: string = 'cal_repo';
const KEY_TOKEN: string = 'cal_token';
const KEY_PATH_ID: string = 'cal_path_id';
const KEY_LAST_SYNC: string = 'cal_last_sync';

const GITEE_API: string = 'https://gitee.com/api/v5';

/** Gitee contents API 响应（只用到的字段） */
interface GiteeFileResp {
  sha?: string;
  content?: string;
}

/** 日历订阅配置快照 */
export class CalSyncConfig {
  enabled: boolean = false;
  /** Gitee 用户名 / 组织名 */
  owner: string = '';
  /** 仓库名（须公开） */
  repo: string = '';
  /** Gitee 私人令牌（需 projects 权限） */
  token: string = '';
  /** 订阅文件随机路径段，防止猜测 */
  pathId: string = '';
  /** 上次成功同步时间戳，0 表示从未 */
  lastSync: number = 0;

  copy(): CalSyncConfig {
    const next: CalSyncConfig = new CalSyncConfig();
    next.enabled = this.enabled;
    next.owner = this.owner;
    next.repo = this.repo;
    next.token = this.token;
    next.pathId = this.pathId;
    next.lastSync = this.lastSync;
    return next;
  }
}

/**
 * 日历订阅服务：
 * 把带截止日、未完成的任务生成 ICS 日历（全天事件），推送到 Gitee 仓库；
 * 苹果日历 / Google 日历等以「订阅日历」方式添加 raw 链接即可看到。
 * 文件路径含随机段（cal-<pathId>.ics），知道完整地址才能访问。
 */
export class CalSyncService {
  private static cfg: CalSyncConfig = new CalSyncConfig();
  private static loaded: boolean = false;

  static async init(context: common.Context): Promise<void> {
    if (CalSyncService.loaded) {
      return;
    }
    await PrefStore.init(context);
    const next: CalSyncConfig = new CalSyncConfig();
    next.enabled = PrefStore.getBool(KEY_ENABLED, false);
    next.owner = PrefStore.getString(KEY_OWNER, '');
    next.repo = PrefStore.getString(KEY_REPO, '');
    next.token = PrefStore.getString(KEY_TOKEN, '');
    next.pathId = PrefStore.getString(KEY_PATH_ID, '');
    next.lastSync = PrefStore.getNumber(KEY_LAST_SYNC, 0);
    CalSyncService.cfg = next;
    CalSyncService.loaded = true;
  }

  static getConfig(): CalSyncConfig {
    return CalSyncService.cfg.copy();
  }

  static async saveConfig(next: CalSyncConfig): Promise<void> {
    CalSyncService.cfg = next.copy();
    await PrefStore.put(KEY_ENABLED, next.enabled);
    await PrefStore.put(KEY_OWNER, next.owner);
    await PrefStore.put(KEY_REPO, next.repo);
    await PrefStore.put(KEY_TOKEN, next.token);
    await PrefStore.put(KEY_PATH_ID, next.pathId);
    await PrefStore.put(KEY_LAST_SYNC, next.lastSync);
  }

  /** 首次启用时生成随机路径段（16 位十六进制） */
  static newCandidatePathId(): string {
    const now: number = Date.now();
    let hex: string = '';
    for (let i = 0; i < 4; i++) {
      hex += Math.floor(Math.random() * 0xFFFF).toString(16).padStart(4, '0');
    }
    return `${hex}${now.toString(16).padStart(8, '0')}`.substring(0, 24);
  }

  /** 订阅链接（Gitee raw，公开仓库免登录可读） */
  static subscriptionUrl(cfg: CalSyncConfig): string {
    if (cfg.owner.length === 0 || cfg.repo.length === 0 || cfg.pathId.length === 0) {
      return '';
    }
    return `https://gitee.com/${cfg.owner}/${cfg.repo}/raw/master/quadrant-todo/cal-${cfg.pathId}.ics`;
  }

  private static filePath(cfg: CalSyncConfig): string {
    return `quadrant-todo/cal-${cfg.pathId}.ics`;
  }

  /** RFC 5545 文本转义 */
  private static escapeText(text: string): string {
    return text
      .replace(/\\/g, '\\\\')
      .replace(/;/g, '\\;')
      .replace(/,/g, '\\,')
      .replace(/\r?\n/g, '\\n');
  }

  /** 毫秒时间戳 → 本地日期 yyyymmdd */
  private static dateNumber(ms: number): string {
    const d: Date = new Date(ms);
    const m: string = (d.getMonth() + 1).toString().padStart(2, '0');
    const day: string = d.getDate().toString().padStart(2, '0');
    return `${d.getFullYear()}${m}${day}`;
  }

  /** 毫秒时间戳 → UTC 基本格式 yyyymmddThhmmssZ */
  private static utcStamp(ms: number): string {
    const d: Date = new Date(ms);
    const p = (n: number, w: number = 2): string => n.toString().padStart(w, '0');
    return `${d.getUTCFullYear()}${p(d.getUTCMonth() + 1)}${p(d.getUTCDate())}` +
      `T${p(d.getUTCHours())}${p(d.getUTCMinutes())}${p(d.getUTCSeconds())}Z`;
  }

  /** 由任务列表构建 ICS 文本（全天事件，CRLF 行尾） */
  static buildIcs(tasks: TaskItem[]): string {
    const lines: string[] = [];
    lines.push('BEGIN:VCALENDAR');
    lines.push('VERSION:2.0');
    lines.push('PRODID:-//quadrant-todo//HarmonyOS//CN');
    lines.push('CALSCALE:GREGORIAN');
    lines.push('METHOD:PUBLISH');
    lines.push('X-WR-CALNAME:象限待办');
    lines.push('X-WR-CALDESC:来自象限待办 APP 的任务截止日');
    lines.push('REFRESH-INTERVAL;VALUE=DURATION:PT30M');
    lines.push('X-PUBLISHED-TTL:PT30M');
    const stamp: string = CalSyncService.utcStamp(Date.now());
    for (let i = 0; i < tasks.length; i++) {
      const t: TaskItem = tasks[i];
      if (t.dueAt <= 0 || t.completed) {
        continue;
      }
      const start: string = CalSyncService.dateNumber(t.dueAt);
      // 全天事件 DTEND 为排他结束日：次日
      const endMs: number = t.dueAt + 86400000;
      const end: string = CalSyncService.dateNumber(endMs);
      lines.push('BEGIN:VEVENT');
      lines.push(`UID:quad-${t.id}-${t.updatedAt}@quadrant-todo`);
      lines.push(`DTSTAMP:${stamp}`);
      lines.push(`DTSTART;VALUE=DATE:${start}`);
      lines.push(`DTEND;VALUE=DATE:${end}`);
      lines.push(`SUMMARY:[${CalSyncService.escapeText(quadrantMeta(t.quadrant).name)}] ${CalSyncService.escapeText(t.title)}`);
      lines.push(`DESCRIPTION:来自象限待办 APP，截止日 ${start.substring(0, 4)}-${start.substring(4, 6)}-${start.substring(6, 8)}`);
      lines.push('TRANSP:TRANSPARENT');
      lines.push('END:VEVENT');
    }
    lines.push('END:VCALENDAR');
    return lines.join('\r\n');
  }

  static ready(cfg: CalSyncConfig): boolean {
    return cfg.enabled && cfg.owner.length > 0 && cfg.repo.length > 0 &&
      cfg.token.length > 0 && cfg.pathId.length > 0;
  }

  /** 立即同步：构建 ICS → 与云端内容比对 → 有变化才提交（避免 commit 刷屏） */
  static async syncNow(): Promise<void> {
    const cfg: CalSyncConfig = CalSyncService.cfg;
    if (!CalSyncService.ready(cfg)) {
      throw new Error('日历订阅未配置完整（需开启并填写 Gitee 用户名 / 仓库 / 令牌）');
    }
    const repo: TaskRepository = TaskRepository.getInstance();
    const tasks: TaskItem[] = await repo.listAll();
    const ics: string = CalSyncService.buildIcs(tasks);
    const encoder: util.TextEncoder = new util.TextEncoder();
    const bytes: Uint8Array = encoder.encodeInto(ics);
    const helper: util.Base64Helper = new util.Base64Helper();
    const content: string = helper.encodeToStringSync(bytes);

    const path: string = encodeURIComponent(CalSyncService.filePath(cfg));
    const fileUrl: string =
      `${GITEE_API}/repos/${cfg.owner}/${cfg.repo}/contents/${path}?access_token=${cfg.token}`;

    // 读取远端：存在则比对 sha 与内容，内容相同则跳过提交
    let sha: string = '';
    let remoteContent: string = '';
    try {
      const resp: string = (await MsHttp.send(http.RequestMethod.GET, fileUrl, undefined, undefined)).body;
      const info: GiteeFileResp = JSON.parse(resp) as GiteeFileResp;
      sha = info.sha ?? '';
      remoteContent = (info.content ?? '').replace(/\n/g, '');
    } catch (err) {
      // 404 = 文件尚未创建，正常走新建
      sha = '';
    }
    if (sha.length > 0 && remoteContent === content) {
      await CalSyncService.markSynced();
      return;
    }

    const bodyObj: Record<string, string> = {
      'access_token': cfg.token,
      'content': content,
      'message': 'sync: 象限待办日历更新'
    };
    if (sha.length > 0) {
      bodyObj['sha'] = sha;
    }
    await MsHttp.send(http.RequestMethod.PUT, fileUrl, undefined, JSON.stringify(bodyObj));
    await CalSyncService.markSynced();
  }

  private static async markSynced(): Promise<void> {
    CalSyncService.cfg.lastSync = Date.now();
    await PrefStore.put(KEY_LAST_SYNC, CalSyncService.cfg.lastSync);
  }
}
