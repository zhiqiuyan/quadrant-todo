import { cloudStorage } from '@kit.CloudFoundationKit';
import { common } from '@kit.AbilityKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { util } from '@kit.ArkTS';
import { BusinessError } from '@kit.BasicServicesKit';
import { PrefStore } from './PrefStore';
import { AccountStore } from './AccountStore';
import { TaskRepository } from './TaskRepository';
import { HuaweiAuthService } from './HuaweiAuthService';

const DOMAIN: number = 0x0000;
const TAG: string = 'BackupService';
const CLOUD_DIR: string = 'quadrant-todo';
const KEY_LAST_BACKUP: string = 'backup_last_ts';
const KEY_AUTO_BACKUP: string = 'backup_auto';

/** 快照结构（JSON 序列化用） */
interface BackupRow {
  id: number;
  title: string;
  quadrant: number;
  dueAt: number;
  important: boolean;
  completed: boolean;
  createdAt: number;
  updatedAt: number;
}

interface BackupAccount {
  id: number;
  name: string;
  colorIndex: number;
  tasks: BackupRow[];
}

interface BackupSnapshot {
  version: number;
  exportedAt: number;
  accountCount: number;
  taskCount: number;
  accounts: BackupAccount[];
}

/** 解析不可信 JSON 用的宽松结构（字段全部可选） */
interface LooseRow {
  title?: string;
  quadrant?: number;
  dueAt?: number;
  important?: boolean;
  completed?: boolean;
}

interface LooseAccount {
  tasks?: LooseRow[];
}

interface LooseSnapshot {
  taskCount?: number;
  accounts?: LooseAccount[];
}

/** 一次备份的结果摘要 */
export class BackupResult {
  ok: boolean = false;
  message: string = '';
  taskCount: number = 0;
}

/**
 * 云备份：把全部账号的任务与设置序列化为 JSON，上传到 AGC 云存储。
 *
 * 运行前提（与华为账号登录一致）：
 * 1. AGC 创建应用，开通「云基础服务」并创建默认存储实例；
 * 2. module.json5 配置 client_id；
 * 3. 已登录华为账号（云存储以华为账号身份鉴权）。
 */
export class BackupService {
  /** 全量快照：所有账号的任务 + 备份元信息 */
  private static async snapshotJson(): Promise<string> {
    const repo: TaskRepository = TaskRepository.getInstance();
    const accounts = AccountStore.all();
    const snapshot: BackupSnapshot = {
      version: 1,
      exportedAt: Date.now(),
      accountCount: accounts.length,
      taskCount: 0,
      accounts: []
    };

    let total: number = 0;
    for (let i = 0; i < accounts.length; i++) {
      const account = accounts[i];
      repo.useAccount(account.id);
      const tasks = await repo.listAll();
      total += tasks.length;
      const rows: BackupRow[] = [];
      for (let j = 0; j < tasks.length; j++) {
        const t = tasks[j];
        rows.push({
          id: t.id,
          title: t.title,
          quadrant: t.quadrant,
          dueAt: t.dueAt,
          important: t.important,
          completed: t.completed,
          createdAt: t.createdAt,
          updatedAt: t.updatedAt
        });
      }
      snapshot.accounts.push({
        id: account.id,
        name: account.name,
        colorIndex: account.colorIndex,
        tasks: rows
      });
    }
    snapshot.taskCount = total;
    return JSON.stringify(snapshot);
  }

