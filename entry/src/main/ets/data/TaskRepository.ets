import { relationalStore } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { TaskItem } from '../model/TaskItem';
import { SORT_DUE, SORT_IMPORTANT } from '../model/AppSettings';

const TABLE: string = 'task';
const COLUMNS: string[] = [
  'id', 'account_id', 'title', 'quadrant', 'due_at', 'important', 'completed', 'created_at', 'updated_at'
];

const SQL_CREATE: string =
  'CREATE TABLE IF NOT EXISTS task (' +
  'id INTEGER PRIMARY KEY AUTOINCREMENT, ' +
  'account_id INTEGER NOT NULL DEFAULT 1, ' +
  'title TEXT NOT NULL, ' +
  'quadrant INTEGER NOT NULL DEFAULT 1, ' +
  'due_at INTEGER NOT NULL DEFAULT 0, ' +
  'important INTEGER NOT NULL DEFAULT 0, ' +
  'completed INTEGER NOT NULL DEFAULT 0, ' +
  'created_at INTEGER NOT NULL, ' +
  'updated_at INTEGER NOT NULL)';

/** 旧版本（无 account_id）升级用；列已存在时会抛错，忽略即可 */
const SQL_MIGRATE_ACCOUNT: string = 'ALTER TABLE task ADD COLUMN account_id INTEGER NOT NULL DEFAULT 1';
const SQL_INDEX_ACCOUNT: string = 'CREATE INDEX IF NOT EXISTS idx_task_account ON task(account_id, completed)';

/**
 * 任务仓储层：封装 relationalStore 的全部读写。
 * 单例 + 懒初始化；账号切换通过 useAccount() 设置当前维度的 account_id。
 */
export class TaskRepository {
  private static instance: TaskRepository = new TaskRepository();
  private store: relationalStore.RdbStore | undefined = undefined;
  private accountId: number = 1;

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
      try {
        await store.executeSql(SQL_MIGRATE_ACCOUNT);
      } catch (migrateErr) {
        // 列已存在：说明是新库或已完成迁移，无需处理
      }
      await store.executeSql(SQL_INDEX_ACCOUNT);
    } catch (err) {
      throw new Error(`初始化数据库失败：${(err as Error).message}`);
    }
    this.store = store;
  }

  /** 切换数据维度：之后所有读写都只针对该账号 */
  useAccount(accountId: number): void {
    this.accountId = accountId;
  }

  currentAccountId(): number {
    return this.accountId;
  }

  private db(): relationalStore.RdbStore {
    if (this.store === undefined) {
      throw new Error('数据库尚未初始化，请先调用 init()');
    }
    return this.store;
  }

  /** 当前账号维度的谓词，避免每条查询重复写过滤条件 */
  private predicate(): relationalStore.RdbPredicates {
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates(TABLE);
    predicates.equalTo('account_id', this.accountId);
    return predicates;
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

  /**
   * 未完成的任务。
   * sortMode：0 最新创建 / 1 截止优先 / 2 重要优先。
   * 「截止优先」把有截止日的排前面，无截止日的按创建时间兜底。
   */
  async listActive(sortMode: number): Promise<TaskItem[]> {
    const predicates: relationalStore.RdbPredicates = this.predicate();
    predicates.equalTo('completed', 0);
    predicates.orderByDesc('created_at');
    const list: TaskItem[] = await this.runQuery(predicates);
    if (sortMode === SORT_DUE) {
      list.sort((a: TaskItem, b: TaskItem) => {
        const aHas: boolean = a.dueAt > 0;
        const bHas: boolean = b.dueAt > 0;
        if (aHas !== bHas) {
          return aHas ? -1 : 1;
        }
        if (aHas && a.dueAt !== b.dueAt) {
          return a.dueAt < b.dueAt ? -1 : 1;
        }
        return b.createdAt - a.createdAt;
      });
    } else if (sortMode === SORT_IMPORTANT) {
      list.sort((a: TaskItem, b: TaskItem) => {
        if (a.important !== b.important) {
          return a.important ? -1 : 1;
        }
        return b.createdAt - a.createdAt;
      });
    }
    return list;
  }

  /** 已完成的任务，按更新时间倒序 */
  async listCompleted(limit: number): Promise<TaskItem[]> {
    const predicates: relationalStore.RdbPredicates = this.predicate();
    predicates.equalTo('completed', 1);
    predicates.orderByDesc('updated_at');
    predicates.limitAs(limit);
    return this.runQuery(predicates);
  }

  /** 指定时间之后完成的任务数量 */
  async countCompletedSince(ts: number): Promise<number> {
    const predicates: relationalStore.RdbPredicates = this.predicate();
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
      'account_id': this.accountId,
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
    const predicates: relationalStore.RdbPredicates = this.predicate();
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
    const predicates: relationalStore.RdbPredicates = this.predicate();
    predicates.equalTo('id', id);
    try {
      await this.db().update(values, predicates);
    } catch (err) {
      throw new Error(`更新完成状态失败：${(err as Error).message}`);
    }
  }

  async remove(id: number): Promise<void> {
    const predicates: relationalStore.RdbPredicates = this.predicate();
    predicates.equalTo('id', id);
    try {
      await this.db().delete(predicates);
    } catch (err) {
      throw new Error(`删除任务失败：${(err as Error).message}`);
    }
  }

  /** 清理当前账号的全部已完成任务 */
  async clearCompleted(): Promise<number> {
    const predicates: relationalStore.RdbPredicates = this.predicate();
    predicates.equalTo('completed', 1);
    try {
      return await this.db().delete(predicates);
    } catch (err) {
      throw new Error(`清理已完成任务失败：${(err as Error).message}`);
    }
  }

  /** 清空当前账号的全部任务（含未完成），设置面板里的「清空本账号」 */
  async clearAll(): Promise<number> {
    const predicates: relationalStore.RdbPredicates = this.predicate();
    try {
      return await this.db().delete(predicates);
    } catch (err) {
      throw new Error(`清空任务失败：${(err as Error).message}`);
    }
  }

  /** 删除指定账号的全部任务（账号被删除时调用，与当前账号维度无关） */
  async clearAccount(accountId: number): Promise<void> {
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates(TABLE);
    predicates.equalTo('account_id', accountId);
    try {
      await this.db().delete(predicates);
    } catch (err) {
      throw new Error(`删除账号数据失败：${(err as Error).message}`);
    }
  }
}
