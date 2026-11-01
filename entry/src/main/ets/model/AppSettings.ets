/**
 * 应用设置：全部为设备级偏好，落 preferences。
 * 每一项都在界面上有实际效果，不做纯装饰。
 */

/** 排序模式 */
export const SORT_CREATED: number = 0;
export const SORT_DUE: number = 1;
export const SORT_IMPORTANT: number = 2;

/** 外观模式，映射 ConfigurationConstant.ColorMode */
export const MODE_SYSTEM: number = 0;
export const MODE_LIGHT: number = 1;
export const MODE_DARK: number = 2;

export class AppSettings {
  /** 新建任务默认落入的象限 */
  defaultQuadrant: number = 1;
  /** 任务排序：0 最新创建 / 1 截止优先 / 2 重要优先 */
  sortMode: number = SORT_CREATED;
  /** 外观：0 跟随系统 / 1 浅色 / 2 深色 */
  colorMode: number = MODE_SYSTEM;
  /** 顶栏是否显示「今日完成」计数 */
  showCompletedToday: boolean = true;
  /** 大卡片（6*4）显示的清单条数 */
  widgetLines: number = 3;

  copy(): AppSettings {
    const next: AppSettings = new AppSettings();
    next.defaultQuadrant = this.defaultQuadrant;
    next.sortMode = this.sortMode;
    next.colorMode = this.colorMode;
    next.showCompletedToday = this.showCompletedToday;
    next.widgetLines = this.widgetLines;
    return next;
  }
}

/** 选项元数据，供设置面板渲染胶囊按钮 */
export class SettingOption {
  key: number;
  label: string;

  constructor(key: number, label: string) {
    this.key = key;
    this.label = label;
  }
}

export const SORT_OPTIONS: SettingOption[] = [
  new SettingOption(SORT_CREATED, '最新创建'),
  new SettingOption(SORT_DUE, '截止优先'),
  new SettingOption(SORT_IMPORTANT, '重要优先')
];

export const COLOR_MODE_OPTIONS: SettingOption[] = [
  new SettingOption(MODE_SYSTEM, '跟随系统'),
  new SettingOption(MODE_LIGHT, '浅色'),
  new SettingOption(MODE_DARK, '深色')
];

export const WIDGET_LINE_OPTIONS: SettingOption[] = [
  new SettingOption(2, '2 条'),
  new SettingOption(3, '3 条'),
  new SettingOption(5, '5 条')
];
