import { common, ConfigurationConstant } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { QuadrantMeta, QUADRANTS, TaskItem, Q1 } from '../model/TaskItem';
import { Account, accountInitial, avatarColor, AVATAR_COLORS } from '../model/Account';
import {
  AppSettings, COLOR_MODE_OPTIONS, MODE_DARK, MODE_LIGHT, MODE_SYSTEM, SettingOption,
  SORT_OPTIONS, WIDGET_LINE_OPTIONS
} from '../model/AppSettings';
import { TaskRepository } from '../data/TaskRepository';
import { AccountStore } from '../data/AccountStore';
import { SettingsStore } from '../data/SettingsStore';
import { WidgetBridge } from '../data/WidgetBridge';
import { DateUtil } from '../common/DateUtil';

const DOMAIN: number = 0x0000;
const TAG: string = 'QuadrantTodo';
const APP_VERSION: string = '1.1.0';

@Entry
@Component
struct Index {
  /** 未完成任务全集，四个格子按象限过滤渲染 */
  @State tasks: TaskItem[] = [];
  @State ready: boolean = false;
  @State completedToday: number = 0;

  /** 账号与设置 */
  @State account: Account = new Account();
  @State accounts: Account[] = [];
  @State settings: AppSettings = new AppSettings();
  @State showAccount: boolean = false;
  @State showSettings: boolean = false;
  @State newName: string = '';
  @State newColorIndex: number = 0;
  @State renameId: number = 0;
  @State renameText: string = '';

  /** 编辑面板 */
  @State showEditor: boolean = false;
  @State editingId: number = 0;
  @State draftTitle: string = '';
  @State draftQuadrant: number = Q1;
  @State draftDue: number = 0;
  @State draftImportant: boolean = false;
  @State draftDate: Date = new Date();
  @State showCalendar: boolean = false;

  /** 归类尺子面板 */
  @State showRuler: boolean = false;

  /** 已完成面板 */
  @State showDone: boolean = false;
  @State doneTasks: TaskItem[] = [];

  /** 四个格子的快速输入框内容 */
  @State inputQ1: string = '';
  @State inputQ2: string = '';
  @State inputQ3: string = '';
  @State inputQ4: string = '';

  private ctx: common.UIAbilityContext | undefined = undefined;

  aboutToAppear(): void {
    this.boot();
  }

  /* ==================== 数据 ==================== */

