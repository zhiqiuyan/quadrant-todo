import { hilog } from '@kit.PerformanceAnalysisKit';
import { MsGraphClient } from './MsGraphClient';
import { MsAuthService } from './MsAuthService';
import { TaskRepository } from './TaskRepository';
import { TaskItem } from '../model/TaskItem';
import { MsSyncResult, MsTask, MsTaskPayload, MsTombstone } from '../model/MsTodo';

const DOMAIN: number = 0x0000;
const TAG: string = 'QuadrantTodo';

/**
 * 微软 To Do 双向同步引擎。
 *
 * 每轮顺序：墓碑（远端删除）→ 推送本地脏数据 → 拉取远端变更。
 * 冲突策略：单字段级不做合并，按「最后修改时间赢」：
 * - 推送阶段：本地脏数据一律覆盖远端；
 * - 拉取阶段：远端 lastModified 更新且本地干净 → 覆盖本地；
 *   本地更新但本轮推送后又改动 → 打脏标记等下一轮。
 * 象限变更 = 换清单：To Do 无跨清单移动 API，按「旧清单删 + 新清单建」实现。
 */
export class MsSyncService {
  private static working: boolean = false;

  static get busy(): boolean {
    return MsSyncService.working;
  }

  /** 本地删除后调用：远端还有对应任务则记入墓碑队列 */
  static async recordDeletion(task: TaskItem): Promise<void> {
    if (task.msId.length === 0) {
      return;
    }
    await TaskRepository.getInstance().addTombstone(task.msId, task.msListId);
  }

  /** 单条远端删除（失败只记日志，由下次同步重试） */
  static async deleteRemote(listId: string, msId: string): Promise<boolean> {
    try {
      await MsGraphClient.deleteTask(listId, msId);
      return true;
    } catch (err) {
      const message: string = (err as Error).message;
      // 404：远端本来就没有，视为成功
      if (message.indexOf('HTTP 404') >= 0) {
        return true;
      }
      hilog.warn(DOMAIN, TAG, 'delete remote failed: %{public}s', message);
      return false;
    }
  }

  /** 执行一轮完整同步；并发调用直接拒绝，返回当前进行中 */
  static async sync(): Promise<MsSyncResult> {
    const result: MsSyncResult = new MsSyncResult();
    if (MsSyncService.working) {
      result.message = '上一次同步还在进行中';
      return result;
    }
    MsSyncService.working = true;
    try {
      if (!MsAuthService.connected()) {
        result.message = '尚未连接微软账号';
        return result;
      }
      const repo: TaskRepository = TaskRepository.getInstance();
      const listIds: string[] = await MsGraphClient.ensureLists();

      await MsSyncService.flushTombstones(repo, result);
      await MsSyncService.pushDirty(repo, listIds, result);
      await MsSyncService.pullRemote(repo, listIds, result);

      const text: string = `同步完成：推送 ${result.pushed}，拉取 ${result.pulled}`;
      await MsAuthService.setLastSync(text);
      result.message = text;
      if (result.failed > 0) {
        result.message += `，失败 ${result.failed}`;
      }
      return result;
    } catch (err) {
      result.failed++;
      result.message = `同步失败：${(err as Error).message}`;
      hilog.error(DOMAIN, TAG, 'sync failed: %{public}s', result.message);
      return result;
    } finally {
      MsSyncService.working = false;
    }
  }

  private static async flushTombstones(repo: TaskRepository, result: MsSyncResult): Promise<void> {
    const tombstones = await repo.listTombstones();
    for (let i = 0; i < tombstones.length; i++) {
      const tomb: MsTombstone = tombstones[i];
      if (tomb.listId.length === 0) {
        await repo.removeTombstone(tomb.msId);
        continue;
      }
      if (await MsSyncService.deleteRemote(tomb.listId, tomb.msId)) {
        await repo.removeTombstone(tomb.msId);
        result.deleted++;
      } else {
        result.failed++;
      }
    }
  }

