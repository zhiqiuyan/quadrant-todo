import { common, ConfigurationConstant } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { webview } from '@kit.ArkWeb';
import { window } from '@kit.ArkUI';
import { QuadrantMeta, QUADRANTS, TaskItem, Q1 } from '../model/TaskItem';
import { Account } from '../model/Account';
import {
  AppSettings, COLOR_MODE_OPTIONS, MODE_DARK, MODE_LIGHT, MODE_SYSTEM, SettingOption,
  SORT_OPTIONS, WIDGET_LINE_OPTIONS
} from '../model/AppSettings';
import { MsSyncResult } from '../model/MsTodo';
import { TaskRepository } from '../data/TaskRepository';
import { AccountStore } from '../data/AccountStore';
import { SettingsStore } from '../data/SettingsStore';
import { WidgetBridge } from '../data/WidgetBridge';
import { MsAuthService } from '../data/MsAuthService';
import { MsSyncService } from '../data/MsSyncService';
import { HuaweiAuthService, HuaweiIdProfile } from '../data/HuaweiAuthService';
import { BackupService, BackupResult } from '../data/BackupService';
import { DateUtil } from '../common/DateUtil';

const DOMAIN: number = 0x0000;
const TAG: string = 'QuadrantTodo';
const APP_VERSION: string = '1.4.0';

/**
 * 输入框独立成组件。
 * 之前输入框直接写在页面里，每敲一个字都会把整页（四个格子 + 全部任务卡）重绘一次，
 * 中文输入法组词时尤其卡。抽成子组件后，打字只重绘这个输入框自己。
 */
@Component
struct QuickInput {
  @Link text: string;
  @Prop placeholder: string = '';
  @Prop boxHeight: number = 32;
  @Prop fontSize: number = 12;
  @Prop boxBg: ResourceColor = Color.Transparent;
  @Prop topMargin: number = 0;
  onCommit: () => void = () => {
  };

  build() {
    TextInput({ placeholder: this.placeholder, text: this.text })
      .placeholderColor($r('app.color.muted'))
      .placeholderFont({ size: this.fontSize })
      .fontSize(this.fontSize)
      .fontColor($r('app.color.fg'))
      .height(this.boxHeight)
      .width('100%')
      .borderRadius(10)
      .padding({ left: 8, right: 8 })
      .margin({ top: this.topMargin })
      .backgroundColor(this.boxBg)
      .onChange((value: string) => {
        this.text = value;
      })
      .onSubmit(() => {
        this.onCommit();
      })
  }
}


@Entry
@Component
struct Index {
  /** 未完成任务全集，四个格子按象限过滤渲染 */
  @State tasks: TaskItem[] = [];
  @State ready: boolean = false;
  @State completedToday: number = 0;

  /** 账号与设置（账号仅作数据维度，不再提供管理界面） */
  @State account: Account = new Account();
  @State settings: AppSettings = new AppSettings();
  @State showSettings: boolean = false;

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

  /** 微软 To Do 同步 */
  @State msConnected: boolean = false;
  @State msProfile: string = '';
  @State msClientIdInput: string = '';
  @State msAutoSync: boolean = true;
  @State msLastSync: string = '';
  @State msBusy: boolean = false;
  @State showMsLogin: boolean = false;
  @State msLoginUrl: string = '';
  private webCtrl: webview.WebviewController = new webview.WebviewController();

  /** 华为账号与云备份 */
  @State hwNickName: string = '';
  @State hwAvatar: string = '';
  @State hwOpenId: string = '';
  @State hwBusy: boolean = false;
  @State hwError: string = '';
  @State autoBackup: boolean = true;
  @State lastBackupText: string = '';
  @State backupBusy: boolean = false;

  /** 沉浸式安全区避让（vp） */
  @State topInset: number = 0;
  @State bottomInset: number = 0;

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
      this.account = AccountStore.active();

