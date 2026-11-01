import { common } from '@kit.AbilityKit';
import { AccountStore } from '../data/AccountStore';
import { SettingsStore } from '../data/SettingsStore';
import { TaskRepository } from '../data/TaskRepository';
import { DateUtil } from '../common/DateUtil';
import { QUADRANTS, QuadrantMeta, TaskItem } from '../model/TaskItem';

/** 象限内任务行，序列化后随卡片数据下发 */
export interface WidgetTaskJson {
  t: string;
  o: boolean;
  d: string;
}

/**
 * 卡片数据载体。字段刻意全部扁平化：卡片端只需 @LocalStorageProp 取值，
 * 复杂结构压成 linesJson 字符串由卡片端解析。
 */
export class WidgetPayload {
  accountName: string = '我';
  total: number = 0;
  doneToday: number = 0;
  q1: number = 0;
  q2: number = 0;
  q3: number = 0;
  q4: number = 0;
  /** 每个象限内的任务标题列表（各象限独立） */
  q1Json: string = '[]';
  q2Json: string = '[]';
  q3Json: string = '[]';
  q4Json: string = '[]';
  /** 大卡片每格显示的行数（来自设置） */
  linesPerQ: number = 3;
  updatedText: string = '';
}

const EMPTY_HINT: string = '还没有待办，点开应用加一条';

/** 卡片数据构建：与主界面共用同一套仓储，保证两边一致 */
export class WidgetData {
  static async build(context: common.Context): Promise<WidgetPayload> {
    const payload: WidgetPayload = new WidgetPayload();
    await AccountStore.init(context);
    await SettingsStore.init(context);
    const repo: TaskRepository = TaskRepository.getInstance();
    await repo.init(context);

    const account = AccountStore.active();
    repo.useAccount(account.id);
    payload.accountName = account.name;

    const tasks: TaskItem[] = await repo.listActive(SettingsStore.current().sortMode);
    payload.total = tasks.length;
    payload.doneToday = await repo.countCompletedSince(DateUtil.todayStart());
    payload.updatedText = WidgetData.clock(Date.now());
    payload.linesPerQ = SettingsStore.current().widgetLines;

    const perQ: TaskItem[][] = [[], [], [], []];
    for (let i = 0; i < tasks.length; i++) {
      const task: TaskItem = tasks[i];
      perQ[task.quadrant - 1].push(task);
      if (task.quadrant === 1) {
        payload.q1++;
      } else if (task.quadrant === 2) {
        payload.q2++;
      } else if (task.quadrant === 3) {
        payload.q3++;
      } else {
        payload.q4++;
      }
    }

    payload.q1Json = JSON.stringify(WidgetData.toJson(perQ[0]));
    payload.q2Json = JSON.stringify(WidgetData.toJson(perQ[1]));
    payload.q3Json = JSON.stringify(WidgetData.toJson(perQ[2]));
    payload.q4Json = JSON.stringify(WidgetData.toJson(perQ[3]));
    return payload;
  }

  /** 象限任务转卡片行：标题 + 逾期标记 + 到期标签 */
  private static toJson(list: TaskItem[]): WidgetTaskJson[] {
    const out: WidgetTaskJson[] = [];
    for (let i = 0; i < list.length && out.length < 5; i++) {
      const task: TaskItem = list[i];
      const item: WidgetTaskJson = {
        t: task.title,
        o: DateUtil.isOverdue(task.dueAt),
        d: task.dueAt > 0 ? DateUtil.dueLabel(task.dueAt) : ''
      };
      out.push(item);
    }
    return out;
  }

  private static clock(ts: number): string {
    const d: Date = new Date(ts);
    const hh: string = d.getHours() < 10 ? `0${d.getHours()}` : `${d.getHours()}`;
    const mm: string = d.getMinutes() < 10 ? `0${d.getMinutes()}` : `${d.getMinutes()}`;
    return `${hh}:${mm} 更新`;
  }

  /** 卡片空态文案（与象限提示区分，避免卡片里长句换行） */
  static emptyHint(): string {
    return EMPTY_HINT;
  }

  /** 象限短名，卡片宽度有限时用 */
  static shortName(quadrant: number): string {
    const meta: QuadrantMeta = QUADRANTS[0];
    for (let i = 0; i < QUADRANTS.length; i++) {
      if (QUADRANTS[i].key === quadrant) {
        return QUADRANTS[i].name;
      }
    }
    return meta.name;
  }
}