  private static async pushDirty(repo: TaskRepository, listIds: string[],
    result: MsSyncResult): Promise<void> {
    const dirty: TaskItem[] = await repo.listDirty();
    for (let i = 0; i < dirty.length; i++) {
      const task: TaskItem = dirty[i];
      const targetList: string = listIds[task.quadrant - 1];
      if (targetList.length === 0) {
        result.failed++;
        continue;
      }
      const payload: MsTaskPayload = MsSyncService.toPayload(task);
      try {
        if (task.msId.length === 0) {
          const msId: string = await MsGraphClient.createTask(targetList, payload);
          await repo.setSyncInfo(task.id, msId, targetList);
          result.pushed++;
        } else if (task.msListId !== targetList && task.msListId.length > 0) {
          // 象限变更：旧清单删除 + 新清单重建
          const deleted: boolean = await MsSyncService.deleteRemote(task.msListId, task.msId);
          const msId: string = await MsGraphClient.createTask(targetList, payload);
          await repo.setSyncInfo(task.id, msId, targetList);
          if (deleted) {
            result.moved++;
          } else {
            result.pushed++;
          }
        } else {
          // 已有远端任务的更新：To Do 无跨清单移动 API，且 PATCH 方法要求较新系统
          // 版本，这里统一走「旧任务删除 + 新任务重建」，失败则保留脏标记等下轮重试。
          const oldList: string = task.msListId.length > 0 ? task.msListId : targetList;
          const deleted: boolean = await MsSyncService.deleteRemote(oldList, task.msId);
          if (!deleted) {
            result.failed++;
            continue;
          }
          const msId: string = await MsGraphClient.createTask(targetList, payload);
          await repo.setSyncInfo(task.id, msId, targetList);
          result.pushed++;
        }
      } catch (err) {
        result.failed++;
        hilog.warn(DOMAIN, TAG, 'push failed: %{public}s', (err as Error).message);
      }
    }
  }

  private static async pullRemote(repo: TaskRepository, listIds: string[],
    result: MsSyncResult): Promise<void> {
    for (let q = 1; q <= 4; q++) {
      const listId: string = listIds[q - 1];
      if (listId.length === 0) {
        continue;
      }
      let remote: MsTask[] = [];
      try {
        remote = await MsGraphClient.listTasks(listId);
      } catch (err) {
        result.failed++;
        hilog.warn(DOMAIN, TAG, 'pull q%{public}d failed: %{public}s', q, (err as Error).message);
        continue;
      }
      for (let i = 0; i < remote.length; i++) {
        const task: MsTask = remote[i];
        try {
          const local: TaskItem | undefined = await repo.findByMsId(task.id);
          const remoteUpdated: number = MsGraphClient.modifiedAt(task);
          if (local === undefined) {
            await repo.insertRemote(task.title, q, MsGraphClient.dueFromGraph(task),
              task.importance === 'high', task.status === 'completed', task.id, listId,
              remoteUpdated > 0 ? remoteUpdated : Date.now());
            result.pulled++;
          } else if (local.dirty) {
            // 本地有未推送的改动：本地赢，本轮跳过
            continue;
          } else if (remoteUpdated > local.updatedAt) {
            await repo.applyRemote(local.id, task.title, q, MsGraphClient.dueFromGraph(task),
              task.importance === 'high', task.status === 'completed', remoteUpdated);
            result.pulled++;
          } else if (local.updatedAt > remoteUpdated) {
            await repo.markDirty(local.id);
          }
        } catch (err) {
          result.failed++;
          hilog.warn(DOMAIN, TAG, 'pull item failed: %{public}s', (err as Error).message);
        }
      }
    }
  }

  private static toPayload(task: TaskItem): MsTaskPayload {
    const payload: MsTaskPayload = new MsTaskPayload();
    payload.title = task.title;
    payload.importance = task.important ? 'high' : 'normal';
    payload.status = task.completed ? 'completed' : 'notStarted';
    payload.dueDateTime = MsGraphClient.dueToGraph(task.dueAt);
    return payload;
  }

  /** 首次连接后的整库上行：把当前账号全部任务推到微软端 */
  static async initialPush(): Promise<MsSyncResult> {
    const repo: TaskRepository = TaskRepository.getInstance();
    const all: TaskItem[] = await repo.listAll();
    for (let i = 0; i < all.length; i++) {
      if (all[i].msId.length === 0) {
        await repo.markDirty(all[i].id);
      }
    }
    return MsSyncService.sync();
  }
}
