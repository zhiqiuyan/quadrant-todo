import { AbilityConstant, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { SettingsStore } from '../data/SettingsStore';
import { MODE_DARK, MODE_LIGHT } from '../model/AppSettings';

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
    // 先把外观设置应用好，再加载页面，避免启动瞬间的浅色闪烁
    this.applyAppearance().then(() => {
      windowStage.loadContent('pages/Index', (err) => {
        if (err.code) {
          hilog.error(DOMAIN, TAG, 'Failed to load the content. Cause: %{public}s', JSON.stringify(err));
          return;
        }
        hilog.info(DOMAIN, TAG, 'Succeeded in loading the content.');
      });
    });
  }

  private async applyAppearance(): Promise<void> {
    try {
      await SettingsStore.init(this.context);
      const mode: number = SettingsStore.current().colorMode;
      let target: ConfigurationConstant.ColorMode = ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET;
      if (mode === MODE_DARK) {
        target = ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
      } else if (mode === MODE_LIGHT) {
        target = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
      }
      this.context.getApplicationContext().setColorMode(target);
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'apply appearance failed: %{public}s', (err as Error).message);
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