  private async boot(): Promise<void> {
    try {
      const context: common.UIAbilityContext =
        this.getUIContext().getHostContext() as common.UIAbilityContext;
      this.ctx = context;
      await AccountStore.init(context);
      await SettingsStore.init(context);
      this.settings = SettingsStore.current();
      this.accounts = AccountStore.all();
      this.account = AccountStore.active();

      const repo: TaskRepository = TaskRepository.getInstance();
      await repo.init(context);
      repo.useAccount(this.account.id);
      this.applyColorMode(this.settings.colorMode);
      await this.reload();
      this.ready = true;
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'boot failed: %{public}s', (err as Error).message);
      this.toast('初始化失败：' + (err as Error).message);
    }
  }

  private async reload(): Promise<void> {
    try {
      this.tasks = await TaskRepository.getInstance().listActive(this.settings.sortMode);
      this.completedToday = await TaskRepository.getInstance().countCompletedSince(DateUtil.todayStart());
      if (this.showDone) {
        await this.loadDone();
      }
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'reload failed: %{public}s', (err as Error).message);
    }
  }

  /** 任何写操作之后：刷新界面 + 推送桌面卡片 */
  private async afterChange(): Promise<void> {
    await this.reload();
    await WidgetBridge.refreshAll(this.ctx);
  }

  private async loadDone(): Promise<void> {
    try {
      this.doneTasks = await TaskRepository.getInstance().listCompleted(50);
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'loadDone failed: %{public}s', (err as Error).message);
    }
  }

  private openDone(): void {
    this.showDone = true;
    this.loadDone();
  }

  private async restoreTask(item: TaskItem): Promise<void> {
    try {
      await TaskRepository.getInstance().setCompleted(item.id, false);
      await this.afterChange();
    } catch (err) {
      this.toast('恢复失败：' + (err as Error).message);
    }
  }

  private toast(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: message, duration: 2000 });
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'toast failed: %{public}s', (err as Error).message);
    }
  }

  private tasksOf(quadrant: number): TaskItem[] {
    const result: TaskItem[] = [];
    for (let i = 0; i < this.tasks.length; i++) {
      if (this.tasks[i].quadrant === quadrant) {
        result.push(this.tasks[i]);
      }
    }
    return result;
  }

  private inputOf(quadrant: number): string {
    if (quadrant === 1) {
      return this.inputQ1;
    }
    if (quadrant === 2) {
      return this.inputQ2;
    }
    if (quadrant === 3) {
      return this.inputQ3;
    }
    return this.inputQ4;
  }

  private setInput(quadrant: number, value: string): void {
    if (quadrant === 1) {
      this.inputQ1 = value;
    } else if (quadrant === 2) {
      this.inputQ2 = value;
    } else if (quadrant === 3) {
      this.inputQ3 = value;
    } else {
      this.inputQ4 = value;
    }
  }

  private quadBg(quadrant: number): Resource {
    if (quadrant === 1) {
      return $r('app.color.q1_bg');
    }
    if (quadrant === 2) {
      return $r('app.color.q2_bg');
    }
    if (quadrant === 3) {
      return $r('app.color.q3_bg');
    }
    return $r('app.color.q4_bg');
  }

  private subtitle(): string {
    const parts: string[] = [this.account.name];
    if (this.tasks.length === 0) {
      parts.push('把事放进格子里，脑子就空出来了');
    } else {
      parts.push(`${this.tasks.length} 项待办`);
      if (this.settings.showCompletedToday) {
        parts.push(`今日完成 ${this.completedToday}`);
      }
    }
    return parts.join(' · ');
  }

  /* ==================== 账号 ==================== */

  private async switchAccount(id: number): Promise<void> {
    if (id === this.account.id) {
      this.showAccount = false;
      return;
    }
    try {
      await AccountStore.switchTo(id);
      this.account = AccountStore.active();
      TaskRepository.getInstance().useAccount(this.account.id);
      this.accounts = AccountStore.all();
      this.showAccount = false;
      await this.afterChange();
      this.toast(`已切换到「${this.account.name}」`);
    } catch (err) {
      this.toast('切换失败：' + (err as Error).message);
    }
  }

  private async createAccount(): Promise<void> {
    const name: string = this.newName.trim();
    if (name.length === 0) {
      this.toast('请输入账号名称');
      return;
    }
    try {
      const created: Account = await AccountStore.create(name, this.newColorIndex);
      this.newName = '';
      this.newColorIndex = (created.colorIndex + 1) % AVATAR_COLORS.length;
      this.accounts = AccountStore.all();
      await this.switchAccount(created.id);
    } catch (err) {
      this.toast('创建失败：' + (err as Error).message);
    }
  }

  private async commitRename(id: number): Promise<void> {
    const name: string = this.renameText.trim();
    if (name.length === 0) {
      this.toast('名称不能为空');
      return;
    }
    try {
      await AccountStore.rename(id, name);
      this.accounts = AccountStore.all();
      this.account = AccountStore.active();
      this.renameId = 0;
      this.renameText = '';
      await WidgetBridge.refreshAll(this.ctx);
    } catch (err) {
      this.toast('重命名失败：' + (err as Error).message);
    }
  }

  private confirmDeleteAccount(acc: Account): void {
    this.getUIContext().showAlertDialog({
      title: '删除账号',
      message: `将删除「${acc.name}」及其全部任务，不可恢复。`,
      autoCancel: true,
      primaryButton: {
        value: '取消',
        action: () => {
        }
      },
      secondaryButton: {
        value: '删除',
        fontColor: $r('app.color.danger'),
        action: () => {
          this.doDeleteAccount(acc);
        }
      }
    });
  }

  private async doDeleteAccount(acc: Account): Promise<void> {
    try {
      const removed: boolean = await AccountStore.remove(acc.id);
      if (!removed) {
        this.toast('至少保留一个账号');
        return;
      }
      const repo: TaskRepository = TaskRepository.getInstance();
      await repo.clearAccount(acc.id);
      this.account = AccountStore.active();
      repo.useAccount(this.account.id);
      this.accounts = AccountStore.all();
      await this.afterChange();
      this.toast('账号已删除');
    } catch (err) {
      this.toast('删除失败：' + (err as Error).message);
    }
  }

  /* ==================== 设置 ==================== */

  private applyColorMode(mode: number): void {
    if (this.ctx === undefined) {
      return;
    }
    let target: ConfigurationConstant.ColorMode = ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET;
    if (mode === MODE_DARK) {
      target = ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
    } else if (mode === MODE_LIGHT) {
      target = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
    }
    try {
      this.ctx.getApplicationContext().setColorMode(target);
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'setColorMode failed: %{public}s', (err as Error).message);
    }
  }

  private async saveSettings(next: AppSettings, appearanceChanged: boolean): Promise<void> {
    const previous: AppSettings = this.settings;
    this.settings = next;
    try {
      await SettingsStore.save(next);
    } catch (err) {
      this.toast('保存设置失败：' + (err as Error).message);
      return;
    }
    if (appearanceChanged) {
      this.applyColorMode(next.colorMode);
    }
    if (previous.sortMode !== next.sortMode) {
      await this.reload();
    }
    await WidgetBridge.refreshAll(this.ctx);
  }

  private changeQuadrantSettings(key: number): void {
    const next: AppSettings = this.settings.copy();
    next.defaultQuadrant = key;
    this.saveSettings(next, false);
  }

  private changeSortMode(key: number): void {
    const next: AppSettings = this.settings.copy();
    next.sortMode = key;
    this.saveSettings(next, false);
  }

  private changeColorMode(key: number): void {
    const next: AppSettings = this.settings.copy();
    next.colorMode = key;
    this.saveSettings(next, true);
  }

  private changeWidgetLines(key: number): void {
    const next: AppSettings = this.settings.copy();
    next.widgetLines = key;
    this.saveSettings(next, false);
  }

  private toggleShowDone(isOn: boolean): void {
    const next: AppSettings = this.settings.copy();
    next.showCompletedToday = isOn;
    this.saveSettings(next, false);
  }

  private confirmClearAll(): void {
    this.getUIContext().showAlertDialog({
      title: '清空本账号',
      message: `将删除「${this.account.name}」下的全部任务（含未完成），不可恢复。`,
      autoCancel: true,
      primaryButton: {
        value: '取消',
        action: () => {
        }
      },
      secondaryButton: {
        value: '清空',
        fontColor: $r('app.color.danger'),
        action: () => {
          this.doClearAll();
        }
      }
    });
  }

  private async doClearAll(): Promise<void> {
    try {
      await TaskRepository.getInstance().clearAll();
      await this.afterChange();
      this.toast('已清空');
    } catch (err) {
      this.toast('清空失败：' + (err as Error).message);
    }
  }

  /* ==================== 操作 ==================== */

  private async addTask(quadrant: number, raw: string): Promise<void> {
    const title: string = raw.trim();
    if (title.length === 0) {
      return;
    }
    try {
      await TaskRepository.getInstance().insert(title, quadrant, 0, false);
      this.setInput(quadrant, '');
      await this.afterChange();
    } catch (err) {
      this.toast('添加失败：' + (err as Error).message);
    }
  }

  private async toggle(item: TaskItem): Promise<void> {
    try {
      await TaskRepository.getInstance().setCompleted(item.id, !item.completed);
      await this.afterChange();
    } catch (err) {
      this.toast('更新失败：' + (err as Error).message);
    }
  }

  private openEditor(item?: TaskItem): void {
    if (item !== undefined) {
      this.editingId = item.id;
      this.draftTitle = item.title;
      this.draftQuadrant = item.quadrant;
      this.draftDue = item.dueAt;
      this.draftImportant = item.important;
      this.draftDate = new Date(item.dueAt > 0 ? item.dueAt : Date.now());
    } else {
      this.editingId = 0;
      this.draftTitle = '';
      this.draftQuadrant = this.settings.defaultQuadrant;
      this.draftDue = 0;
      this.draftImportant = false;
      this.draftDate = new Date();
    }
    this.showCalendar = false;
    this.showEditor = true;
  }

  private async saveDraft(): Promise<void> {
    const title: string = this.draftTitle.trim();
    if (title.length === 0) {
      this.toast('标题不能为空');
      return;
    }
    const repo: TaskRepository = TaskRepository.getInstance();
    try {
      if (this.editingId > 0) {
        await repo.updateFields(this.editingId, title, this.draftQuadrant, this.draftDue, this.draftImportant);
      } else {
        await repo.insert(title, this.draftQuadrant, this.draftDue, this.draftImportant);
      }
      this.showEditor = false;
      await this.afterChange();
    } catch (err) {
      this.toast('保存失败：' + (err as Error).message);
    }
  }

  private confirmDelete(id: number, title: string): void {
    this.getUIContext().showAlertDialog({
      title: '删除任务',
      message: `确定删除「${title}」？删除后不可恢复。`,
      autoCancel: true,
      primaryButton: {
        value: '取消',
        action: () => {
        }
      },
      secondaryButton: {
        value: '删除',
        fontColor: $r('app.color.danger'),
        action: () => {
          this.doDelete(id);
        }
      }
    });
  }

  private async doDelete(id: number): Promise<void> {
    try {
      await TaskRepository.getInstance().remove(id);
      this.showEditor = false;
      await this.afterChange();
    } catch (err) {
      this.toast('删除失败：' + (err as Error).message);
    }
  }

  private confirmClearCompleted(): void {
    if (this.completedToday === 0) {
      this.toast('暂无可清理的已完成任务');
      return;
    }
    this.getUIContext().showAlertDialog({
      title: '清理已完成',
      message: '将永久删除全部已完成任务，是否继续？',
      autoCancel: true,
      primaryButton: {
        value: '取消',
        action: () => {
        }
      },
      secondaryButton: {
        value: '清理',
        fontColor: $r('app.color.danger'),
        action: () => {
          this.doClearCompleted();
        }
      }
    });
  }

  private async doClearCompleted(): Promise<void> {
    try {
      await TaskRepository.getInstance().clearCompleted();
      await this.afterChange();
      this.toast('已清理');
    } catch (err) {
      this.toast('清理失败：' + (err as Error).message);
    }
  }

  /** 截止日期快捷项：offsetDays < 0 代表「清除」 */
  private isDuePicked(offsetDays: number): boolean {
    if (offsetDays < 0) {
      return this.draftDue === 0;
    }
    if (this.draftDue <= 0) {
      return false;
    }
    return DateUtil.startOfDay(this.draftDue) === DateUtil.dayOffset(offsetDays);
  }

  /* ==================== 视图 ==================== */

  @Builder
  AvatarView(acc: Account, size: number) {
    Text(accountInitial(acc.name))
      .fontSize(size * 0.42)
      .fontWeight(FontWeight.Medium)
      .fontColor('#FFFFFF')
      .width(size)
      .height(size)
      .textAlign(TextAlign.Center)
      .borderRadius(size / 2)
      .backgroundColor(avatarColor(acc.colorIndex))
  }

  @Builder
  Header() {
    Row() {
      Stack() {
        this.AvatarView(this.account, 34)
      }
      .onClick(() => {
        this.showAccount = true;
      })

      Column() {
        Text('四象限待办')
          .fontSize(19)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.fg'))
        Text(this.subtitle())
          .fontSize(10)
          .fontColor($r('app.color.muted'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ top: 3 })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      .margin({ left: 9 })

      Text('尺子')
        .fontSize(11)
        .fontColor($r('app.color.accent'))
        .padding({ left: 9, right: 9, top: 6, bottom: 6 })
        .backgroundColor($r('app.color.accent_soft'))
        .borderRadius(13)
        .onClick(() => {
          this.showRuler = true;
        })

      Text('已完成')
        .fontSize(11)
        .fontColor($r('app.color.fg'))
        .padding({ left: 9, right: 9, top: 6, bottom: 6 })
        .backgroundColor($r('app.color.card'))
        .borderRadius(13)
        .margin({ left: 5 })
        .onClick(() => {
          this.openDone();
        })

      Text('⚙')
        .fontSize(15)
        .fontColor($r('app.color.fg'))
        .width(30)
        .height(28)
        .textAlign(TextAlign.Center)
        .backgroundColor($r('app.color.card'))
        .borderRadius(13)
        .margin({ left: 5 })
        .onClick(() => {
          this.showSettings = true;
        })
    }
    .width('100%')
    .padding({ left: 14, right: 14, top: 12, bottom: 8 })
  }

  @Builder
  Board() {
    Column({ space: 8 }) {
      Row({ space: 8 }) {
        this.QuadrantCell(QUADRANTS[0])
        this.QuadrantCell(QUADRANTS[1])
      }
      .width('100%')
      .layoutWeight(1)

      Row({ space: 8 }) {
        this.QuadrantCell(QUADRANTS[2])
        this.QuadrantCell(QUADRANTS[3])
      }
      .width('100%')
      .layoutWeight(1)
    }
    .width('100%')
    .layoutWeight(1)
    .padding({ left: 12, right: 12 })
  }

  @Builder
  QuadrantCell(meta: QuadrantMeta) {
    Column() {
      Row() {
        Text(meta.name)
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.fg'))
        Blank()
        Text(this.tasksOf(meta.key).length.toString())
          .fontSize(11)
          .fontColor($r('app.color.muted'))
      }
      .width('100%')
      .padding({ left: 2, right: 2 })

      if (this.tasksOf(meta.key).length === 0) {
        Column() {
          Text(meta.hint)
            .fontSize(11)
            .fontColor($r('app.color.muted'))
            .textAlign(TextAlign.Center)
            .opacity(0.8)
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        List({ space: 5 }) {
          ForEach(this.tasksOf(meta.key), (item: TaskItem) => {
            ListItem() {
              this.TaskCard(item)
            }
          }, (item: TaskItem) => `task-${item.id}`)
        }
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Off)
        .padding({ top: 6 })
      }

      Row() {
        TextInput({ placeholder: '添加任务…', text: this.inputOf(meta.key) })
          .placeholderColor($r('app.color.muted'))
          .placeholderFont({ size: 12 })
          .fontSize(12)
          .fontColor($r('app.color.fg'))
          .height(32)
          .layoutWeight(1)
          .backgroundColor($r('app.color.card'))
          .borderRadius(8)
          .padding({ left: 8, right: 8 })
          .onChange((value: string) => {
            this.setInput(meta.key, value);
          })
          .onSubmit(() => {
            this.addTask(meta.key, this.inputOf(meta.key));
          })

        Button() {
          Text('＋')
            .fontSize(17)
            .fontColor($r('app.color.on_accent'))
            .fontWeight(FontWeight.Medium)
        }
        .width(32)
        .height(32)
        .borderRadius(16)
        .backgroundColor($r('app.color.accent'))
        .margin({ left: 6 })
        .onClick(() => {
          this.addTask(meta.key, this.inputOf(meta.key));
        })
      }
      .width('100%')
      .margin({ top: 6 })
    }
    .layoutWeight(1)
    .height('100%')
    .padding(8)
    .borderRadius(16)
    .backgroundColor(this.quadBg(meta.key))
    .clip(true)
  }

  @Builder
  TaskCard(item: TaskItem) {
    Row() {
      Stack() {
        if (item.completed) {
          Text('✓')
            .fontSize(11)
            .fontColor($r('app.color.on_accent'))
        }
      }
      .width(18)
      .height(18)
      .borderRadius(9)
      .backgroundColor(item.completed ? $r('app.color.accent') : $r('app.color.transparent'))
      .border({
        width: 1.5,
        color: item.completed ? $r('app.color.accent') : $r('app.color.border')
      })
      .margin({ top: 1 })
      .onClick(() => {
        this.toggle(item);
      })

      Column() {
        Text(item.title)
          .fontSize(13)
          .fontColor(item.completed ? $r('app.color.muted') : $r('app.color.fg'))
          .decoration({
            type: item.completed ? TextDecorationType.LineThrough : TextDecorationType.None,
            color: $r('app.color.muted')
          })
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')

        if (item.dueAt > 0 || item.important) {
          Row() {
            if (item.important) {
              Text('★')
                .fontSize(10)
                .fontColor($r('app.color.danger'))
                .margin({ right: 3 })
            }
            if (item.dueAt > 0) {
              Text(DateUtil.dueLabel(item.dueAt))
                .fontSize(10)
                .fontColor(DateUtil.isOverdue(item.dueAt) ? $r('app.color.danger') : $r('app.color.muted'))
            }
          }
          .margin({ top: 2 })
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      .margin({ left: 6 })
    }
    .width('100%')
    .padding({ left: 7, right: 7, top: 6, bottom: 6 })
    .backgroundColor($r('app.color.card'))
    .borderRadius(8)
    .border({ width: 0.5, color: $r('app.color.border') })
    .onClick(() => {
      this.openEditor(item);
    })
    .gesture(
      LongPressGesture({ repeat: false })
        .onAction(() => {
          this.confirmDelete(item.id, item.title);
        })
    )
  }

  @Builder
  BottomBar() {
    Row() {
      Button() {
        Row({ space: 6 }) {
          Text('＋')
            .fontSize(17)
            .fontColor($r('app.color.on_accent'))
          Text('新建任务')
            .fontSize(14)
            .fontColor($r('app.color.on_accent'))
        }
      }
      .width('100%')
      .height(44)
      .borderRadius(22)
      .backgroundColor($r('app.color.accent'))
      .onClick(() => {
        this.openEditor();
      })
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 2, bottom: 10 })
  }

  @Builder
  DueChip(label: string, offsetDays: number) {
    Text(label)
      .fontSize(12)
      .fontColor(this.isDuePicked(offsetDays) ? $r('app.color.on_accent') : $r('app.color.fg'))
      .padding({ left: 12, right: 12, top: 6, bottom: 6 })
      .backgroundColor(this.isDuePicked(offsetDays) ? $r('app.color.accent') : $r('app.color.bg'))
      .borderRadius(12)
      .margin({ right: 8, bottom: 8 })
      .onClick(() => {
        this.draftDue = offsetDays < 0 ? 0 : DateUtil.dayOffset(offsetDays);
        if (offsetDays >= 0) {
          this.draftDate = new Date(this.draftDue);
        }
        this.showCalendar = false;
      })
  }

  @Builder
  EditorPanel() {
    Stack({ alignContent: Alignment.Bottom }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor($r('app.color.scrim'))
        .onClick(() => {
          this.showEditor = false;
        })

      Column() {
        Row() {
          Text(this.editingId > 0 ? '编辑任务' : '新建任务')
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.fg'))
          Blank()
          Text('✕')
            .fontSize(16)
            .fontColor($r('app.color.muted'))
            .padding(6)
            .onClick(() => {
              this.showEditor = false;
            })
        }
        .width('100%')

        TextInput({ placeholder: '要做什么？', text: this.draftTitle })
          .fontSize(15)
          .fontColor($r('app.color.fg'))
          .placeholderColor($r('app.color.muted'))
          .height(44)
          .backgroundColor($r('app.color.bg'))
          .borderRadius(10)
          .padding({ left: 10, right: 10 })
          .margin({ top: 12 })
          .onChange((value: string) => {
            this.draftTitle = value;
          })

        Text('放在哪个象限')
          .fontSize(12)
          .fontColor($r('app.color.muted'))
          .width('100%')
          .margin({ top: 16 })

        Flex({ wrap: FlexWrap.Wrap }) {
          ForEach(QUADRANTS, (meta: QuadrantMeta) => {
            Text(meta.name)
              .fontSize(12)
              .fontColor(this.draftQuadrant === meta.key ? $r('app.color.on_accent') : $r('app.color.fg'))
              .padding({ left: 12, right: 12, top: 6, bottom: 6 })
              .backgroundColor(this.draftQuadrant === meta.key ? $r('app.color.accent') : this.quadBg(meta.key))
              .borderRadius(12)
              .margin({ right: 8, top: 8 })
              .onClick(() => {
                this.draftQuadrant = meta.key;
              })
          }, (meta: QuadrantMeta) => `pick-${meta.key}`)
        }
        .width('100%')

        Row() {
          Text('截止日期')
            .fontSize(12)
            .fontColor($r('app.color.muted'))
            .layoutWeight(1)
          Text(this.draftDue > 0 ? DateUtil.dueLabel(this.draftDue) : '未设置')
            .fontSize(12)
            .fontColor(DateUtil.isOverdue(this.draftDue) ? $r('app.color.danger') : $r('app.color.fg'))
        }
        .width('100%')
        .margin({ top: 16 })

        Flex({ wrap: FlexWrap.Wrap }) {
          this.DueChip('今天', 0)
          this.DueChip('明天', 1)
          this.DueChip('后天', 2)
          this.DueChip('清除', -1)
          Text(this.showCalendar ? '收起日历' : '选日期')
            .fontSize(12)
            .fontColor($r('app.color.accent'))
            .padding({ left: 12, right: 12, top: 6, bottom: 6 })
            .backgroundColor($r('app.color.accent_soft'))
            .borderRadius(12)
            .margin({ right: 8, bottom: 8 })
            .onClick(() => {
              this.showCalendar = !this.showCalendar;
            })
        }
        .width('100%')
        .margin({ top: 8 })

        if (this.showCalendar) {
          CalendarPicker({ hintRadius: 12, selected: this.draftDate })
            .width('100%')
            .onChange((value: Date) => {
              this.draftDate = value;
              this.draftDue = DateUtil.startOfDay(value.getTime());
            })
        }

        Row() {
          Text('标记为重要')
            .fontSize(13)
            .fontColor($r('app.color.fg'))
            .layoutWeight(1)
          Toggle({ type: ToggleType.Switch, isOn: this.draftImportant })
            .selectedColor($r('app.color.accent'))
            .onChange((isOn: boolean) => {
              this.draftImportant = isOn;
            })
        }
        .width('100%')
        .margin({ top: 14 })

        Row({ space: 10 }) {
          if (this.editingId > 0) {
            Button() {
              Text('删除')
                .fontSize(14)
                .fontColor($r('app.color.danger'))
            }
            .layoutWeight(1)
            .height(44)
            .backgroundColor($r('app.color.bg'))
            .onClick(() => {
              this.confirmDelete(this.editingId, this.draftTitle);
            })
          }
          Button() {
            Text(this.editingId > 0 ? '保存' : '添加')
              .fontSize(14)
              .fontColor($r('app.color.on_accent'))
          }
          .layoutWeight(1)
          .height(44)
          .backgroundColor($r('app.color.accent'))
          .onClick(() => {
            this.saveDraft();
          })
        }
        .width('100%')
        .margin({ top: 18 })
      }
      .width('100%')
      .padding({ left: 18, right: 18, top: 18, bottom: 22 })
      .backgroundColor($r('app.color.card'))
      .borderRadius({ topLeft: 20, topRight: 20 })
      .constraintSize({ maxHeight: '92%' })
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  RulerSection(title: string, body: string) {
    Column({ space: 4 }) {
      Text(title)
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.fg'))
      Text(body)
        .fontSize(12)
        .fontColor($r('app.color.muted'))
        .lineHeight(19)
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
  }

  @Builder
  RulerPanel() {
    Stack({ alignContent: Alignment.Bottom }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor($r('app.color.scrim'))
        .onClick(() => {
          this.showRuler = false;
        })

      Column() {
        Row() {
          Text('归类尺子')
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.fg'))
          Blank()
          Text('✕')
            .fontSize(16)
            .fontColor($r('app.color.muted'))
            .padding(6)
            .onClick(() => {
              this.showRuler = false;
            })
        }
        .width('100%')

        Scroll() {
          Column({ space: 14 }) {
            this.RulerSection('重要',
              '会影响钱、岗位、口碑、健康、长期可积累技能的，一律算重要。判断标准是「半年后还重不重要」，而不是「现在有没有人催」。')
            this.RulerSection('不重要',
              '可代劳、可拒绝、对上面几项几乎无影响的事务性琐事。这类事做得再漂亮，也不会改变你的处境。')
            this.RulerSection('紧急',
              '有硬性截止时间，或者再拖下去会真的出问题（罚款、误机、关系破裂、身体报警）。')
            this.RulerSection('不紧急',
              '没有硬截止，但拖久了会让「重要不紧急」变成「重要紧急」。这是大多数人长期焦虑的真正来源。')

            Column({ space: 8 }) {
              Text('四格怎么用')
                .fontSize(13)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.fg'))
              ForEach(QUADRANTS, (meta: QuadrantMeta) => {
                Row() {
                  Text(meta.name)
                    .fontSize(12)
                    .fontColor($r('app.color.fg'))
                    .width(88)
                  Text(meta.hint)
                    .fontSize(12)
                    .fontColor($r('app.color.muted'))
                    .layoutWeight(1)
                }
                .width('100%')
                .alignItems(VerticalAlign.Top)
              }, (meta: QuadrantMeta) => `rule-${meta.key}`)
            }
            .alignItems(HorizontalAlign.Start)
            .width('100%')

            Text('口诀：上午啃「重要不紧急」；中午到下午清「重要紧急」；碎片时间批量处理「紧急不重要」；第四格只在闲时碰。')
              .fontSize(12)
              .fontColor($r('app.color.muted'))
              .lineHeight(19)
              .width('100%')
          }
          .alignItems(HorizontalAlign.Start)
          .width('100%')
          .padding({ top: 12 })
        }
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Off)

        Row({ space: 10 }) {
          Text('清理已完成')
            .fontSize(12)
            .fontColor($r('app.color.danger'))
            .padding({ left: 12, right: 12, top: 8, bottom: 8 })
            .backgroundColor($r('app.color.bg'))
            .borderRadius(12)
            .onClick(() => {
              this.confirmClearCompleted();
            })
          Text('桌面卡片')
            .fontSize(12)
            .fontColor($r('app.color.accent'))
            .padding({ left: 12, right: 12, top: 8, bottom: 8 })
            .backgroundColor($r('app.color.accent_soft'))
            .borderRadius(12)
            .onClick(() => {
              this.showRuler = false;
              this.showSettings = true;
            })
        }
        .width('100%')
        .margin({ top: 12 })
      }
      .width('100%')
      .height('62%')
      .padding({ left: 18, right: 18, top: 18, bottom: 22 })
      .backgroundColor($r('app.color.card'))
      .borderRadius({ topLeft: 20, topRight: 20 })
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  DonePanel() {
    Stack({ alignContent: Alignment.Bottom }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor($r('app.color.scrim'))
        .onClick(() => {
          this.showDone = false;
        })

      Column() {
        Row() {
          Text('已完成')
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.fg'))
          Text(` ${this.doneTasks.length} 项`)
            .fontSize(12)
            .fontColor($r('app.color.muted'))
            .layoutWeight(1)
          Text('✕')
            .fontSize(16)
            .fontColor($r('app.color.muted'))
            .padding(6)
            .onClick(() => {
              this.showDone = false;
            })
        }
        .width('100%')

        if (this.doneTasks.length === 0) {
          Column() {
            Text('还没有已完成的任务')
              .fontSize(12)
              .fontColor($r('app.color.muted'))
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else {
          List({ space: 0 }) {
            ForEach(this.doneTasks, (item: TaskItem) => {
              ListItem() {
                Row() {
                  Text(item.title)
                    .fontSize(13)
                    .fontColor($r('app.color.muted'))
                    .decoration({ type: TextDecorationType.LineThrough, color: $r('app.color.muted') })
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                    .layoutWeight(1)

                  Text('恢复')
                    .fontSize(11)
                    .fontColor($r('app.color.accent'))
                    .padding({ left: 10, right: 10, top: 5, bottom: 5 })
                    .backgroundColor($r('app.color.accent_soft'))
                    .borderRadius(10)
                    .onClick(() => {
                      this.restoreTask(item);
                    })

                  Text('删除')
                    .fontSize(11)
                    .fontColor($r('app.color.danger'))
                    .padding({ left: 10, right: 10, top: 5, bottom: 5 })
                    .backgroundColor($r('app.color.bg'))
                    .borderRadius(10)
                    .margin({ left: 6 })
                    .onClick(() => {
                      this.confirmDelete(item.id, item.title);
                    })
                }
                .width('100%')
                .padding({ top: 9, bottom: 9 })
                .border({ width: { bottom: 0.5 }, color: $r('app.color.border') })
              }
            }, (item: TaskItem) => `done-${item.id}`)
          }
          .width('100%')
          .layoutWeight(1)
          .scrollBar(BarState.Off)
          .padding({ top: 6 })
        }
      }
      .width('100%')
      .height('62%')
      .padding({ left: 18, right: 18, top: 18, bottom: 22 })
      .backgroundColor($r('app.color.card'))
      .borderRadius({ topLeft: 20, topRight: 20 })
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  AccountPanel() {
    Stack({ alignContent: Alignment.Bottom }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor($r('app.color.scrim'))
        .onClick(() => {
          this.showAccount = false;
        })

      Column() {
        Row() {
          Text('账号')
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.fg'))
          Blank()
          Text('✕')
            .fontSize(16)
            .fontColor($r('app.color.muted'))
            .padding(6)
            .onClick(() => {
              this.showAccount = false;
            })
        }
        .width('100%')

        Text('每个账号有独立的四象限清单，数据只存在本机。')
          .fontSize(11)
          .fontColor($r('app.color.muted'))
          .width('100%')
          .margin({ top: 4 })

        Scroll() {
          Column({ space: 8 }) {
            ForEach(this.accounts, (acc: Account) => {
              Column() {
                Row() {
                  this.AvatarView(acc, 32)
                  Column() {
                    if (this.renameId === acc.id) {
                      TextInput({ text: this.renameText })
                        .fontSize(13)
                        .fontColor($r('app.color.fg'))
                        .height(32)
                        .backgroundColor($r('app.color.bg'))
                        .borderRadius(8)
                        .padding({ left: 8, right: 8 })
                        .onChange((value: string) => {
                          this.renameText = value;
                        })
                        .onSubmit(() => {
                          this.commitRename(acc.id);
                        })
                    } else {
                      Text(acc.name)
                        .fontSize(13)
                        .fontWeight(FontWeight.Medium)
                        .fontColor($r('app.color.fg'))
                        .maxLines(1)
                        .textOverflow({ overflow: TextOverflow.Ellipsis })
                    }
                    Text(acc.id === this.account.id ? '使用中' : '点击切换')
                      .fontSize(10)
                      .fontColor(acc.id === this.account.id ? $r('app.color.accent') : $r('app.color.muted'))
                      .margin({ top: 2 })
                  }
                  .alignItems(HorizontalAlign.Start)
                  .layoutWeight(1)
                  .margin({ left: 10 })

                  if (this.renameId === acc.id) {
                    Text('确定')
                      .fontSize(11)
                      .fontColor($r('app.color.on_accent'))
                      .padding({ left: 10, right: 10, top: 5, bottom: 5 })
                      .backgroundColor($r('app.color.accent'))
                      .borderRadius(10)
                      .onClick(() => {
                        this.commitRename(acc.id);
                      })
                  } else {
                    Text('改名')
                      .fontSize(11)
                      .fontColor($r('app.color.accent'))
                      .padding({ left: 10, right: 10, top: 5, bottom: 5 })
                      .backgroundColor($r('app.color.accent_soft'))
                      .borderRadius(10)
                      .onClick(() => {
                        this.renameId = acc.id;
                        this.renameText = acc.name;
                      })
                    if (this.accounts.length > 1) {
                      Text('删除')
                        .fontSize(11)
                        .fontColor($r('app.color.danger'))
                        .padding({ left: 10, right: 10, top: 5, bottom: 5 })
                        .backgroundColor($r('app.color.bg'))
                        .borderRadius(10)
                        .margin({ left: 6 })
                        .onClick(() => {
                          this.confirmDeleteAccount(acc);
                        })
                    }
                  }
                }
                .width('100%')
              }
              .width('100%')
              .padding(10)
              .borderRadius(12)
              .backgroundColor(acc.id === this.account.id ? $r('app.color.accent_soft') : $r('app.color.bg'))
              .onClick(() => {
                if (this.renameId !== acc.id) {
                  this.switchAccount(acc.id);
                }
              })
            }, (acc: Account) => `acc-${acc.id}`)

            Column({ space: 8 }) {
              Text('新建账号')
                .fontSize(12)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.fg'))
                .width('100%')

              TextInput({ placeholder: '账号名称，例如「工作」「家庭」', text: this.newName })
                .fontSize(13)
                .fontColor($r('app.color.fg'))
                .placeholderColor($r('app.color.muted'))
                .height(40)
                .backgroundColor($r('app.color.bg'))
                .borderRadius(10)
                .padding({ left: 10, right: 10 })
                .onChange((value: string) => {
                  this.newName = value;
                })
                .onSubmit(() => {
                  this.createAccount();
                })

              Row({ space: 8 }) {
                ForEach(AVATAR_COLORS, (color: string, index: number) => {
                  Text(accountInitial(this.newName))
                    .fontSize(11)
                    .fontColor('#FFFFFF')
                    .width(26)
                    .height(26)
                    .textAlign(TextAlign.Center)
                    .borderRadius(13)
                    .backgroundColor(color)
                    .border({
                      width: this.newColorIndex === index ? 2 : 0,
                      color: $r('app.color.fg')
                    })
                    .onClick(() => {
                      this.newColorIndex = index;
                    })
                }, (color: string, index: number) => `color-${color}-${index}`)
              }
              .width('100%')

              Button() {
                Text('创建并切换')
                  .fontSize(14)
                  .fontColor($r('app.color.on_accent'))
              }
              .width('100%')
              .height(42)
              .backgroundColor($r('app.color.accent'))
              .onClick(() => {
                this.createAccount();
              })
            }
            .width('100%')
            .padding(10)
            .borderRadius(12)
            .backgroundColor($r('app.color.bg'))
            .margin({ top: 4 })
          }
          .width('100%')
          .padding({ top: 10, bottom: 10 })
        }
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Off)
      }
      .width('100%')
      .height('80%')
      .padding({ left: 18, right: 18, top: 18, bottom: 22 })
      .backgroundColor($r('app.color.card'))
      .borderRadius({ topLeft: 20, topRight: 20 })
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  SectionTitle(text: string) {
    Text(text)
      .fontSize(12)
      .fontWeight(FontWeight.Medium)
      .fontColor($r('app.color.fg'))
      .width('100%')
      .margin({ top: 16 })
  }

  @Builder
  HintText(text: string) {
    Text(text)
      .fontSize(10)
      .fontColor($r('app.color.muted'))
      .width('100%')
      .margin({ top: 4 })
  }

  @Builder
  SettingsPanel() {
    Stack({ alignContent: Alignment.Bottom }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor($r('app.color.scrim'))
        .onClick(() => {
          this.showSettings = false;
        })

      Column() {
        Row() {
          Text('设置')
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.fg'))
          Blank()
          Text('✕')
            .fontSize(16)
            .fontColor($r('app.color.muted'))
            .padding(6)
            .onClick(() => {
              this.showSettings = false;
            })
        }
        .width('100%')

        Scroll() {
          Column() {
            this.SectionTitle('当前账号')
            Row() {
              this.AvatarView(this.account, 30)
              Column() {
                Text(this.account.name)
                  .fontSize(13)
                  .fontColor($r('app.color.fg'))
                Text('切换 / 新建账号')
                  .fontSize(10)
                  .fontColor($r('app.color.muted'))
                  .margin({ top: 2 })
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)
              .margin({ left: 9 })

              Text('管理')
                .fontSize(11)
                .fontColor($r('app.color.accent'))
                .padding({ left: 10, right: 10, top: 5, bottom: 5 })
                .backgroundColor($r('app.color.accent_soft'))
                .borderRadius(10)
                .onClick(() => {
                  this.showSettings = false;
                  this.showAccount = true;
                })
            }
            .width('100%')
            .padding(10)
            .borderRadius(12)
            .backgroundColor($r('app.color.bg'))
            .margin({ top: 8 })

            this.SectionTitle('新建任务的默认象限')
            Flex({ wrap: FlexWrap.Wrap }) {
              ForEach(QUADRANTS, (meta: QuadrantMeta) => {
                Text(meta.name)
                  .fontSize(12)
                  .fontColor(this.settings.defaultQuadrant === meta.key ?
                    $r('app.color.on_accent') : $r('app.color.fg'))
                  .padding({ left: 12, right: 12, top: 6, bottom: 6 })
                  .backgroundColor(this.settings.defaultQuadrant === meta.key ?
                    $r('app.color.accent') : this.quadBg(meta.key))
                  .borderRadius(12)
                  .margin({ right: 8, top: 8 })
                  .onClick(() => {
                    this.changeQuadrantSettings(meta.key);
                  })
              }, (meta: QuadrantMeta) => `def-${meta.key}`)
            }
            .width('100%')

            this.SectionTitle('任务排序')
            Flex({ wrap: FlexWrap.Wrap }) {
              ForEach(SORT_OPTIONS, (opt: SettingOption) => {
                Text(opt.label)
                  .fontSize(12)
                  .fontColor(this.settings.sortMode === opt.key ?
                    $r('app.color.on_accent') : $r('app.color.fg'))
                  .padding({ left: 12, right: 12, top: 6, bottom: 6 })
                  .backgroundColor(this.settings.sortMode === opt.key ?
                    $r('app.color.accent') : $r('app.color.bg'))
                  .borderRadius(12)
                  .margin({ right: 8, top: 8 })
                  .onClick(() => {
                    this.changeSortMode(opt.key);
                  })
              }, (opt: SettingOption) => `sort-${opt.key}`)
            }
            .width('100%')

            this.SectionTitle('外观')
            Flex({ wrap: FlexWrap.Wrap }) {
              ForEach(COLOR_MODE_OPTIONS, (opt: SettingOption) => {
                Text(opt.label)
                  .fontSize(12)
                  .fontColor(this.settings.colorMode === opt.key ?
                    $r('app.color.on_accent') : $r('app.color.fg'))
                  .padding({ left: 12, right: 12, top: 6, bottom: 6 })
                  .backgroundColor(this.settings.colorMode === opt.key ?
                    $r('app.color.accent') : $r('app.color.bg'))
                  .borderRadius(12)
                  .margin({ right: 8, top: 8 })
                  .onClick(() => {
                    this.changeColorMode(opt.key);
                  })
              }, (opt: SettingOption) => `mode-${opt.key}`)
            }
            .width('100%')
            this.HintText('切换后立即生效；「跟随系统」与系统深色模式同步。')

            Row() {
              Text('顶栏显示今日完成')
                .fontSize(13)
                .fontColor($r('app.color.fg'))
                .layoutWeight(1)
              Toggle({ type: ToggleType.Switch, isOn: this.settings.showCompletedToday })
                .selectedColor($r('app.color.accent'))
                .onChange((isOn: boolean) => {
                  this.toggleShowDone(isOn);
                })
            }
            .width('100%')
            .margin({ top: 16 })

            this.SectionTitle('大卡片（6*4）显示条数')
            Flex({ wrap: FlexWrap.Wrap }) {
              ForEach(WIDGET_LINE_OPTIONS, (opt: SettingOption) => {
                Text(opt.label)
                  .fontSize(12)
                  .fontColor(this.settings.widgetLines === opt.key ?
                    $r('app.color.on_accent') : $r('app.color.fg'))
                  .padding({ left: 12, right: 12, top: 6, bottom: 6 })
                  .backgroundColor(this.settings.widgetLines === opt.key ?
                    $r('app.color.accent') : $r('app.color.bg'))
                  .borderRadius(12)
                  .margin({ right: 8, top: 8 })
                  .onClick(() => {
                    this.changeWidgetLines(opt.key);
                  })
              }, (opt: SettingOption) => `lines-${opt.key}`)
            }
            .width('100%')
            this.HintText('长按桌面空白处 → 卡片 → 四象限待办，可选 4*4（方）与 6*4（宽幅，平板 / 2in1）。')

            this.SectionTitle('数据')
            Row({ space: 10 }) {
              Text('清理已完成')
                .fontSize(12)
                .fontColor($r('app.color.fg'))
                .padding({ left: 12, right: 12, top: 8, bottom: 8 })
                .backgroundColor($r('app.color.bg'))
                .borderRadius(12)
                .onClick(() => {
                  this.confirmClearCompleted();
                })
              Text('清空本账号')
                .fontSize(12)
                .fontColor($r('app.color.danger'))
                .padding({ left: 12, right: 12, top: 8, bottom: 8 })
                .backgroundColor($r('app.color.bg'))
                .borderRadius(12)
                .onClick(() => {
                  this.confirmClearAll();
                })
            }
            .width('100%')
            .margin({ top: 8 })

            this.SectionTitle('关于')
            Column({ space: 6 }) {
              Row() {
                Text('版本')
                  .fontSize(12)
                  .fontColor($r('app.color.muted'))
                  .layoutWeight(1)
                Text(APP_VERSION)
                  .fontSize(12)
                  .fontColor($r('app.color.fg'))
              }
              .width('100%')

              Row() {
                Text('存储')
                  .fontSize(12)
                  .fontColor($r('app.color.muted'))
                  .layoutWeight(1)
                Text('本机数据库（RDB）')
                  .fontSize(12)
                  .fontColor($r('app.color.fg'))
              }
              .width('100%')

              Row() {
                Text('卡片尺寸')
                  .fontSize(12)
                  .fontColor($r('app.color.muted'))
                  .layoutWeight(1)
                Text('4*4 / 6*4')
                  .fontSize(12)
                  .fontColor($r('app.color.fg'))
              }
              .width('100%')

              Text('任务与账号均不上传，卸载应用即清除全部数据。')
                .fontSize(10)
                .fontColor($r('app.color.muted'))
                .width('100%')
                .margin({ top: 4 })
            }
            .width('100%')
            .padding({ top: 8, bottom: 20 })
            .alignItems(HorizontalAlign.Start)
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
        }
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Off)
      }
      .width('100%')
      .height('86%')
      .padding({ left: 18, right: 18, top: 18, bottom: 22 })
      .backgroundColor($r('app.color.card'))
      .borderRadius({ topLeft: 20, topRight: 20 })
    }
    .width('100%')
    .height('100%')
  }

  build() {
    Stack() {
      Column() {
        this.Header()

        if (this.ready) {
          this.Board()
          this.BottomBar()
        } else {
          Column() {
            LoadingProgress()
              .width(30)
              .height(30)
              .color($r('app.color.accent'))
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.bg'))

      if (this.showEditor) {
        this.EditorPanel()
      }

      if (this.showRuler) {
        this.RulerPanel()
      }

      if (this.showDone) {
        this.DonePanel()
      }

      if (this.showAccount) {
        this.AccountPanel()
      }

      if (this.showSettings) {
        this.SettingsPanel()
      }
    }
    .width('100%')
    .height('100%')
  }
}
