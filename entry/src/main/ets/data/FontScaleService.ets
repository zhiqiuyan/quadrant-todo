import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { FONT_FOLLOW, fontRatioOf } from '../model/AppSettings';

const DOMAIN: number = 0x0000;
const TAG: string = 'QuadrantTodo';

/**
 * 应用字体比例。
 *
 * 两条通道：
 * 1) 跟随系统 —— 由 AppScope/resources/base/profile/configuration.json 的
 *    fontSizeScale=followSystem 驱动，ArkUI 中 fontSize 的数值单位为 fp，
 *    系统调整「设置 → 显示和亮度 → 字体大小」时应用自动缩放，上限 1.75×。
 * 2) 应用内档位 —— 调用 ApplicationContext.setFontSizeScale 设置绝对比例。
 *    注意：官方约束为「设置后应用字体不再跟随系统」，因此该比例只在
 *    用户主动选择非「跟随系统」档位时使用，跟随系统时不做任何设置。
 */
export class FontScaleService {
  /** 系统当前字体缩放比，读不到时按 1.0 处理 */
  static systemScale(context: common.Context): number {
    try {
      const ui: common.UIAbilityContext = context as common.UIAbilityContext;
      const scale: number | undefined = ui.config.fontSizeScale;
      if (scale === undefined || scale === null || scale <= 0) {
        return 1;
      }
      return scale;
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'read fontSizeScale failed: %{public}s', (err as Error).message);
      return 1;
    }
  }

  /** 冷启动应用：跟随系统时保持不干预，把缩放权交给系统配置 */
  static applyOnLaunch(context: common.Context, mode: number): void {
    if (mode === FONT_FOLLOW) {
      return;
    }
    FontScaleService.setScale(context, fontRatioOf(mode));
  }

  /** 用户切换档位后立即生效；「跟随系统」档位回退到当前系统比例 */
  static applyNow(context: common.Context, mode: number): void {
    const target: number = mode === FONT_FOLLOW ? FontScaleService.systemScale(context) : fontRatioOf(mode);
    FontScaleService.setScale(context, target);
  }

  private static setScale(context: common.Context, scale: number): void {
    try {
      context.getApplicationContext().setFontSizeScale(scale);
      hilog.info(DOMAIN, TAG, 'font scale set to %{public}s', scale.toString());
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'setFontSizeScale failed: %{public}s', (err as Error).message);
    }
  }
}