  /** 生成快照文件，返回本地路径 */
  private static async writeSnapshot(context: common.Context): Promise<string> {
    const json: string = await BackupService.snapshotJson();
    const dir: string = `${context.cacheDir}/backup`;
    try {
      if (!fs.accessSync(dir)) {
        fs.mkdirSync(dir, true);
      }
      const path: string = `${dir}/backup-latest.json`;
      const file = fs.openSync(path, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      fs.writeSync(file.fd, json);
      fs.closeSync(file.fd);
      return path;
    } catch (err) {
      throw new Error(`生成备份文件失败：${(err as Error).message}`);
    }
  }

  /** 上传备份。namespace 由华为账号 openID 派生，避免不同用户互相覆盖 */
  static async backup(context: common.Context): Promise<BackupResult> {
    const result: BackupResult = new BackupResult();
    const ns: string = HuaweiAuthService.cloudNamespace();
    if (ns.length === 0) {
      result.message = '请先登录华为账号';
      return result;
    }
    try {
      const localPath: string = await BackupService.writeSnapshot(context);
      const bucket: cloudStorage.StorageBucket = cloudStorage.bucket();
      await bucket.uploadFile(context, {
        localPath: localPath,
        cloudPath: `${CLOUD_DIR}/${ns}/backup-latest.json`
      });
      const json: string = await BackupService.readLocal(localPath);
      result.taskCount = BackupService.countOf(json);
      await PrefStore.put(KEY_LAST_BACKUP, Date.now());
      result.ok = true;
      result.message = `已备份 ${result.taskCount} 条任务`;
    } catch (err) {
      const be: BusinessError = err as BusinessError;
      const code: number = be.code ?? 0;
      hilog.error(DOMAIN, TAG, 'backup failed: %{public}d %{public}s', code, be.message ?? '');
      if (code === 1008221001 || code === 1008220009) {
        result.message = '云存储不可用：请在 AGC 开通云基础服务并创建存储实例';
      } else {
        result.message = `备份失败：${(err as Error).message}`;
      }
    }
    return result;
  }

  /** 从云端恢复：下载最近备份，把任务并入当前账号（按标题+象限去重） */
  static async restore(context: common.Context): Promise<BackupResult> {
    const result: BackupResult = new BackupResult();
    const ns: string = HuaweiAuthService.cloudNamespace();
    if (ns.length === 0) {
      result.message = '请先登录华为账号';
      return result;
    }
    try {
      const dir: string = `${context.cacheDir}/backup`;
      if (!fs.accessSync(dir)) {
        fs.mkdirSync(dir, true);
      }
      const localPath: string = `${dir}/restore.json`;
      const bucket: cloudStorage.StorageBucket = cloudStorage.bucket();
      await bucket.downloadFile(context, {
        localPath: localPath,
        cloudPath: `${CLOUD_DIR}/${ns}/backup-latest.json`
      });
      const json: string = await BackupService.readLocal(localPath);
      result.taskCount = await BackupService.importJson(json);
      result.ok = true;
      result.message = `已恢复 ${result.taskCount} 条任务到「${AccountStore.active().name}」`;
    } catch (err) {
      result.message = `恢复失败：${(err as Error).message}`;
    }
    return result;
  }

  /** 自动备份：改动后调用（内部 60s 防抖），失败静默不打扰 */
  private static pending: boolean = false;
  private static lastRun: number = 0;

  static async autoBackup(context: common.Context): Promise<void> {
    if (!BackupService.autoEnabled() || !HuaweiAuthService.loggedIn()) {
      return;
    }
    const now: number = Date.now();
    if (now - BackupService.lastRun < 60_000) {
      return;
    }
    if (BackupService.pending) {
      return;
    }
    BackupService.pending = true;
    BackupService.lastRun = now;
    try {
      await BackupService.backup(context);
    } finally {
      BackupService.pending = false;
    }
  }

  static autoEnabled(): boolean {
    return PrefStore.getBool(KEY_AUTO_BACKUP, true);
  }

  static async setAutoEnabled(on: boolean): Promise<void> {
    await PrefStore.put(KEY_AUTO_BACKUP, on);
  }

  static lastBackupText(): string {
    const ts: number = PrefStore.getNumber(KEY_LAST_BACKUP, 0);
    if (ts === 0) {
      return '';
    }
    const d: Date = new Date(ts);
    const hh: string = d.getHours() < 10 ? `0${d.getHours()}` : `${d.getHours()}`;
    const mm: string = d.getMinutes() < 10 ? `0${d.getMinutes()}` : `${d.getMinutes()}`;
    return `${d.getMonth() + 1}/${d.getDate()} ${hh}:${mm}`;
  }

  private static async readLocal(path: string): Promise<string> {
    try {
      const file = fs.openSync(path, fs.OpenMode.READ_ONLY);
      const stat = fs.statSync(path);
      const buf: ArrayBuffer = new ArrayBuffer(stat.size);
      fs.readSync(file.fd, buf);
      fs.closeSync(file.fd);
      return BackupService.decode(buf);
    } catch (err) {
      throw new Error(`读取备份文件失败：${(err as Error).message}`);
    }
  }

  private static decode(buf: ArrayBuffer): string {
    const decoder: util.TextDecoder = util.TextDecoder.create('utf-8');
    return decoder.decodeToString(new Uint8Array(buf));
  }

  private static countOf(json: string): number {
    try {
      const parsed: LooseSnapshot = JSON.parse(json) as LooseSnapshot;
      return parsed.taskCount ?? 0;
    } catch (err) {
      return 0;
    }
  }

  /** 把备份 JSON 并入当前账号；同象限同标题的未完成任务视为重复跳过 */
  private static async importJson(json: string): Promise<number> {
    const parsed: LooseSnapshot = JSON.parse(json) as LooseSnapshot;
    if (parsed.accounts === undefined) {
      throw new Error('备份文件格式不正确');
    }
    const repo: TaskRepository = TaskRepository.getInstance();
    const activeId: number = AccountStore.active().id;
    repo.useAccount(activeId);
    const existing = await repo.listAll();

    let imported: number = 0;
    for (let i = 0; i < parsed.accounts.length; i++) {
      const acc: LooseAccount = parsed.accounts[i];
      if (acc.tasks === undefined) {
        continue;
      }
      for (let j = 0; j < acc.tasks.length; j++) {
        const row: LooseRow = acc.tasks[j];
        const title: string = row.title ?? '';
        const quadrant: number = row.quadrant ?? 1;
        const completed: boolean = row.completed === true;
        if (title.length === 0) {
          continue;
        }
        let dup: boolean = false;
        for (let k = 0; k < existing.length; k++) {
          if (existing[k].title === title && existing[k].quadrant === quadrant) {
            dup = true;
            break;
          }
        }
        if (dup) {
          continue;
        }
        const dueAt: number = row.dueAt ?? 0;
        const important: boolean = row.important === true;
        await repo.insert(title, quadrant, dueAt, important, false);
        if (completed) {
          const all = await repo.listAll();
          for (let k = 0; k < all.length; k++) {
            if (all[k].title === title && all[k].quadrant === quadrant) {
              await repo.setCompleted(all[k].id, true, false);
              break;
            }
          }
        }
        imported++;
      }
    }
    return imported;
  }
}
