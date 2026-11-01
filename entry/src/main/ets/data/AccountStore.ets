import { common } from '@kit.AbilityKit';
import { Account, AccountJson } from '../model/Account';
import { PrefStore } from './PrefStore';

const KEY_ACCOUNTS: string = 'accounts_json';
const KEY_ACTIVE: string = 'active_account_id';

/**
 * 账号仓储：账号列表与当前账号持久化在 preferences。
 * 任务数据不在这里删除——账号删除时由 TaskRepository 清理该账号的任务。
 */
export class AccountStore {
  private static list: Account[] = [];
  private static activeId: number = 0;
  private static loaded: boolean = false;

  static async init(context: common.Context): Promise<void> {
    if (AccountStore.loaded) {
      return;
    }
    await PrefStore.init(context);
    const text: string = PrefStore.getString(KEY_ACCOUNTS, '');
    const parsed: Account[] = AccountStore.parse(text);
    if (parsed.length === 0) {
      const seed: Account = new Account();
      seed.id = 1;
      seed.name = '我';
      seed.colorIndex = 0;
      seed.createdAt = Date.now();
      AccountStore.list = [seed];
      AccountStore.activeId = 1;
      await AccountStore.persist();
      await PrefStore.put(KEY_ACTIVE, 1);
    } else {
      AccountStore.list = parsed;
      const active: number = PrefStore.getNumber(KEY_ACTIVE, parsed[0].id);
      AccountStore.activeId = AccountStore.contains(active) ? active : parsed[0].id;
    }
    AccountStore.loaded = true;
  }

  private static contains(id: number): boolean {
    for (let i = 0; i < AccountStore.list.length; i++) {
      if (AccountStore.list[i].id === id) {
        return true;
      }
    }
    return false;
  }

  /** 容错解析：任何一条脏数据都不应该让应用起不来 */
  private static parse(text: string): Account[] {
    const result: Account[] = [];
    if (text.length === 0) {
      return result;
    }
    try {
      const raw: AccountJson[] = JSON.parse(text) as AccountJson[];
      for (let i = 0; i < raw.length; i++) {
        const item: AccountJson = raw[i];
        if (item === null || item === undefined) {
          continue;
        }
        const acc: Account = new Account();
        acc.id = item.id;
        acc.name = item.name !== undefined && item.name.length > 0 ? item.name : '我';
        acc.colorIndex = item.colorIndex !== undefined ? item.colorIndex : 0;
        acc.createdAt = item.createdAt !== undefined ? item.createdAt : 0;
        result.push(acc);
      }
    } catch (err) {
      return [];
    }
    return result;
  }

  private static async persist(): Promise<void> {
    const plain: AccountJson[] = [];
    for (let i = 0; i < AccountStore.list.length; i++) {
      const acc: Account = AccountStore.list[i];
      plain.push({ id: acc.id, name: acc.name, colorIndex: acc.colorIndex, createdAt: acc.createdAt } as AccountJson);
    }
    await PrefStore.put(KEY_ACCOUNTS, JSON.stringify(plain));
  }

  static all(): Account[] {
    const copy: Account[] = [];
    for (let i = 0; i < AccountStore.list.length; i++) {
      copy.push(AccountStore.list[i].copy());
    }
    return copy;
  }

  static activeIdValue(): number {
    return AccountStore.activeId;
  }

  static active(): Account {
    for (let i = 0; i < AccountStore.list.length; i++) {
      if (AccountStore.list[i].id === AccountStore.activeId) {
        return AccountStore.list[i].copy();
      }
    }
    if (AccountStore.list.length > 0) {
      return AccountStore.list[0].copy();
    }
    const fallback: Account = new Account();
    fallback.id = 1;
    fallback.name = '我';
    return fallback;
  }

  private static nextId(): number {
    let max: number = 0;
    for (let i = 0; i < AccountStore.list.length; i++) {
      if (AccountStore.list[i].id > max) {
        max = AccountStore.list[i].id;
      }
    }
    return max + 1;
  }

  static async create(name: string, colorIndex: number): Promise<Account> {
    const acc: Account = new Account();
    acc.id = AccountStore.nextId();
    acc.name = name.trim().length > 0 ? name.trim() : `账号 ${acc.id}`;
    acc.colorIndex = colorIndex;
    acc.createdAt = Date.now();
    AccountStore.list.push(acc);
    await AccountStore.persist();
    return acc.copy();
  }

  static async switchTo(id: number): Promise<void> {
    if (!AccountStore.contains(id)) {
      return;
    }
    AccountStore.activeId = id;
    await PrefStore.put(KEY_ACTIVE, id);
  }

  static async rename(id: number, name: string): Promise<void> {
    const trimmed: string = name.trim();
    if (trimmed.length === 0) {
      return;
    }
    for (let i = 0; i < AccountStore.list.length; i++) {
      if (AccountStore.list[i].id === id) {
        AccountStore.list[i].name = trimmed;
        await AccountStore.persist();
        return;
      }
    }
  }

  /** 删除账号；最后一个账号不允许删除，返回 false */
  static async remove(id: number): Promise<boolean> {
    if (AccountStore.list.length <= 1) {
      return false;
    }
    const next: Account[] = [];
    for (let i = 0; i < AccountStore.list.length; i++) {
      if (AccountStore.list[i].id !== id) {
        next.push(AccountStore.list[i]);
      }
    }
    if (next.length === AccountStore.list.length) {
      return false;
    }
    AccountStore.list = next;
    await AccountStore.persist();
    if (AccountStore.activeId === id) {
      AccountStore.activeId = next[0].id;
      await PrefStore.put(KEY_ACTIVE, AccountStore.activeId);
    }
    return true;
  }
}
