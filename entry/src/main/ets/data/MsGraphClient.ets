import { http } from '@kit.NetworkKit';
import { PrefStore } from './PrefStore';
import { MsAuthService } from './MsAuthService';
import { MsHttp } from './MsHttp';
import {
  GRAPH_API, MsDateTime, MsList, MsTask, MsTaskPayload,
  RawListPage, RawTaskPage
} from '../model/MsTodo';
import { QUADRANTS } from '../model/TaskItem';

const PAGE_TOP: number = 200;

/**
 * Microsoft Graph To Do 客户端。
 *
 * 四象限与 To Do 清单的映射：每个象限对应一个同名清单
 * （重要紧急 / 重要不紧急 / 紧急不重要 / 不重要不紧急），不存在则自动创建，
 * 清单 id 缓存在 preferences（按本地账号隔离）。用户在微软端重命名清单不影响映射。
 */
export class MsGraphClient {
  /** 象限（1-4）→ 清单 id；ensureLists 之后才有效 */
  private static listIds: string[] = [];

  /** 清单缓存键：ms.{account}.list.q{n} */
  private static listKey(quadrant: number): string {
    return `ms.${MsAuthService.currentAccountId()}.list.q${quadrant}`;
  }

  /** 确保四个象限清单都存在并缓存 id，返回 [q1,q2,q3,q4] 的清单 id */
  static async ensureLists(): Promise<string[]> {
    const ids: string[] = ['', '', '', ''];
    const missing: boolean[] = [false, false, false, false];
    for (let q = 1; q <= 4; q++) {
      const cached: string = PrefStore.getString(MsGraphClient.listKey(q), '');
      if (cached.length > 0) {
        ids[q - 1] = cached;
      } else {
        missing[q - 1] = true;
      }
    }
    if (missing[0] || missing[1] || missing[2] || missing[3]) {
      const lists: MsList[] = await MsGraphClient.listLists();
      for (let q = 1; q <= 4; q++) {
        if (!missing[q - 1]) {
          continue;
        }
        const wanted: string = QUADRANTS[q - 1].name;
        let found: string = '';
        for (let i = 0; i < lists.length; i++) {
          if (lists[i].displayName === wanted) {
            found = lists[i].id;
            break;
          }
        }
        if (found.length === 0) {
          found = await MsGraphClient.createList(wanted);
        }
        ids[q - 1] = found;
        await PrefStore.put(MsGraphClient.listKey(q), found);
      }
    }
    MsGraphClient.listIds = ids;
    return ids;
  }

  static listIdOf(quadrant: number): string {
    if (quadrant >= 1 && quadrant <= 4 && MsGraphClient.listIds.length === 4) {
      return MsGraphClient.listIds[quadrant - 1];
    }
    return '';
  }

  static async listLists(): Promise<MsList[]> {
    const body: string = await MsHttp.getJson(`${GRAPH_API}/me/todo/lists`, await MsAuthService.token());
    const page = JSON.parse(body) as RawListPage;
    return page.value ?? [];
  }

  static async createList(name: string): Promise<string> {
    const payload: Record<string, string> = { 'displayName': name };
    const body: string =
      await MsHttp.sendJson(http.RequestMethod.POST, `${GRAPH_API}/me/todo/lists`,
        await MsAuthService.token(), JSON.stringify(payload));
    const created = JSON.parse(body) as MsList;
    return created.id;
  }

  static async listTasks(listId: string): Promise<MsTask[]> {
    const url: string =
      `${GRAPH_API}/me/todo/lists/${listId}/tasks?$top=${PAGE_TOP}`;
    const body: string = await MsHttp.getJson(url, await MsAuthService.token());
    const page = JSON.parse(body) as RawTaskPage;
    return page.value ?? [];
  }

  static async createTask(listId: string, payload: MsTaskPayload): Promise<string> {
    const url: string = `${GRAPH_API}/me/todo/lists/${listId}/tasks`;
    const body: string =
      await MsHttp.sendJson(http.RequestMethod.POST, url, await MsAuthService.token(), JSON.stringify(payload));
    const created = JSON.parse(body) as MsTask;
    return created.id;
  }

  static async deleteTask(listId: string, taskId: string): Promise<void> {
    const url: string = `${GRAPH_API}/me/todo/lists/${listId}/tasks/${taskId}`;
    await MsHttp.sendJson(http.RequestMethod.DELETE, url, await MsAuthService.token(), undefined);
  }

  /** dueAt（本地零点时间戳）→ Graph dueDateTime；0 返回 null 表示清除 */
  static dueToGraph(dueAt: number): MsDateTime | null {
    if (dueAt <= 0) {
      return null;
    }
    const d: Date = new Date(dueAt);
    const y: number = d.getFullYear();
    const m: number = d.getMonth() + 1;
    const day: number = d.getDate();
    const mm: string = m < 10 ? `0${m}` : `${m}`;
    const dd: string = day < 10 ? `0${day}` : `${day}`;
    const result: MsDateTime = new MsDateTime();
    // 用本地日期的年月日 + UTC 时区：两端展示的都是「这一天」，与时区无关
    result.dateTime = `${y}-${mm}-${dd}T00:00:00.0000000`;
    result.timeZone = 'UTC';
    return result;
  }

  /** Graph dueDateTime → 本地零点时间戳；无则 0 */
  static dueFromGraph(task: MsTask): number {
    if (task.dueDateTime === undefined || task.dueDateTime.dateTime.length < 10) {
      return 0;
    }
    const datePart: string = task.dueDateTime.dateTime.substring(0, 10);
    const parts: string[] = datePart.split('-');
    if (parts.length < 3) {
      return 0;
    }
    const y: number = Number.parseInt(parts[0]);
    const m: number = Number.parseInt(parts[1]);
    const day: number = Number.parseInt(parts[2]);
    if (Number.isNaN(y) || Number.isNaN(m) || Number.isNaN(day)) {
      return 0;
    }
    return new Date(y, m - 1, day).getTime();
  }

  /** Graph lastModifiedDateTime（ISO8601 UTC）→ 本地毫秒时间戳；失败返回 0 */
  static modifiedAt(task: MsTask): number {
    if (task.lastModifiedDateTime.length === 0) {
      return 0;
    }
    const parsed: number = Date.parse(task.lastModifiedDateTime);
    return Number.isNaN(parsed) ? 0 : parsed;
  }
}
