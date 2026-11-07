import { AbilityConstant, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { SettingsStore } from '../data/SettingsStore';
import { FontScaleService } from '../data/FontScaleService';
import { MODE_DARK, MODE_LIGHT, AppSettings } from '../model/AppSettings';

const DOMAIN: number = 0x0000;
const TAG: string = 'QuadrantTodo';

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(DOMAIN, TAG, 'Ability onCreate');
  }

  onDestroy(): void {
    hilog.info(DOMAIN, TAG, 'Ability onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    // 先把外观与字体设置应用好，再加载页面，避免启动瞬间的浅色闪烁与字号跳变
    this.applyLaunchPreferences().then(() => {
      windowStage.loadContent('pages/Index', async (err) => {
        if (err.code) {
          hilog.error(DOMAIN, TAG, 'Failed to load the content. Cause: %{public}s', JSON.stringify(err));
          return;
        }
        // 沉浸式：内容延伸到状态栏与导航条，页面内按安全区避让，顶栏与状态栏背景一致
        // 状态栏图标颜色随应用 colorMode 自动适配，无需显式设置
        try {
          const win: window.Window = await windowStage.getMainWindow();
          await win.setWindowLayoutFullScreen(true);
          // 状态栏背景透明，露出应用根背景；浅色 / 深色随 colorMode 自动切换，与主页面始终同色
          await win.setWindowSystemBarProperties({ statusBarColor: '#00000000' });
        } catch (err2) {
          hilog.warn(DOMAIN, TAG, 'immersive layout failed: %{public}s', (err2 as Error).message);
        }
        hilog.info(DOMAIN, TAG, 'Succeeded in loading the content.');
      });
    });
  }

  private async applyLaunchPreferences(): Promise<void> {
    try {
      await SettingsStore.init(this.context);
      const settings: AppSettings = SettingsStore.current();
      const mode: number = settings.colorMode;
      let target: ConfigurationConstant.ColorMode = ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET;
      if (mode === MODE_DARK) {
        target = ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
      } else if (mode === MODE_LIGHT) {
        target = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
      }
      this.context.getApplicationContext().setColorMode(target);
      // 自定义字号档位需在页面加载前生效；「跟随系统」不干预，由 configuration.json 驱动
      FontScaleService.applyOnLaunch(this.context, settings.fontMode);
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'apply launch preferences failed: %{public}s', (err as Error).message);
    }
  }

  onWindowStageDestroy(): void {
    hilog.info(DOMAIN, TAG, 'Ability onWindowStageDestroy');
  }

  onForeground(): void {
    hilog.info(DOMAIN, TAG, 'Ability onForeground');
  }

  onBackground(): void {
    hilog.info(DOMAIN, TAG, 'Ability onBackground');
  }
}
