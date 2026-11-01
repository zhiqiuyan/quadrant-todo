import { relationalStore } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { TaskItem } from '../model/TaskItem';
import { SORT_DUE, SORT_IMPORTANT } from '../model/AppSettings';
import { MsTombstone } from '../model/MsTodo';

const TABLE: string = 'task';
const TOMBSTONE_TABLE: string = 'ms_tombstone';
const COLUMNS: string[] = [
  'id', 'account_id', 'title', 'quadrant', 'due_at', 'important', 'completed', 'created_at', 'updated_at',
  'ms_id', 'ms_list_id', 'dirty'
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
  'updated_at INTEGER NOT NULL, ' +
  'ms_id TEXT NOT NULL DEFAULT \'\', ' +
  'ms_list_id TEXT NOT NULL DEFAULT \'\', ' +
  'dirty INTEGER NOT NULL DEFAULT 0)';

const SQL_CREATE_TOMBSTONE: string =
  'CREATE TABLE IF NOT EXISTS ms_tombstone (' +
  'ms_id TEXT PRIMARY KEY, ' +
  'list_id TEXT NOT NULL, ' +
  'deleted_at INTEGER NOT NULL)';

/** 旧版本升级用；列已存在时会抛错，忽略即可 */
const SQL_MIGRATIONS: string[] = [
  'ALTER TABLE task ADD COLUMN account_id INTEGER NOT NULL DEFAULT 1',
  'ALTER TABLE task ADD COLUMN ms_id TEXT NOT NULL DEFAULT \'\'',
  'ALTER TABLE task ADD COLUMN ms_list_id TEXT NOT NULL DEFAULT \'\'',
  'ALTER TABLE task ADD COLUMN dirty INTEGER NOT NULL DEFAULT 0'
];
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
      for (let i = 0; i < SQL_MIGRATIONS.length; i++) {
        try {
          await store.executeSql(SQL_MIGRATIONS[i]);
        } catch (migrateErr) {
          // 列已存在：说明是新库或已完成迁移，无需处理
        }
      }
      await store.executeSql(SQL_CREATE_TOMBSTONE);
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
        item.msId = rs.getString(rs.getColumnIndex('ms_id'));
        item.msListId = rs.getString(rs.getColumnIndex('ms_list_id'));
        item.dirty = rs.getLong(rs.getColumnIndex('dirty')) === 1;
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

  async insert(title: string, quadrant: number, dueAt: number, important: boolean,
    markDirty: boolean = true): Promise<number> {
    const now: number = Date.now();
    const values: relationalStore.ValuesBucket = {
      'account_id': this.accountId,
      'title': title,
      'quadrant': quadrant,
      'due_at': dueAt,
      'important': important ? 1 : 0,
      'completed': 0,
      'created_at': now,
      'updated_at': now,
      'dirty': markDirty ? 1 : 0
    };
    try {
      return await this.db().insert(TABLE, values);
    } catch (err) {
      throw new Error(`新增任务失败：${(err as Error).message}`);
    }
  }

  async updateFields(id: number, title: string, quadrant: number, dueAt: number,
    important: boolean, markDirty: boolean = true): Promise<void> {
    const values: relationalStore.ValuesBucket = {
      'title': title,
      'quadrant': quadrant,
      'due_at': dueAt,
      'important': important ? 1 : 0,
      'updated_at': Date.now(),
      'dirty': markDirty ? 1 : 0
    };
    const predicates: relationalStore.RdbPredicates = this.predicate();
    predicates.equalTo('id', id);
    try {
      await this.db().update(values, predicates);
    } catch (err) {
      throw new Error(`更新任务失败：${(err as Error).message}`);
    }
  }

  async setCompleted(id: number, completed: boolean, markDirty: boolean = true): Promise<void> {
    const values: relationalStore.ValuesBucket = {
      'completed': completed ? 1 : 0,
      'updated_at': Date.now(),
      'dirty': markDirty ? 1 : 0
    };
    const predicates: relationalStore.RdbPredicates = this.predicate();
    predicates.equalTo('id', id);
    try {
      await this.db().update(values, predicates);
    } catch (err) {
      throw new Error(`更新完成状态失败：${(err as Error).message}`);
    }
  }

  /** 删除并返回被删行（含微软同步字段），供墓碑记录用 */
  async remove(id: number): Promise<TaskItem | undefined> {
    const removed: TaskItem | undefined = await this.findById(id);
    const predicates: relationalStore.RdbPredicates = this.predicate();
    predicates.equalTo('id', id);
    try {
      await this.db().delete(predicates);
    } catch (err) {
      throw new Error(`删除任务失败：${(err as Error).message}`);
    }
    return removed;
  }

  async findById(id: number): Promise<TaskItem | undefined> {
    const predicates: relationalStore.RdbPredicates = this.predicate();
    predicates.equalTo('id', id);
    const list: TaskItem[] = await this.runQuery(predicates);
    return list.length > 0 ? list[0] : undefined;
  }

  async findByMsId(msId: string): Promise<TaskItem | undefined> {
    const predicates: relationalStore.RdbPredicates = this.predicate();
    predicates.equalTo('ms_id', msId);
    const list: TaskItem[] = await this.runQuery(predicates);
    return list.length > 0 ? list[0] : undefined;
  }

  /** 本地有改动、待推送到微软端的任务 */
  async listDirty(): Promise<TaskItem[]> {
    const predicates: relationalStore.RdbPredicates = this.predicate();
    predicates.equalTo('dirty', 1);
    predicates.orderByAsc('updated_at');
    return this.runQuery(predicates);
  }

  /** 全部任务（含已完成），清空账号前收集墓碑用 */
  async listAll(): Promise<TaskItem[]> {
    const predicates: relationalStore.RdbPredicates = this.predicate();
    predicates.orderByAsc('created_at');
    return this.runQuery(predicates);
  }

  /** 推送成功后回写同步状态并清除脏标记 */
  async setSyncInfo(id: number, msId: string, msListId: string): Promise<void> {
    const values: relationalStore.ValuesBucket = {
      'ms_id': msId,
      'ms_list_id': msListId,
      'dirty': 0
    };
    const predicates: relationalStore.RdbPredicates = this.predicate();
    predicates.equalTo('id', id);
    try {
      await this.db().update(values, predicates);
    } catch (err) {
      throw new Error(`回写同步状态失败：${(err as Error).message}`);
    }
  }

  /** 同步中发现本地比远端新时打脏标记，等待下一轮推送 */
  async markDirty(id: number): Promise<void> {
    const values: relationalStore.ValuesBucket = {
      'dirty': 1
    };
    const predicates: relationalStore.RdbPredicates = this.predicate();
    predicates.equalTo('id', id);
    try {
      await this.db().update(values, predicates);
    } catch (err) {
      throw new Error(`标记待同步失败：${(err as Error).message}`);
    }
  }

  /** 拉取远端新建：不标记脏（数据源就是远端） */
  async insertRemote(title: string, quadrant: number, dueAt: number, important: boolean,
    completed: boolean, msId: string, msListId: string, updatedAt: number): Promise<number> {
    const values: relationalStore.ValuesBucket = {
      'account_id': this.accountId,
      'title': title,
      'quadrant': quadrant,
      'due_at': dueAt,
      'important': important ? 1 : 0,
      'completed': completed ? 1 : 0,
      'created_at': updatedAt,
      'updated_at': updatedAt,
      'ms_id': msId,
      'ms_list_id': msListId,
      'dirty': 0
    };
    try {
      return await this.db().insert(TABLE, values);
    } catch (err) {
      throw new Error(`写入远端任务失败：${(err as Error).message}`);
    }
  }

  /** 拉取远端更新：覆盖本地字段，不标记脏 */
  async applyRemote(id: number, title: string, quadrant: number, dueAt: number, important: boolean,
    completed: boolean, updatedAt: number): Promise<void> {
    const values: relationalStore.ValuesBucket = {
      'title': title,
      'quadrant': quadrant,
      'due_at': dueAt,
      'important': important ? 1 : 0,
      'completed': completed ? 1 : 0,
      'updated_at': updatedAt,
      'dirty': 0
    };
    const predicates: relationalStore.RdbPredicates = this.predicate();
    predicates.equalTo('id', id);
    try {
      await this.db().update(values, predicates);
    } catch (err) {
      throw new Error(`应用远端更新失败：${(err as Error).message}`);
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

  /* ==================== 微软同步：墓碑 ==================== */

  async addTombstone(msId: string, listId: string): Promise<void> {
    if (msId.length === 0) {
      return;
    }
    const values: relationalStore.ValuesBucket = {
      'ms_id': msId,
      'list_id': listId,
      'deleted_at': Date.now()
    };
    try {
      await this.db().insert(TOMBSTONE_TABLE, values);
    } catch (err) {
      // 主键冲突说明已在队列中，忽略
    }
  }

  async listTombstones(): Promise<MsTombstone[]> {
    const result: MsTombstone[] = [];
    const predicates: relationalStore.RdbPredicates =
      new relationalStore.RdbPredicates(TOMBSTONE_TABLE);
    predicates.orderByAsc('deleted_at');
    let rs: relationalStore.ResultSet | undefined = undefined;
    try {
      rs = await this.db().query(predicates, ['ms_id', 'list_id']);
      while (rs.goToNextRow()) {
        const item: MsTombstone = new MsTombstone();
        item.msId = rs.getString(rs.getColumnIndex('ms_id'));
        item.listId = rs.getString(rs.getColumnIndex('list_id'));
        result.push(item);
      }
    } catch (err) {
      throw new Error(`读取删除队列失败：${(err as Error).message}`);
    } finally {
      if (rs !== undefined) {
        try {
          rs.close();
        } catch (closeErr) {
          // 关闭失败不影响已读取的数据
        }
      }
    }
    return result;
  }

  async removeTombstone(msId: string): Promise<void> {
    const predicates: relationalStore.RdbPredicates =
      new relationalStore.RdbPredicates(TOMBSTONE_TABLE);
    predicates.equalTo('ms_id', msId);
    try {
      await this.db().delete(predicates);
    } catch (err) {
      // 清理失败只影响重试，不阻断同步
    }
  }
}
