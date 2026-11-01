import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';

const PREF_NAME: string = 'quadrant_todo_pref';

/**
 * 轻量键值存储：账号列表、当前账号、用户设置都落在这里。
 * 与任务表分开——偏好是设备级配置，不需要事务。
 */
export class PrefStore {
  private static store: preferences.Preferences | undefined = undefined;

  static async init(context: common.Context): Promise<void> {
    if (PrefStore.store !== undefined) {
      return;
    }
    try {
      const options: preferences.Options = { name: PREF_NAME };
      PrefStore.store = await preferences.getPreferences(context, options);
    } catch (err) {
      throw new Error(`打开偏好存储失败：${(err as Error).message}`);
    }
  }

  private static p(): preferences.Preferences {
    if (PrefStore.store === undefined) {
      throw new Error('偏好存储尚未初始化，请先调用 init()');
    }
    return PrefStore.store;
  }

  static getString(key: string, defValue: string): string {
    try {
      const value: preferences.ValueType = PrefStore.p().getSync(key, defValue);
      if (typeof value === 'string') {
        return value;
      }
    } catch (err) {
      return defValue;
    }
    return defValue;
  }

  static getNumber(key: string, defValue: number): number {
    try {
      const value: preferences.ValueType = PrefStore.p().getSync(key, defValue);
      if (typeof value === 'number') {
        return value;
      }
    } catch (err) {
      return defValue;
    }
    return defValue;
  }

  static getBool(key: string, defValue: boolean): boolean {
    try {
      const value: preferences.ValueType = PrefStore.p().getSync(key, defValue);
      if (typeof value === 'boolean') {
        return value;
      }
    } catch (err) {
      return defValue;
    }
    return defValue;
  }

  static async put(key: string, value: string | number | boolean): Promise<void> {
    const p: preferences.Preferences = PrefStore.p();
    try {
      await p.put(key, value);
      await p.flush();
    } catch (err) {
      throw new Error(`写入偏好失败（${key}）：${(err as Error).message}`);
    }
  }

  static async remove(key: string): Promise<void> {
    const p: preferences.Preferences = PrefStore.p();
    try {
      await p.delete(key);
      await p.flush();
    } catch (err) {
      throw new Error(`删除偏好失败（${key}）：${(err as Error).message}`);
    }
  }
}
