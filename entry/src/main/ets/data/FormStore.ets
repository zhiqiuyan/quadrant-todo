import { common } from '@kit.AbilityKit';
import { PrefStore } from './PrefStore';

const KEY_FORM_IDS: string = 'form_ids_json';

/**
 * 卡片实例登记表。
 * 桌面上的每张卡片有一个 formId，只有记住它才能在任务变化后主动刷新。
 */
export class FormStore {
  static async init(context: common.Context): Promise<void> {
    await PrefStore.init(context);
  }

  static list(): string[] {
    const text: string = PrefStore.getString(KEY_FORM_IDS, '[]');
    try {
      const raw: string[] = JSON.parse(text) as string[];
      const result: string[] = [];
      for (let i = 0; i < raw.length; i++) {
        if (typeof raw[i] === 'string' && raw[i].length > 0) {
          result.push(raw[i]);
        }
      }
      return result;
    } catch (err) {
      return [];
    }
  }

  private static async save(ids: string[]): Promise<void> {
    await PrefStore.put(KEY_FORM_IDS, JSON.stringify(ids));
  }

  static async add(formId: string): Promise<void> {
    if (formId.length === 0) {
      return;
    }
    const ids: string[] = FormStore.list();
    for (let i = 0; i < ids.length; i++) {
      if (ids[i] === formId) {
        return;
      }
    }
    ids.push(formId);
    await FormStore.save(ids);
  }

  static async remove(formId: string): Promise<void> {
    const ids: string[] = FormStore.list();
    const next: string[] = [];
    for (let i = 0; i < ids.length; i++) {
      if (ids[i] !== formId) {
        next.push(ids[i]);
      }
    }
    if (next.length !== ids.length) {
      await FormStore.save(next);
    }
  }
}
