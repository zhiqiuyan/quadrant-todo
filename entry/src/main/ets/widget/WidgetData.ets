import { common } from '@kit.AbilityKit';
import { AccountStore } from '../data/AccountStore';
import { SettingsStore } from '../data/SettingsStore';
import { TaskRepository } from '../data/TaskRepository';
import { DateUtil } from '../common/DateUtil';
import { QUADRANTS, QuadrantMeta, TaskItem } from '../model/TaskItem';

/** 卡片清单里的一行，序列化后随卡片数据下发 */
export interface WidgetLineJson {
  q: number;
  t: string;
  l: string;
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
  linesJson: string = '[]';
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

    for (let i = 0; i < tasks.length; i++) {
      const task: TaskItem = tasks[i];
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

    payload.linesJson = JSON.stringify(WidgetData.pickLines(tasks, SettingsStore.current().widgetLines));
    return payload;
  }

  /**
   * 选进卡片的条目：先逾期，再今天到期，再重要，最后其余。
   * 卡片空间有限，把「真的会出问题」的排在最前面。
   */
  private static pickLines(tasks: TaskItem[], max: number): WidgetLineJson[] {
    const ordered: TaskItem[] = [];
    WidgetData.collect(tasks, ordered, 1);
    WidgetData.collect(tasks, ordered, 2);
    WidgetData.collect(tasks, ordered, 3);
    WidgetData.collect(tasks, ordered, 4);

    const lines: WidgetLineJson[] = [];
    for (let i = 0; i < ordered.length && lines.length < max; i++) {
      const task: TaskItem = ordered[i];
      const line: WidgetLineJson = {
        q: task.quadrant,
        t: task.title,
        l: task.dueAt > 0 ? DateUtil.dueLabel(task.dueAt) : ''
      };
      lines.push(line);
    }
    return lines;
  }

  /** stage: 1 逾期 / 2 今日 / 3 重要 / 4 其他 */
  private static collect(tasks: TaskItem[], out: TaskItem[], stage: number): void {
    for (let i = 0; i < tasks.length; i++) {
      const task: TaskItem = tasks[i];
      if (WidgetData.contains(out, task.id)) {
        continue;
      }
      let match: boolean = false;
      if (stage === 1) {
        match = DateUtil.isOverdue(task.dueAt);
      } else if (stage === 2) {
        match = DateUtil.isToday(task.dueAt);
      } else if (stage === 3) {
        match = task.important;
      } else {
        match = true;
      }
      if (match) {
        out.push(task);
      }
    }
  }

  private static contains(list: TaskItem[], id: number): boolean {
    for (let i = 0; i < list.length; i++) {
      if (list[i].id === id) {
        return true;
      }
    }
    return false;
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
