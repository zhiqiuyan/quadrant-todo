import { calendarManager } from '@kit.CalendarKit';
import { abilityAccessCtrl, common, PermissionRequestResult, Permissions } from '@kit.AbilityKit';
import { PrefStore } from './PrefStore';
import { TaskItem, quadrantMeta } from '../model/TaskItem';

const KEY_ENABLED: string = 'localcal_enabled';
const KEY_MAP: string = 'localcal_map';
const KEY_LAST: string = 'localcal_last';
const KEY_ADOPTED: string = 'localcal_adopted';

const PERMS: Permissions[] = ['ohos.permission.READ_CALENDAR', 'ohos.permission.WRITE_CALENDAR'];

/** 事件描述前缀，用于认领历史写入的事件，避免 app 数据被清后重复创建 */
const DESC_PREFIX: string = 'quad-todo:task=';

/** taskId → 系统日历事件 id 的映射条目 */
class CalMapEntry {
  eventId: number = 0;
  /** 写入时的任务 updatedAt，用于判断是否需要更新 */
  updatedAt: number = 0;
  dueAt: number = 0;
  title: string = '';
  quadrant: number = 0;
}

/** 一次同步的结果统计 */
export class LocalCalResult {
  added: number = 0;
  updated: number = 0;
  removed: number = 0;
  unchanged: number = 0;

  summary(): string {
    const parts: string[] = [];
    if (this.added > 0) {
      parts.push(`新增 ${this.added}`);
    }
    if (this.updated > 0) {
      parts.push(`更新 ${this.updated}`);
    }
    if (this.removed > 0) {
      parts.push(`移除 ${this.removed}`);
    }
    if (parts.length === 0) {
      return `已是最新（${this.unchanged} 条无需变更）`;
    }
    return parts.join(' · ');
  }
}

/**
 * 本机日历服务（HarmonyOS Calendar Kit）：
 * 把带截止日、未完成的任务写成「全天事件」加入系统默认日历账户。
 * 采用「映射对账」：本地保存 taskId → eventId，同步时新增 / 更新 / 删除，
 * 不做全量重建，避免每次同步把用户的日历搅一遍。
 * 只操作本服务自己创建的事件（描述含 quad-todo:task= 前缀），不碰用户其他日程。
 */
export class LocalCalService {
  private static enabled: boolean = false;
  private static lastSync: number = 0;
  private static loaded: boolean = false;

  static async init(context: common.Context): Promise<void> {
    if (LocalCalService.loaded) {
      return;
    }
    await PrefStore.init(context);
    LocalCalService.enabled = PrefStore.getBool(KEY_ENABLED, false);
    LocalCalService.lastSync = PrefStore.getNumber(KEY_LAST, 0);
    LocalCalService.loaded = true;
  }

  static isEnabled(): boolean {
    return LocalCalService.enabled;
  }

  static getLastSync(): number {
    return LocalCalService.lastSync;
  }

  static async setEnabled(on: boolean): Promise<void> {
    LocalCalService.enabled = on;
    await PrefStore.put(KEY_ENABLED, on);
  }

  /** 申请日历读写权限；已授权时系统直接返回，不弹窗 */
  static async ensurePermission(context: common.Context): Promise<boolean> {
    try {
      const atManager: abilityAccessCtrl.AtManager = abilityAccessCtrl.createAtManager();
      const result: PermissionRequestResult =
        await atManager.requestPermissionsFromUser(context, PERMS);
      const results: number[] = result.authResults;
      if (results.length === 0) {
        return false;
      }
      for (let i = 0; i < results.length; i++) {
        if (results[i] !== 0) {
          return false;
        }
      }
      return true;
    } catch (err) {
      return false;
    }
  }

  private static loadMap(): Record<string, CalMapEntry> {
    const raw: string = PrefStore.getString(KEY_MAP, '');
    if (raw.length === 0) {
      return {};
    }
    try {
      return JSON.parse(raw) as Record<string, CalMapEntry>;
    } catch (err) {
      return {};
    }
  }

  private static async saveMap(map: Record<string, CalMapEntry>): Promise<void> {
    await PrefStore.put(KEY_MAP, JSON.stringify(map));
  }

  private static makeEntry(eventId: number, task: TaskItem): CalMapEntry {
    const entry: CalMapEntry = new CalMapEntry();
    entry.eventId = eventId;
    entry.updatedAt = task.updatedAt;
    entry.dueAt = task.dueAt;
    entry.title = task.title;
    entry.quadrant = task.quadrant;
    return entry;
  }

  /** 当天 00:00 的本地时间戳（日历里全天事件按本地零点记） */
  private static dayStart(ms: number): number {
    const d: Date = new Date(ms);
    d.setHours(0, 0, 0, 0);
    return d.getTime();
  }

  private static buildEvent(task: TaskItem, existingId: number): calendarManager.Event {
    const start: number = LocalCalService.dayStart(task.dueAt);
    const event: calendarManager.Event = {
      type: calendarManager.EventType.NORMAL,
      title: `[${quadrantMeta(task.quadrant).name}] ${task.title}`,
      startTime: start,
      endTime: start + 86400000,
      isAllDay: true,
      description: `${DESC_PREFIX}${task.id} · 由「象限待办」自动写入，完成后会自动移除`
    };
    if (existingId > 0) {
      event.id = existingId;
    }
    return event;
  }

