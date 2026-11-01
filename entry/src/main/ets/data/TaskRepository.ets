import { relationalStore } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { TaskItem } from '../model/TaskItem';

const TABLE: string = 'task';
const COLUMNS: string[] = [
  'id', 'title', 'quadrant', 'due_at', 'important', 'completed', 'created_at', 'updated_at'
];

const SQL_CREATE: string =
  'CREATE TABLE IF NOT EXISTS task (' +
  'id INTEGER PRIMARY KEY AUTOINCREMENT, ' +
  'title TEXT NOT NULL, ' +
  'quadrant INTEGER NOT NULL DEFAULT 1, ' +
  'due_at INTEGER NOT NULL DEFAULT 0, ' +
  'important INTEGER NOT NULL DEFAULT 0, ' +
  'completed INTEGER NOT NULL DEFAULT 0, ' +
  'created_at INTEGER NOT NULL, ' +
  'updated_at INTEGER NOT NULL)';

/**
 * 任务仓储层：封装 relationalStore 的全部读写。
 * 单例 + 懒初始化，页面只需 await TaskRepository.getInstance().init(context) 一次。
 */
export class TaskRepository {
  private static instance: TaskRepository = new TaskRepository();
  private store: relationalStore.RdbStore | undefined = undefined;

  static getInstance(): TaskRepository {
    return TaskRepository.instance;
  }

  async init(context: common.Context): Promise<void> {
    if (this.store !== undefined) {
      return;
    }
    const config: relationalStore.StoreConfig = {
      name: 'quadrant_todo.db',
      securityLevel: relationalStore.SecurityLevel.S1
    };
    let store: relationalStore.RdbStore | undefined = undefined;
    try {
      store = await relationalStore.getRdbStore(context, config);
      await store.executeSql(SQL_CREATE);
    } catch (err) {
      throw new Error(`初始化数据库失败：${(err as Error).message}`);
    }
    this.store = store;
  }

  private db(): relationalStore.RdbStore {
    if (this.store === undefined) {
      throw new Error('数据库尚未初始化，请先调用 init()');
    }
    return this.store;
  }

  private async runQuery(predicates: relationalStore.RdbPredicates): Promise<TaskItem[]> {
    const result: TaskItem[] = [];
    let rs: relationalStore.ResultSet | undefined = undefined;
    try {
      rs = await this.db().query(predicates, COLUMNS);
      while (rs.goToNextRow()) {
        const item: TaskItem = new TaskItem();
        item.id = rs.getLong(rs.getColumnIndex('id'));
        item.title = rs.getString(rs.getColumnIndex('title'));
        item.quadrant = rs.getLong(rs.getColumnIndex('quadrant'));
        item.dueAt = rs.getLong(rs.getColumnIndex('due_at'));
        item.important = rs.getLong(rs.getColumnIndex('important')) === 1;
        item.completed = rs.getLong(rs.getColumnIndex('completed')) === 1;
        item.createdAt = rs.getLong(rs.getColumnIndex('created_at'));
        item.updatedAt = rs.getLong(rs.getColumnIndex('updated_at'));
        result.push(item);
      }
    } catch (err) {
      throw new Error(`查询任务失败：${(err as Error).message}`);
    } finally {
      if (rs !== undefined) {
        try {
          rs.close();
        } catch (closeErr) {
          // 结果集关闭失败不影响已读取的数据
        }
      }
    }
    return result;
  }

  /** 未完成的任务，按创建时间倒序（新任务在上） */
  async listActive(): Promise<TaskItem[]> {
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates(TABLE);
    predicates.equalTo('completed', 0);
    predicates.orderByDesc('created_at');
    return this.runQuery(predicates);
  }

  /** 已完成的任务，按更新时间倒序 */
  async listCompleted(limit: number): Promise<TaskItem[]> {
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates(TABLE);
    predicates.equalTo('completed', 1);
    predicates.orderByDesc('updated_at');
    predicates.limitAs(limit);
    return this.runQuery(predicates);
  }

  /** 指定时间之后完成的任务数量 */
  async countCompletedSince(ts: number): Promise<number> {
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates(TABLE);
    predicates.equalTo('completed', 1);
    predicates.greaterThanOrEqualTo('updated_at', ts);
    let count: number = 0;
    let rs: relationalStore.ResultSet | undefined = undefined;
    try {
      rs = await this.db().query(predicates, ['id']);
      while (rs.goToNextRow()) {
        count++;
      }
    } catch (err) {
      throw new Error(`统计已完成任务失败：${(err as Error).message}`);
    } finally {
      if (rs !== undefined) {
        try {
          rs.close();
        } catch (closeErr) {
          // 结果集关闭失败不影响统计结果
        }
      }
    }
    return count;
  }

  async insert(title: string, quadrant: number, dueAt: number, important: boolean): Promise<number> {
    const now: number = Date.now();
    const values: relationalStore.ValuesBucket = {
      'title': title,
      'quadrant': quadrant,
      'due_at': dueAt,
      'important': important ? 1 : 0,
      'completed': 0,
      'created_at': now,
      'updated_at': now
    };
    try {
      return await this.db().insert(TABLE, values);
    } catch (err) {
      throw new Error(`新增任务失败：${(err as Error).message}`);
    }
  }

  async updateFields(id: number, title: string, quadrant: number, dueAt: number,
    important: boolean): Promise<void> {
    const values: relationalStore.ValuesBucket = {
      'title': title,
      'quadrant': quadrant,
      'due_at': dueAt,
      'important': important ? 1 : 0,
      'updated_at': Date.now()
    };
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates(TABLE);
    predicates.equalTo('id', id);
    try {
      await this.db().update(values, predicates);
    } catch (err) {
      throw new Error(`更新任务失败：${(err as Error).message}`);
    }
  }

  async setCompleted(id: number, completed: boolean): Promise<void> {
    const values: relationalStore.ValuesBucket = {
      'completed': completed ? 1 : 0,
      'updated_at': Date.now()
    };
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates(TABLE);
    predicates.equalTo('id', id);
    try {
      await this.db().update(values, predicates);
    } catch (err) {
      throw new Error(`更新完成状态失败：${(err as Error).message}`);
    }
  }

  async remove(id: number): Promise<void> {
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates(TABLE);
    predicates.equalTo('id', id);
    try {
      await this.db().delete(predicates);
    } catch (err) {
      throw new Error(`删除任务失败：${(err as Error).message}`);
    }
  }

  /** 清理全部已完成任务 */
  async clearCompleted(): Promise<number> {
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates(TABLE);
    predicates.equalTo('completed', 1);
    try {
      return await this.db().delete(predicates);
    } catch (err) {
      throw new Error(`清理已完成任务失败：${(err as Error).message}`);
    }
  }
}
