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

/** 字体档位：0 跟随系统，1-4 为应用内固定比例（覆盖系统字号） */
export const FONT_FOLLOW: number = 0;
export const FONT_SMALL: number = 1;
export const FONT_NORMAL: number = 2;
export const FONT_LARGE: number = 3;
export const FONT_XLARGE: number = 4;

/** 档位 → 绝对缩放比；索引即档位值 */
const FONT_RATIOS: number[] = [1, 0.9, 1, 1.15, 1.3];

/** 档位对应比例；跟随系统时返回 1（实际值由系统配置决定） */
export function fontRatioOf(mode: number): number {
  if (mode < 0 || mode >= FONT_RATIOS.length) {
    return 1;
  }
  return FONT_RATIOS[mode];
}

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
  /** 字体档位：0 跟随系统 / 1 小 / 2 标准 / 3 大 / 4 特大 */
  fontMode: number = FONT_FOLLOW;

  copy(): AppSettings {
    const next: AppSettings = new AppSettings();
    next.defaultQuadrant = this.defaultQuadrant;
    next.sortMode = this.sortMode;
    next.colorMode = this.colorMode;
    next.showCompletedToday = this.showCompletedToday;
    next.widgetLines = this.widgetLines;
    next.fontMode = this.fontMode;
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

export const FONT_MODE_OPTIONS: SettingOption[] = [
  new SettingOption(FONT_FOLLOW, '跟随系统'),
  new SettingOption(FONT_SMALL, '小'),
  new SettingOption(FONT_NORMAL, '标准'),
  new SettingOption(FONT_LARGE, '大'),
  new SettingOption(FONT_XLARGE, '特大')
];