  /**
   * 首次同步时认领历史事件：扫描默认账户里描述带前缀的事件，
   * 回填映射（updatedAt 留 0，所以下一轮会覆盖写一次，结果幂等）。
   */
  private static async adopt(cal: calendarManager.Calendar, map: Record<string, CalMapEntry>): Promise<void> {
    try {
      const events: calendarManager.Event[] = await cal.getEvents();
      for (let i = 0; i < events.length; i++) {
        const item: calendarManager.Event = events[i];
        const desc: string = item.description ?? '';
        const at: number = desc.indexOf(DESC_PREFIX);
        if (at < 0 || item.id === undefined) {
          continue;
        }
        const rest: string = desc.substring(at + DESC_PREFIX.length);
        let end: number = rest.length;
        for (let j = 0; j < rest.length; j++) {
          const ch: string = rest.charAt(j);
          if (ch < '0' || ch > '9') {
            end = j;
            break;
          }
        }
        const taskId: string = rest.substring(0, end);
        if (taskId.length === 0 || map[taskId] !== undefined) {
          continue;
        }
        const entry: CalMapEntry = new CalMapEntry();
        entry.eventId = item.id;
        map[taskId] = entry;
      }
    } catch (err) {
      // 读取失败不影响后续写入
    }
    await PrefStore.put(KEY_ADOPTED, true);
  }

  private static hasActive(list: TaskItem[], id: string): boolean {
    for (let i = 0; i < list.length; i++) {
      if (`${list[i].id}` === id) {
        return true;
      }
    }
    return false;
  }

  /**
   * 对账式同步：以「带截止日 + 未完成」的任务为目标集合，
   * 新增 / 更新 / 删除自己创建的事件。单条失败不阻断其余条目。
   */
  static async syncNow(context: common.Context, tasks: TaskItem[]): Promise<LocalCalResult> {
    const granted: boolean = await LocalCalService.ensurePermission(context);
    if (!granted) {
      throw new Error('未获得日历读写权限，请在「设置 → 应用 → 象限待办 → 权限」中允许日历');
    }
    const mgr: calendarManager.CalendarManager = calendarManager.getCalendarManager(context);
    const cal: calendarManager.Calendar = await mgr.getCalendar();

    const map: Record<string, CalMapEntry> = LocalCalService.loadMap();
    if (!PrefStore.getBool(KEY_ADOPTED, false)) {
      await LocalCalService.adopt(cal, map);
    }

    const active: TaskItem[] = [];
    for (let i = 0; i < tasks.length; i++) {
      const t: TaskItem = tasks[i];
      if (t.dueAt > 0 && !t.completed) {
        active.push(t);
      }
    }

    const result: LocalCalResult = new LocalCalResult();
    const keep: Record<string, CalMapEntry> = {};

    // 1. 完成 / 删除 / 清空截止日的任务：删掉对应事件
    const keys: string[] = Object.keys(map);
    for (let i = 0; i < keys.length; i++) {
      const key: string = keys[i];
      const entry: CalMapEntry = map[key];
      if (LocalCalService.hasActive(active, key)) {
        continue;
      }
      try {
        await cal.deleteEvent(entry.eventId);
        result.removed++;
      } catch (err) {
        // 事件已被用户手动删除：视为已清理
      }
    }

    // 2. 新增 / 更新
    for (let i = 0; i < active.length; i++) {
      const t: TaskItem = active[i];
      const key: string = `${t.id}`;
      const entry: CalMapEntry | undefined = map[key];
      if (entry === undefined) {
        try {
          const eventId: number = await cal.addEvent(LocalCalService.buildEvent(t, 0));
          keep[key] = LocalCalService.makeEntry(eventId, t);
          result.added++;
        } catch (err) {
          // 单条写入失败：下一轮重试
        }
        continue;
      }
      if (entry.updatedAt === t.updatedAt && entry.dueAt === t.dueAt &&
        entry.title === t.title && entry.quadrant === t.quadrant) {
        keep[key] = entry;
        result.unchanged++;
        continue;
      }
      try {
        await cal.updateEvent(LocalCalService.buildEvent(t, entry.eventId));
        keep[key] = LocalCalService.makeEntry(entry.eventId, t);
        result.updated++;
      } catch (err) {
        // 事件 id 失效：重新创建
        try {
          const eventId: number = await cal.addEvent(LocalCalService.buildEvent(t, 0));
          keep[key] = LocalCalService.makeEntry(eventId, t);
          result.added++;
        } catch (e2) {
          // 忽略
        }
      }
    }

    await LocalCalService.saveMap(keep);
    LocalCalService.lastSync = Date.now();
    await PrefStore.put(KEY_LAST, LocalCalService.lastSync);
    return result;
  }

  /** 清除本服务写入的全部事件（关闭同步时用），返回删除条数 */
  static async clearAll(context: common.Context): Promise<number> {
    const granted: boolean = await LocalCalService.ensurePermission(context);
    if (!granted) {
      return 0;
    }
    const mgr: calendarManager.CalendarManager = calendarManager.getCalendarManager(context);
    const cal: calendarManager.Calendar = await mgr.getCalendar();
    const map: Record<string, CalMapEntry> = LocalCalService.loadMap();
    const keys: string[] = Object.keys(map);
    let removed: number = 0;
    for (let i = 0; i < keys.length; i++) {
      try {
        await cal.deleteEvent(map[keys[i]].eventId);
        removed++;
      } catch (err) {
        // 已不存在
      }
    }
    await LocalCalService.saveMap({});
    // 重置认领标记：下次同步若发现残留事件会重新认领，而不是重复创建
    await PrefStore.put(KEY_ADOPTED, false);
    return removed;
  }
}
