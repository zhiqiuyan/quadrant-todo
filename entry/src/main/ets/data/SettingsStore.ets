import { common } from '@kit.AbilityKit';
import { AppSettings, MODE_SYSTEM, SORT_CREATED } from '../model/AppSettings';
import { PrefStore } from './PrefStore';

const KEY_DEFAULT_QUADRANT: string = 'set_default_quadrant';
const KEY_SORT_MODE: string = 'set_sort_mode';
const KEY_COLOR_MODE: string = 'set_color_mode';
const KEY_SHOW_DONE: string = 'set_show_completed_today';
const KEY_WIDGET_LINES: string = 'set_widget_lines';

/** 设置仓储：一次读入内存，改动即落盘并保持内存同步 */
export class SettingsStore {
  private static settings: AppSettings = new AppSettings();
  private static loaded: boolean = false;

  static async init(context: common.Context): Promise<void> {
    if (SettingsStore.loaded) {
      return;
    }
    await PrefStore.init(context);
    const next: AppSettings = new AppSettings();
    const quadrant: number = PrefStore.getNumber(KEY_DEFAULT_QUADRANT, 1);
    next.defaultQuadrant = quadrant >= 1 && quadrant <= 4 ? quadrant : 1;
    const sortMode: number = PrefStore.getNumber(KEY_SORT_MODE, SORT_CREATED);
    next.sortMode = sortMode >= 0 && sortMode <= 2 ? sortMode : SORT_CREATED;
    const colorMode: number = PrefStore.getNumber(KEY_COLOR_MODE, MODE_SYSTEM);
    next.colorMode = colorMode >= 0 && colorMode <= 2 ? colorMode : MODE_SYSTEM;
    next.showCompletedToday = PrefStore.getBool(KEY_SHOW_DONE, true);
    const lines: number = PrefStore.getNumber(KEY_WIDGET_LINES, 3);
    next.widgetLines = lines >= 1 && lines <= 8 ? lines : 3;
    SettingsStore.settings = next;
    SettingsStore.loaded = true;
  }

  static current(): AppSettings {
    return SettingsStore.settings.copy();
  }

  static async save(next: AppSettings): Promise<void> {
    SettingsStore.settings = next.copy();
    await PrefStore.put(KEY_DEFAULT_QUADRANT, next.defaultQuadrant);
    await PrefStore.put(KEY_SORT_MODE, next.sortMode);
    await PrefStore.put(KEY_COLOR_MODE, next.colorMode);
    await PrefStore.put(KEY_SHOW_DONE, next.showCompletedToday);
    await PrefStore.put(KEY_WIDGET_LINES, next.widgetLines);
  }
}
