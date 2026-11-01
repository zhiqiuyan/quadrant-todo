import { common } from '@kit.AbilityKit';
import { formBindingData, formProvider } from '@kit.FormKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { WidgetData, WidgetPayload } from '../widget/WidgetData';
import { FormStore } from './FormStore';

const DOMAIN: number = 0x0000;
const TAG: string = 'QuadrantTodo';

/**
 * 主界面 → 桌面卡片的单向刷新。
 * 任务或设置变化后调用 refreshAll()，所有已登记的卡片实例会被推一次最新数据。
 */
export class WidgetBridge {
  static async refreshAll(context: common.Context | undefined): Promise<void> {
    if (context === undefined) {
      return;
    }
    await FormStore.init(context);
    const ids: string[] = FormStore.list();
    if (ids.length === 0) {
      return;
    }
    let payload: WidgetPayload;
    try {
      payload = await WidgetData.build(context);
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'build widget payload failed: %{public}s', (err as Error).message);
      return;
    }
    for (let i = 0; i < ids.length; i++) {
      try {
        await formProvider.updateForm(ids[i], formBindingData.createFormBindingData(payload));
      } catch (err) {
        hilog.warn(DOMAIN, TAG, 'update form %{public}s failed: %{public}s', ids[i], (err as Error).message);
      }
    }
  }
}
