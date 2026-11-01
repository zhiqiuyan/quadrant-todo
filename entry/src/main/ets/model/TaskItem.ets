/**
 * 数据模型：四象限待办
 *
 * 象限用数字常量表示，与 QUADRANTS 顺序一致：
 *   1 = 重要紧急（左上）
 *   2 = 重要不紧急（右上）
 *   3 = 紧急不重要（左下）
 *   4 = 不重要不紧急（右下）
 */

export const Q1: number = 1;
export const Q2: number = 2;
export const Q3: number = 3;
export const Q4: number = 4;

/** 单条待办。字段全部为可序列化基础类型，便于直接落库。 */
export class TaskItem {
  id: number = 0;
  title: string = '';
  quadrant: number = Q1;
  /** 截止日期时间戳，0 表示未设置 */
  dueAt: number = 0;
  important: boolean = false;
  completed: boolean = false;
  createdAt: number = 0;
  updatedAt: number = 0;

  /** 返回一份浅拷贝，用于构造 UI 层不可变快照 */
  copy(): TaskItem {
    const next: TaskItem = new TaskItem();
    next.id = this.id;
    next.title = this.title;
    next.quadrant = this.quadrant;
    next.dueAt = this.dueAt;
    next.important = this.important;
    next.completed = this.completed;
    next.createdAt = this.createdAt;
    next.updatedAt = this.updatedAt;
    return next;
  }
}

/** 象限的展示元数据 */
export class QuadrantMeta {
  key: number;
  name: string;
  hint: string;

  constructor(key: number, name: string, hint: string) {
    this.key = key;
    this.name = name;
    this.hint = hint;
  }
}

/** 网格顺序：左上、右上、左下、右下 */
export const QUADRANTS: QuadrantMeta[] = [
  new QuadrantMeta(Q1, '重要紧急', '立刻做完，尽量清空'),
  new QuadrantMeta(Q2, '重要不紧急', '主战场，预约进日历'),
  new QuadrantMeta(Q3, '紧急不重要', '委托 / 缩短 / 批量处理'),
  new QuadrantMeta(Q4, '不重要不紧急', '删掉，或只在闲时碰')
];

/** 按 key 取象限元数据，找不到时回落到第一象限 */
export function quadrantMeta(key: number): QuadrantMeta {
  for (let i = 0; i < QUADRANTS.length; i++) {
    if (QUADRANTS[i].key === key) {
      return QUADRANTS[i];
    }
  }
  return QUADRANTS[0];
}