      const repo: TaskRepository = TaskRepository.getInstance();
      await repo.init(context);
      repo.useAccount(this.account.id);
      this.applyColorMode(this.settings.colorMode);
      this.refreshMsState();
      this.refreshHuaweiState();
      this.autoBackup = BackupService.autoEnabled();
      this.refreshBackupState();
      this.computeInsets();
      await this.reload();
      this.ready = true;
      if (this.msConnected && MsAuthService.autoSync()) {
        this.msBackgroundSync();
      }
      if (this.autoBackup && HuaweiAuthService.loggedIn()) {
        this.runAutoBackup();
      }
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'boot failed: %{public}s', (err as Error).message);
      this.toast('初始化失败：' + (err as Error).message);
    }
  }

  /** 读取状态栏/导航条高度，内容按安全区避让，背景延伸到状态栏 */
  private async computeInsets(): Promise<void> {
    if (this.ctx === undefined) {
      return;
    }
    try {
      const win: window.Window = await window.getLastWindow(this.ctx);
      const sysArea: window.AvoidArea =
        win.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
      const navArea: window.AvoidArea =
        win.getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR);
      this.topInset = this.getUIContext().px2vp(sysArea.topRect.height);
      this.bottomInset = this.getUIContext().px2vp(navArea.bottomRect.height);
    } catch (err) {
      this.topInset = 0;
      this.bottomInset = 0;
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

  /**
   * 任何写操作之后：只等本地库刷新（毫秒级）。
   * 卡片推送、微软同步、云备份全部延后到后台执行，
   * 否则「保存」要等好几秒（网络往返 + 卡片 IPC + 云端上传）才会有反应。
   */
  private async afterChange(): Promise<void> {
    await this.reload();
    this.scheduleSideWork();
  }

  private sideTimer: number = -1;

  /** 连续改动作业时只跑最后一次，避免每次都推卡片/备份 */
  private scheduleSideWork(): void {
    if (this.sideTimer !== -1) {
      clearTimeout(this.sideTimer);
    }
    this.sideTimer = setTimeout(() => {
      this.sideTimer = -1;
      this.runSideWork();
    }, 400);
  }

  private async runSideWork(): Promise<void> {
    try {
      await WidgetBridge.refreshAll(this.ctx);
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'widget refresh failed: %{public}s', (err as Error).message);
    }
    if (this.msConnected && MsAuthService.autoSync()) {
      this.msBackgroundSync();
    }
    if (this.autoBackup && this.ctx !== undefined) {
      BackupService.autoBackup(this.ctx);
    }
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

  private quadrantName(quadrant: number): string {
    for (let i = 0; i < QUADRANTS.length; i++) {
      if (QUADRANTS[i].key === quadrant) {
        return QUADRANTS[i].name;
      }
    }
    return '';
  }

  private statsLine(): string {
    const parts: string[] = [];
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
      const repo: TaskRepository = TaskRepository.getInstance();
      if (this.msConnected) {
        const all: TaskItem[] = await repo.listAll();
        for (let i = 0; i < all.length; i++) {
          await MsSyncService.recordDeletion(all[i]);
        }
      }
      await repo.clearAll();
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
    const id: number = this.editingId;
    const quadrant: number = this.draftQuadrant;
    const due: number = this.draftDue;
    const important: boolean = this.draftImportant;
    // 先收面板，手感上「点了就存」，写库在后面几毫秒完成
    this.showEditor = false;
    const repo: TaskRepository = TaskRepository.getInstance();
    try {
      if (id > 0) {
        await repo.updateFields(id, title, quadrant, due, important);
      } else {
        await repo.insert(title, quadrant, due, important);
      }
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
      const repo: TaskRepository = TaskRepository.getInstance();
      const removed: TaskItem | undefined = await repo.remove(id);
      if (removed !== undefined && this.msConnected) {
        await MsSyncService.recordDeletion(removed);
      }
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
      const repo: TaskRepository = TaskRepository.getInstance();
      if (this.msConnected) {
        const done: TaskItem[] = await repo.listCompleted(500);
        for (let i = 0; i < done.length; i++) {
          await MsSyncService.recordDeletion(done[i]);
        }
      }
      await repo.clearCompleted();
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

  /* ==================== 华为账号 ==================== */

  private refreshHuaweiState(): void {
    const profile: HuaweiIdProfile | undefined = HuaweiAuthService.stored();
    if (profile !== undefined) {
      this.hwOpenId = profile.openId;
      this.hwNickName = profile.nickName;
      this.hwAvatar = profile.avatarUri;
    } else {
      this.hwOpenId = '';
      this.hwNickName = '';
      this.hwAvatar = '';
    }
  }

  private async hwLogin(): Promise<void> {
    if (this.hwBusy) {
      return;
    }
    if (this.ctx === undefined) {
      this.hwError = '界面上下文未就绪，请稍后再试';
      return;
    }
    this.hwBusy = true;
    this.hwError = '';
    try {
      const profile: HuaweiIdProfile = await HuaweiAuthService.login(this.ctx);
      this.refreshHuaweiState();
      this.refreshBackupState();
      this.toast(profile.nickName.length > 0 ? `已登录：${profile.nickName}` : '华为账号已登录');
    } catch (err) {
      this.hwError = (err as Error).message;
      await this.showHwErrorDialog();
    } finally {
      this.hwBusy = false;
    }
  }

  /** 登录失败要能看懂原因：错误码 + 缺哪一步配置，而不是一闪而过的提示 */
  private async showHwErrorDialog(): Promise<void> {
    let extra: string = '';
    const configured: boolean = await HuaweiAuthService.clientIdConfigured();
    if (!configured) {
      extra = '\n\n另：module.json5 里的 client_id 还是空的。需要在 AppGallery Connect 创建应用、开通「账号服务」，' +
        '把 Client ID 填进 client_id 后重新打包安装。';
    }
    const code: number = HuaweiAuthService.lastCode;
    const codeText: string = code === 0 ? '' : `（错误码 ${code}）`;
    this.getUIContext().showAlertDialog({
      title: '华为账号登录失败',
      message: `${this.hwError}${codeText}${extra}`,
      autoCancel: true,
      confirm: {
        value: '知道了',
        action: () => {
        }
      }
    });
  }

  private async hwLogout(): Promise<void> {
    try {
      if (this.ctx !== undefined) {
        await HuaweiAuthService.logout(this.ctx);
      }
      this.refreshHuaweiState();
      this.refreshBackupState();
      this.hwError = '';
      this.toast('已退出华为账号');
    } catch (err) {
      this.toast((err as Error).message);
    }
  }

  /* ==================== 云备份 ==================== */

  private refreshBackupState(): void {
    this.lastBackupText = BackupService.lastBackupText();
  }

  private async runAutoBackup(): Promise<void> {
    if (this.ctx === undefined) {
      return;
    }
    await BackupService.autoBackup(this.ctx);
    this.refreshBackupState();
  }

  private async doBackupNow(): Promise<void> {
    if (this.backupBusy || this.ctx === undefined) {
      return;
    }
    this.backupBusy = true;
    try {
      const result: BackupResult = await BackupService.backup(this.ctx);
      this.refreshBackupState();
      this.toast(result.message);
    } finally {
      this.backupBusy = false;
    }
  }

  private async doRestore(): Promise<void> {
    if (this.backupBusy || this.ctx === undefined) {
      return;
    }
    this.backupBusy = true;
    try {
      const result: BackupResult = await BackupService.restore(this.ctx);
      if (result.ok) {
        await this.afterChange();
      }
      this.toast(result.message);
    } finally {
      this.backupBusy = false;
    }
  }

  /** 导出到本地文件：不依赖华为账号 */
  private async doExportFile(): Promise<void> {
    if (this.backupBusy || this.ctx === undefined) {
      return;
    }
    this.backupBusy = true;
    try {
      const result: BackupResult = await BackupService.exportToFile(this.ctx);
      this.toast(result.message);
    } finally {
      this.backupBusy = false;
    }
  }

  /** 从本地文件恢复 */
  private async doImportFile(): Promise<void> {
    if (this.backupBusy || this.ctx === undefined) {
      return;
    }
    this.backupBusy = true;
    try {
      const result: BackupResult = await BackupService.importFromFile(this.ctx);
      if (result.ok) {
        await this.afterChange();
      }
      this.toast(result.message);
    } finally {
      this.backupBusy = false;
    }
  }

  private async toggleAutoBackup(on: boolean): Promise<void> {
    this.autoBackup = on;
    try {
      await BackupService.setAutoEnabled(on);
    } catch (err) {
      this.toast('保存失败：' + (err as Error).message);
    }
  }

  /* ==================== 微软 To Do ==================== */

  /** 读取当前账号的微软连接状态到界面 */
  private refreshMsState(): void {
    MsAuthService.bind(this.account.id);
    this.msConnected = MsAuthService.connected();
    this.msProfile = MsAuthService.profileName();
    this.msClientIdInput = MsAuthService.clientId();
    this.msAutoSync = MsAuthService.autoSync();
    this.msLastSync = MsAuthService.lastSync();
  }

  /** 后台静默同步：只在失败时提示，不抢焦点 */
  private msSyncGuard: number = 0;

  private async msBackgroundSync(): Promise<void> {
    if (this.msBusy || !MsAuthService.connected()) {
      return;
    }
    const now: number = Date.now();
    // 15s 内不重复触发：连续编辑时不要每次都打一轮网络同步
    if (now - this.msSyncGuard < 15000) {
      return;
    }
    this.msSyncGuard = now;
    this.msBusy = true;
    try {
      const result: MsSyncResult = await MsSyncService.sync();
      this.msLastSync = MsAuthService.lastSync();
      if (result.failed > 0) {
        this.toast(result.message);
      }
      await this.reload();
    } finally {
      this.msBusy = false;
    }
  }

  private async msSyncNow(): Promise<void> {
    if (this.msBusy) {
      return;
    }
    if (!this.msConnected) {
      this.toast('请先连接微软账号');
      return;
    }
    this.msBusy = true;
    try {
      const result: MsSyncResult = await MsSyncService.sync();
      this.msLastSync = MsAuthService.lastSync();
      this.toast(result.message);
      await this.reload();
    } finally {
      this.msBusy = false;
    }
  }

  private openMsLogin(): void {
    if (!MsAuthService.hasClientId()) {
      this.toast('请先填写并保存 Azure 应用 Client ID');
      return;
    }
    this.msLoginUrl = MsAuthService.authorizeUrl();
    this.showMsLogin = true;
  }

  /** Web 拦截：命中回调地址则阻断加载并接管 code */
  private onWebNav(url: string): boolean {
    if (MsAuthService.isRedirectUrl(url)) {
      this.showMsLogin = false;
      this.finishMsLogin(url);
      return true;
    }
    return false;
  }

  private async finishMsLogin(url: string): Promise<void> {
    this.msBusy = true;
    try {
      await MsAuthService.completeLogin(url);
      this.refreshMsState();
      this.toast(`已连接 ${this.msProfile.length > 0 ? this.msProfile : '微软账号'}`);
      const result: MsSyncResult = await MsSyncService.initialPush();
      this.msLastSync = MsAuthService.lastSync();
      if (result.failed > 0 || result.pushed > 0) {
        this.toast(result.message);
      }
      await this.reload();
    } catch (err) {
      this.toast((err as Error).message);
    } finally {
      this.msBusy = false;
    }
  }

  private async saveMsClientId(): Promise<void> {
    try {
      await MsAuthService.setClientId(this.msClientIdInput);
      this.msClientIdInput = MsAuthService.clientId();
      this.toast('Client ID 已保存');
    } catch (err) {
      this.toast('保存失败：' + (err as Error).message);
    }
  }

  private async toggleMsAutoSync(isOn: boolean): Promise<void> {
    this.msAutoSync = isOn;
    try {
      await MsAuthService.setAutoSync(isOn);
    } catch (err) {
      this.toast('保存失败：' + (err as Error).message);
    }
  }

  private async msDisconnect(): Promise<void> {
    try {
      await MsAuthService.disconnect();
      this.refreshMsState();
      this.toast('已断开微软账号');
    } catch (err) {
      this.toast('断开失败：' + (err as Error).message);
    }
  }

  /* ==================== 视图 ==================== */

  /** 纯平面的「设置」图标：三条带滑块的横线（不用彩色 emoji 字形，避免 3D 拟真感） */
  @Builder
  SliderBar(lineWidth: number, knobX: number) {
    Stack({ alignContent: Alignment.Start }) {
      Row()
        .width(lineWidth)
        .height(1.5)
        .borderRadius(1)
        .backgroundColor($r('app.color.fg'))
      Row()
        .width(4.6)
        .height(4.6)
        .borderRadius(2.3)
        .backgroundColor($r('app.color.fg'))
        .offset({ x: knobX })
    }
    .width(lineWidth)
    .height(5)
  }

  @Builder
  Header() {
    Row() {
      Text(this.statsLine())
        .fontSize(13)
        .fontColor($r('app.color.fg'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)

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

      Column({ space: 2.5 }) {
        this.SliderBar(15, 2)
        this.SliderBar(15, 8)
        this.SliderBar(15, 4.5)
      }
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      .width(30)
      .height(28)
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
    .padding({ left: 12, right: 12, bottom: 10 })
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
        Row() {
          if (meta.key === 1) {
            QuickInput({
              text: $inputQ1,
              placeholder: '添加任务…',
              boxBg: $r('app.color.card'),
              onCommit: () => {
                this.addTask(1, this.inputQ1);
              }
            })
          } else if (meta.key === 2) {
            QuickInput({
              text: $inputQ2,
              placeholder: '添加任务…',
              boxBg: $r('app.color.card'),
              onCommit: () => {
                this.addTask(2, this.inputQ2);
              }
            })
          } else if (meta.key === 3) {
            QuickInput({
              text: $inputQ3,
              placeholder: '添加任务…',
              boxBg: $r('app.color.card'),
              onCommit: () => {
                this.addTask(3, this.inputQ3);
              }
            })
          } else {
            QuickInput({
              text: $inputQ4,
              placeholder: '添加任务…',
              boxBg: $r('app.color.card'),
              onCommit: () => {
                this.addTask(4, this.inputQ4);
              }
            })
          }
        }
        .layoutWeight(1)

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

        QuickInput({
          text: $draftTitle,
          placeholder: '要做什么？',
          boxHeight: 44,
          fontSize: 15,
          boxBg: $r('app.color.bg'),
          topMargin: 12,
          onCommit: () => {
            this.saveDraft();
          }
        })

        if (this.editingId > 0) {
          Text('移动到其它象限')
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
        } else {
          Text(`将放入「${this.quadrantName(this.draftQuadrant)}」`)
            .fontSize(12)
            .fontColor($r('app.color.muted'))
            .width('100%')
            .margin({ top: 14 })
        }

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
  SectionTitle(text: string) {
    Text(text)
      .fontSize(12)
      .fontWeight(FontWeight.Medium)
      .fontColor($r('app.color.fg'))
      .width('100%')
      .margin({ top: 16 })
  }

  /** 设置页统一操作按钮：同底色同字号（11），危险操作用红字 */
  @Builder
  Chip(label: string, onTap: () => void, danger: boolean) {
    Text(label)
      .fontSize(11)
      .fontColor(danger ? $r('app.color.danger') : $r('app.color.fg'))
      .padding({ left: 11, right: 11, top: 6, bottom: 6 })
      .backgroundColor($r('app.color.bg'))
      .borderRadius(10)
      .border({ width: 0.5, color: $r('app.color.border') })
      .onClick(() => {
        onTap();
      })
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
            this.SectionTitle('任务排序')
            Flex({ wrap: FlexWrap.Wrap }) {
              ForEach(SORT_OPTIONS, (opt: SettingOption) => {
                Text(opt.label)
                  .fontSize(11)
                  .fontColor(this.settings.sortMode === opt.key ?
                    $r('app.color.on_accent') : $r('app.color.fg'))
                  .padding({ left: 10, right: 10, top: 5, bottom: 5 })
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
                  .fontSize(11)
                  .fontColor(this.settings.colorMode === opt.key ?
                    $r('app.color.on_accent') : $r('app.color.fg'))
                  .padding({ left: 10, right: 10, top: 5, bottom: 5 })
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
                  .fontSize(11)
                  .fontColor(this.settings.widgetLines === opt.key ?
                    $r('app.color.on_accent') : $r('app.color.fg'))
                  .padding({ left: 10, right: 10, top: 5, bottom: 5 })
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

            this.SectionTitle('微软 To Do')
            Column({ space: 8 }) {
              Row() {
                Column() {
                  Text(this.msConnected ?
                    (this.msProfile.length > 0 ? this.msProfile : '已连接') : '未连接')
                    .fontSize(13)
                    .fontWeight(FontWeight.Medium)
                    .fontColor($r('app.color.fg'))
                  Text(this.msConnected ?
                    (this.msLastSync.length > 0 ? this.msLastSync : '等待首次同步')
                    : '把当前账号同步到微软 To Do')
                    .fontSize(10)
                    .fontColor($r('app.color.muted'))
                    .margin({ top: 2 })
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)

                if (this.msConnected) {
                  this.Chip(this.msBusy ? '同步中…' : '立即同步', () => {
                    this.msSyncNow();
                  }, false)
                  this.Chip('断开', () => {
                    this.msDisconnect();
                  }, true)
                } else {
                  this.Chip('连接微软账号', () => {
                    this.openMsLogin();
                  }, false)
                }
              }
              .width('100%')
              .padding(10)
              .borderRadius(12)
              .backgroundColor($r('app.color.bg'))

              if (!this.msConnected) {
                Text('第一步：填写 Azure 应用 Client ID')
                  .fontSize(11)
                  .fontColor($r('app.color.muted'))
                Row({ space: 8 }) {
                  TextInput({ placeholder: 'Client ID（GUID）', text: this.msClientIdInput })
                    .fontSize(12)
                    .fontColor($r('app.color.fg'))
                    .placeholderColor($r('app.color.muted'))
                    .height(38)
                    .layoutWeight(1)
                    .backgroundColor($r('app.color.bg'))
                    .borderRadius(10)
                    .padding({ left: 10, right: 10 })
                    .onChange((value: string) => {
                      this.msClientIdInput = value;
                    })
                  Text('保存')
                    .fontSize(11)
                    .fontColor($r('app.color.accent'))
                    .padding({ left: 12, right: 12, top: 8, bottom: 8 })
                    .backgroundColor($r('app.color.accent_soft'))
                    .borderRadius(10)
                    .onClick(() => {
                      this.saveMsClientId();
                    })
                }
                .width('100%')
              }

              Row() {
                Text('自动同步（改动后自动推送 / 拉取）')
                  .fontSize(13)
                  .fontColor($r('app.color.fg'))
                  .layoutWeight(1)
                Toggle({ type: ToggleType.Switch, isOn: this.msAutoSync })
                  .selectedColor($r('app.color.accent'))
                  .onChange((isOn: boolean) => {
                    this.toggleMsAutoSync(isOn);
                  })
              }
              .width('100%')
              .margin({ top: 2 })
            }
            .width('100%')
            .margin({ top: 8 })
            this.HintText('四个象限对应微软 To Do 的四个同名清单，云端不存在则自动创建；冲突按最后修改时间胜出。需在 Azure 门户「应用注册」建公共客户端，回调填 nativeclient。')

            this.SectionTitle('华为账号')
            Row() {
              if (this.hwOpenId.length > 0) {
                if (this.hwAvatar.length > 0) {
                  Image(this.hwAvatar)
                    .width(34)
                    .height(34)
                    .borderRadius(17)
                    .objectFit(ImageFit.Cover)
                } else {
                  Text(this.hwNickName.length > 0 ? this.hwNickName.substring(0, 1) : '华')
                    .fontSize(14)
                    .fontColor('#FFFFFF')
                    .width(34)
                    .height(34)
                    .textAlign(TextAlign.Center)
                    .borderRadius(17)
                    .backgroundColor($r('app.color.accent'))
                }
                Column() {
                  Text(this.hwNickName.length > 0 ? this.hwNickName : '已登录')
                    .fontSize(13)
                    .fontWeight(FontWeight.Medium)
                    .fontColor($r('app.color.fg'))
                  Text('华为账号已连接')
                    .fontSize(10)
                    .fontColor($r('app.color.muted'))
                    .margin({ top: 2 })
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)
                .margin({ left: 9 })

                this.Chip('退出', () => {
                  this.hwLogout();
                }, true)
              } else {
                Column() {
                  Text('未登录')
                    .fontSize(13)
                    .fontWeight(FontWeight.Medium)
                    .fontColor($r('app.color.fg'))
                  Text('登录后可使用云备份与云同步')
                    .fontSize(10)
                    .fontColor($r('app.color.muted'))
                    .margin({ top: 2 })
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)

                this.Chip(this.hwBusy ? '登录中…' : '登录', () => {
                  this.hwLogin();
                }, false)
              }
            }
            .width('100%')
            .padding(10)
            .borderRadius(12)
            .backgroundColor($r('app.color.card'))
            .margin({ top: 8 })

            if (this.hwError.length > 0) {
              Text(this.hwError)
                .fontSize(10)
                .fontColor($r('app.color.danger'))
                .width('100%')
                .margin({ top: 6 })
            }
            this.HintText('需要 AGC「账号服务」与 module.json5 中的 client_id 配置，见 README。')

            this.SectionTitle('云备份')
            Row() {
              Text('自动备份（改动后自动上传）')
                .fontSize(13)
                .fontColor($r('app.color.fg'))
                .layoutWeight(1)
              Toggle({ type: ToggleType.Switch, isOn: this.autoBackup })
                .selectedColor($r('app.color.accent'))
                .onChange((isOn: boolean) => {
                  this.toggleAutoBackup(isOn);
                })
            }
            .width('100%')

            Row({ space: 8 }) {
              this.Chip(this.backupBusy ? '处理中…' : '备份到云端', () => {
                this.doBackupNow();
              }, false)
              this.Chip('从云端恢复', () => {
                this.doRestore();
              }, false)
              Blank()
              Text(this.hwOpenId.length === 0 ? '需先登录华为账号' :
                (this.lastBackupText.length > 0 ? `上次：${this.lastBackupText}` : '尚未备份'))
                .fontSize(10)
                .fontColor($r('app.color.muted'))
            }
            .width('100%')
            .margin({ top: 8 })

            Row({ space: 8 }) {
              this.Chip('导出到文件', () => {
                this.doExportFile();
              }, false)
              this.Chip('从文件恢复', () => {
                this.doImportFile();
              }, false)
            }
            .width('100%')
            .margin({ top: 8 })
            this.HintText('导出/导入走系统文件选择器，不需要华为账号；云端备份需要登录华为账号并在 AGC 开通云存储。')

            this.SectionTitle('数据')
            Row({ space: 10 }) {
              this.Chip('清理已完成', () => {
                this.confirmClearCompleted();
              }, false)
              this.Chip('清空本账号', () => {
                this.confirmClearAll();
              }, true)
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

  @Builder
  MsLoginPanel() {
    Column() {
      Row() {
        Column() {
          Text('登录 Microsoft 账号')
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.fg'))
          Text('登录完成会自动返回；仅授权读写你的待办')
            .fontSize(10)
            .fontColor($r('app.color.muted'))
            .margin({ top: 2 })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        Text('✕')
          .fontSize(16)
          .fontColor($r('app.color.muted'))
          .padding(6)
          .onClick(() => {
            this.showMsLogin = false;
          })
      }
      .width('100%')
      .padding({ left: 14, right: 14, top: 12, bottom: 8 })

      Web({ src: this.msLoginUrl, controller: this.webCtrl })
        .javaScriptAccess(true)
        .domStorageAccess(true)
        .zoomAccess(false)
        .width('100%')
        .layoutWeight(1)
        .onLoadIntercept((event: OnLoadInterceptEvent) => {
          return this.onWebNav(event.data.getRequestUrl());
        })
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.bg'))
  }

  build() {
    Stack() {
      Column() {
        this.Header()

        if (this.ready) {
          this.Board()
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

      if (this.showSettings) {
        this.SettingsPanel()
      }

      if (this.showMsLogin) {
        this.MsLoginPanel()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.bg'))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .padding({ top: this.topInset, bottom: this.bottomInset })
  }
}
