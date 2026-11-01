import { formBindingData, FormExtensionAbility, formInfo, formProvider } from '@kit.FormKit';
import { Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { WidgetData, WidgetPayload } from '../widget/WidgetData';
import { FormStore } from '../data/FormStore';

const DOMAIN: number = 0x0000;
const TAG: string = 'QuadrantTodoForm';

/**
 * 桌面卡片提供者。
 * 4*4 与 6*4 两张卡片共用这一个 ExtensionAbility，数据由 WidgetData 统一构建。
 *
 * onAddForm 必须同步返回数据，所以先给空载荷占位，再用 updateForm 异步推真实数据。
 */
export default class EntryFormAbility extends FormExtensionAbility {
  onAddForm(want: Want): formBindingData.FormBindingData {
    const formId: string = EntryFormAbility.formIdOf(want);
    this.push(formId);
    return formBindingData.createFormBindingData(new WidgetPayload());
  }

  onUpdateForm(formId: string): void {
    this.push(formId);
  }

  onRemoveForm(formId: string): void {
    this.forget(formId);
  }

  onFormEvent(formId: string, message: string): void {
    hilog.info(DOMAIN, TAG, 'form event: %{public}s', message);
    this.push(formId);
  }

  private static formIdOf(want: Want): string {
    const params: Record<string, Object> | undefined = want.parameters;
    if (params === undefined || params === null) {
      return '';
    }
    const raw: Object | undefined = params[formInfo.FormParam.IDENTITY_KEY];
    if (raw === undefined || raw === null) {
      return '';
    }
    return raw.toString();
  }

  private async push(formId: string): Promise<void> {
    if (formId.length === 0) {
      return;
    }
    try {
      await FormStore.init(this.context);
      await FormStore.add(formId);
      const payload: WidgetPayload = await WidgetData.build(this.context);
      await formProvider.updateForm(formId, formBindingData.createFormBindingData(payload));
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'push form data failed: %{public}s', (err as Error).message);
    }
  }

  private async forget(formId: string): Promise<void> {
    if (formId.length === 0) {
      return;
    }
    try {
      await FormStore.init(this.context);
      await FormStore.remove(formId);
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'forget form failed: %{public}s', (err as Error).message);
    }
  }
}
