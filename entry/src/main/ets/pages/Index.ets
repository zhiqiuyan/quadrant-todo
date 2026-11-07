import { common, ConfigurationConstant } from '@kit.AbilityKit';
import { pasteboard } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { QuadrantMeta, QUADRANTS, TaskItem, Q1, quadrantMeta } from '../model/TaskItem';
import { Account } from '../model/Account';
import { dailyQuote, QuoteItem } from '../model/Quote';
import {
  AppSettings, COLOR_MODE_OPTIONS, FONT_FOLLOW, FONT_MODE_OPTIONS, fontRatioOf, MAT_OFF, MATERIAL_OPTIONS,
  MODE_DARK, MODE_LIGHT, MODE_SYSTEM, SettingOption, SORT_OPTIONS, WIDGET_LINE_OPTIONS
} from '../model/AppSettings';
import { TaskRepository } from '../data/TaskRepository';
import { AccountStore } from '../data/AccountStore';
import { SettingsStore } from '../data/SettingsStore';
import { PrefStore } from '../data/PrefStore';
import { WidgetBridge } from '../data/WidgetBridge';
import { HuaweiAuthService, HuaweiIdProfile } from '../data/HuaweiAuthService';
import { BackupService, BackupResult } from '../data/BackupService';
import { CalSyncService, CalSyncConfig } from '../data/CalSyncService';
import { LocalCalService, LocalCalResult } from '../data/LocalCalService';
import { FontScaleService } from '../data/FontScaleService';
import { DateUtil } from '../common/DateUtil';
import {
  deviceLevelLabel, glowOpacityOf, glowRadiusOf, immersiveSupported
} from '../data/MaterialService';

const DOMAIN: number = 0x0000;
const TAG: string = 'QuadrantTodo';
const APP_VERSION: string = '1.1.3';
/** 协议版本：内容有实质变更时 +1，用户需重新确认 */
const AGREEMENT_VERSION: number = 1;
const KEY_AGREE_ACCEPTED: string = 'agree_accepted';
const KEY_AGREE_VERSION: string = 'agree_version';

/**
 * dock 几何：圆形按键直径 44vp，四边内边距 8vp。
 * dock 高 = 44 + 8×2 = 60vp；圆角半径 = 8 + 44/2 = 30vp。
 * 此时圆角弧的圆心与两端圆形按键的圆心重合（都在距角 30vp 处），
 * 四个边角的弧线与圆形之间间隙恒为 8vp，即「四角等距」。
 */
const DOCK_KEY_SIZE: number = 44;
const DOCK_PADDING: number = 8;
const DOCK_HEIGHT: number = 60;
const DOCK_RADIUS: number = 30;

/** 填写小弹窗的截止日快捷选项；offset < 0 代表「不设截止日」 */
class DueOption {
  label: string;
  offset: number;

  constructor(label: string, offset: number) {
    this.label = label;
    this.offset = offset;
  }
}

const DUE_OPTIONS: DueOption[] = [
  new DueOption('无', -1),
  new DueOption('今天', 0),
  new DueOption('明天', 1),
  new DueOption('七天后', 7)
];

/** dock 圆形按键的饱和色（选中时的大色块） */
function quadrantDot(key: number): Resource {
  if (key === 2) {
    return $r('app.color.q2_dot');
  }
  if (key === 3) {
    return $r('app.color.q3_dot');
  }
  if (key === 4) {
    return $r('app.color.q4_dot');
  }
  return $r('app.color.q1_dot');
}

/** dock 圆形按键的浅色底（未选中时同样是实心大色块，只降低对比） */
function quadrantFill(key: number): Resource {
  if (key === 2) {
    return $r('app.color.q2_bg');
  }
  if (key === 3) {
    return $r('app.color.q3_bg');
  }
  if (key === 4) {
    return $r('app.color.q4_bg');
  }
  return $r('app.color.q1_bg');
}


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

  /** 用户协议：false 时全屏展示协议页，同意前无法使用应用 */
  @State agreed: boolean = true;

  /** 设置页「关于」是否展开，默认折叠 */
  @State aboutExpanded: boolean = false;

  /** 编辑面板 */
  @State showEditor: boolean = false;
  @State editingId: number = 0;
  @State draftTitle: string = '';
  @State draftQuadrant: number = Q1;
  @State draftDue: number = 0;
  @State draftImportant: boolean = false;
  @State draftDate: Date = new Date();
  @State showCalendar: boolean = false;

  /** 归类说明面板 */
  @State showRuler: boolean = false;

  /** 已完成面板 */
  @State showDone: boolean = false;
  @State doneTasks: TaskItem[] = [];


  /** 华为账号与云备份 */
  @State hwNickName: string = '';
  @State hwAvatar: string = '';
  @State hwOpenId: string = '';
  @State hwBusy: boolean = false;
  @State hwError: string = '';
  @State autoBackup: boolean = true;
  @State lastBackupText: string = '';
  @State backupBusy: boolean = false;

  /** 日历订阅（Gitee 托管 ICS） */
  @State calEnabled: boolean = false;
  @State calOwner: string = '';
  @State calRepo: string = '';
  @State calToken: string = '';
  @State calUrl: string = '';
  @State calLastSync: string = '';
  @State calBusy: boolean = false;
  private calSyncGuard: number = 0;

  /** 本机日历（HarmonyOS Calendar Kit） */
  @State localCalEnabled: boolean = false;
  @State localCalLast: string = '';
  @State localCalBusy: boolean = false;
  private localCalGuard: number = 0;

  /** 沉浸式安全区避让（vp） */
  @State topInset: number = 0;
  @State bottomInset: number = 0;

  /** 系统当前字体缩放比，仅用于设置页展示 */
  @State systemFontScale: number = 1;

  private ctx: common.UIAbilityContext | undefined = undefined;

  /** 填写小弹窗状态（非模态）：由底部 dock 驱动，主界面始终可交互 */
  @State createOpen: boolean = false;
  @State createTitle: string = '';
  @State createQuadrant: number = Q1;
  @State createDue: number = 0;
  @State createImportant: boolean = false;
  /** 键盘高度（vp），填写小弹窗贴在键盘上沿 */
  @State keyboardHeight: number = 0;
  /** 填写卡片实测高度（vp）：键盘弹起时 dock 据此上移到卡片上方，避免被键盘遮挡 */
  @State createCardHeight: number = 120;

  aboutToAppear(): void {
    this.boot();
  }

  /** 协议未确认前拦截返回键；填写弹窗展开时返回键先收起弹窗 */
  onBackPress(): boolean {
    if (!this.agreed) {
      return true;
    }
    if (this.createOpen) {
      this.closeCreateCard();
      return true;
    }
    return false;
  }

  /** 监听键盘高度（px → vp），填写小弹窗据此贴在键盘上沿 */
  private async bindKeyboard(): Promise<void> {
    if (this.ctx === undefined) {
      return;
    }
    try {
      const win: window.Window = await window.getLastWindow(this.ctx);
      win.on('keyboardHeightChange', (height: number) => {
        this.keyboardHeight = height > 0 ? this.getUIContext().px2vp(height) : 0;
      });
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'keyboard observer failed: %{public}s', (err as Error).message);
    }
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
      this.systemFontScale = FontScaleService.systemScale(context);
      this.agreed = PrefStore.getBool(KEY_AGREE_ACCEPTED, false)
        && PrefStore.getNumber(KEY_AGREE_VERSION, 0) >= AGREEMENT_VERSION;

      const repo: TaskRepository = TaskRepository.getInstance();
      await repo.init(context);
      repo.useAccount(this.account.id);
      this.applyColorMode(this.settings.colorMode);
      this.refreshHuaweiState();
      this.autoBackup = BackupService.autoEnabled();
      this.refreshBackupState();
      await CalSyncService.init(context);
      this.refreshCalState();
      await LocalCalService.init(context);
      this.refreshLocalCalState();
      this.computeInsets();
      await this.bindKeyboard();
      await this.reload();
      this.ready = true;
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
   * 卡片推送、云备份、日历同步全部延后到后台执行，
   * 否则「保存」要等好几秒（网络往返 + 卡片 IPC + 云端上传）才会有反应。
   */
  private async afterChange(): Promise<void> {
    await this.reload();
    // 卡片立即推送（纯本地构建，毫秒级）；网络类工作走防抖
    WidgetBridge.refreshAll(this.ctx).catch(() => {
    });
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

  private fmtCalTime(ms: number): string {
    const d: Date = new Date(ms);
    const p = (n: number): string => n.toString().padStart(2, '0');
    return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())} ${p(d.getHours())}:${p(d.getMinutes())}`;
  }

  private refreshCalState(): void {
    const cfg: CalSyncConfig = CalSyncService.getConfig();
    this.calEnabled = cfg.enabled;
    this.calOwner = cfg.owner;
    this.calRepo = cfg.repo;
    this.calToken = cfg.token;
    this.calUrl = CalSyncService.subscriptionUrl(cfg);
    this.calLastSync = cfg.lastSync > 0 ? this.fmtCalTime(cfg.lastSync) : '';
  }

  private async calPersist(enabled: boolean): Promise<void> {
    const cfg: CalSyncConfig = CalSyncService.getConfig();
    cfg.enabled = enabled;
    cfg.owner = this.calOwner.trim();
    cfg.repo = this.calRepo.trim();
    cfg.token = this.calToken.trim();
    if (cfg.pathId.length === 0) {
      cfg.pathId = CalSyncService.newCandidatePathId();
    }
    await CalSyncService.saveConfig(cfg);
    this.refreshCalState();
  }

  private async calToggle(on: boolean): Promise<void> {
    await this.calPersist(on);
    if (on && CalSyncService.ready(CalSyncService.getConfig())) {
      this.calSyncNow();
    }
  }

  private async calSave(): Promise<void> {
    if (this.calOwner.trim().length === 0 || this.calRepo.trim().length === 0 ||
      this.calToken.trim().length === 0) {
      this.toast('请填写 Gitee 用户名、仓库名和私人令牌');
      return;
    }
    await this.calPersist(this.calEnabled);
    this.toast('已保存');
    if (CalSyncService.ready(CalSyncService.getConfig())) {
      this.calSyncNow();
    }
  }

  private calCopyUrl(): void {
    if (this.calUrl.length === 0) {
      this.toast('尚未生成订阅链接');
      return;
    }
    const data: pasteboard.PasteData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, this.calUrl);
    pasteboard.getSystemPasteboard().setData(data);
    this.toast('订阅链接已复制，去 iPhone 日历 → 账户 → 添加订阅日历粘贴');
  }

  private async calSyncNow(): Promise<void> {
    if (this.calBusy) {
      return;
    }
    this.calBusy = true;
    try {
      await CalSyncService.syncNow();
      this.refreshCalState();
      this.toast('日历已同步到 Gitee');
    } catch (err) {
      this.toast((err as Error).message);
    } finally {
      this.calBusy = false;
    }
  }

  /** 自动同步：60s 节流，失败静默 */
  private calAutoSync(): void {
    if (!CalSyncService.ready(CalSyncService.getConfig()) || this.calBusy) {
      return;
    }
    const now: number = Date.now();
    if (now - this.calSyncGuard < 60000) {
      return;
    }
    this.calSyncGuard = now;
    CalSyncService.syncNow().catch(() => {
    });
  }

  /* ==================== 本机日历（系统日历） ==================== */

  private refreshLocalCalState(): void {
    this.localCalEnabled = LocalCalService.isEnabled();
    const last: number = LocalCalService.getLastSync();
    this.localCalLast = last > 0 ? this.fmtCalTime(last) : '';
  }

  /** 同步到系统日历：先要权限，再按「带截止日 + 未完成」对账 */
  private async localCalSync(showToast: boolean): Promise<void> {
    if (this.localCalBusy || this.ctx === undefined) {
      return;
    }
    this.localCalBusy = true;
    try {
      const granted: boolean = await LocalCalService.ensurePermission(this.ctx);
      if (!granted) {
        if (showToast) {
          this.toast('未获得日历权限，请在系统设置中允许「象限待办」访问日历');
        }
        return;
      }
      const tasks: TaskItem[] = await TaskRepository.getInstance().listAll();
      const result: LocalCalResult = await LocalCalService.syncNow(this.ctx, tasks);
      this.refreshLocalCalState();
      if (showToast) {
        this.toast(`已同步到系统日历：${result.summary()}`);
      }
    } catch (err) {
      if (showToast) {
        this.toast((err as Error).message);
      }
    } finally {
      this.localCalBusy = false;
    }
  }

  private async localCalToggle(on: boolean): Promise<void> {
    if (on) {
      const granted: boolean = this.ctx === undefined ? false :
        await LocalCalService.ensurePermission(this.ctx);
      if (!granted) {
        this.toast('需要日历权限才能同步，请在系统设置中允许「象限待办」访问日历');
        this.localCalEnabled = false;
        return;
      }
      await LocalCalService.setEnabled(true);
      this.localCalEnabled = true;
      await this.localCalSync(true);
      return;
    }
    await LocalCalService.setEnabled(false);
    this.refreshLocalCalState();
    this.toast('已停止自动同步，已写入的事件保留在本机日历中');
  }

  private confirmLocalCalClear(): void {
    this.getUIContext().showAlertDialog({
      title: '清除本机日历事件',
      message: '将删除「象限待办」写入系统日历的全部事件（不影响你手动创建的其他日程），是否继续？',
      autoCancel: true,
      primaryButton: {
        value: '取消',
        action: () => {
        }
      },
      secondaryButton: {
        value: '清除',
        fontColor: $r('app.color.danger'),
        action: () => {
          this.doLocalCalClear();
        }
      }
    });
  }

  private async doLocalCalClear(): Promise<void> {
    if (this.ctx === undefined) {
      return;
    }
    try {
      const removed: number = await LocalCalService.clearAll(this.ctx);
      this.localCalLast = '';
      this.toast(`已清除 ${removed} 条日历事件`);
    } catch (err) {
      this.toast('清除失败：' + (err as Error).message);
    }
  }

  /** 后台自动同步：仅开关打开时执行，60s 节流，失败静默（不打扰用户） */
  private localCalAutoSync(): void {
    if (!this.localCalEnabled || this.localCalBusy || this.ctx === undefined) {
      return;
    }
    const now: number = Date.now();
    if (now - this.localCalGuard < 60000) {
      return;
    }
    this.localCalGuard = now;
    this.localCalSync(false);
  }

  private async runSideWork(): Promise<void> {
    if (this.autoBackup && this.ctx !== undefined) {
      BackupService.autoBackup(this.ctx);
    }
    this.calAutoSync();
    this.localCalAutoSync();
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

  /** dock 栏光晕色标：显式元组类型，满足 RadialGradientOptions.colors */
  private glowStops(): [ResourceColor, number][] {
    return [['#60A5FA', 0], ['#00000000', 1]];
  }

  /** 设置页展示设备算力等级与材质支持情况 */
  private materialCapabilityText(): string {
    const level: string = deviceLevelLabel();
    const flag: string = immersiveSupported() ? '支持沉浸材质' : '不支持，已回退为纯色';
    return `设备能力：${level} · ${flag}`;
  }

  /** 当前沉浸光感档位名称，用于设置页右侧状态 */
  private materialLevelLabel(): string {
    for (let i = 0; i < MATERIAL_OPTIONS.length; i++) {
      if (MATERIAL_OPTIONS[i].key === this.settings.materialLevel) {
        return MATERIAL_OPTIONS[i].label;
      }
    }
    return '标准';
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

  /** 每日一言：与桌面卡片共用同一名言库，按当天日期轮换 */
  private quoteLine(): string {
    const q: QuoteItem = dailyQuote();
    return `${q.text} —— ${q.author}`;
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

  /** 字号档位标签：跟随系统时同时显示系统当前比例 */
  private fontModeLabel(): string {
    if (this.settings.fontMode === FONT_FOLLOW) {
      return `跟随系统 ${this.systemFontScale.toFixed(2)}×`;
    }
    return `自定义 ${fontRatioOf(this.settings.fontMode).toFixed(2)}×`;
  }

  /** 打开设置面板：顺带刷新系统字体比例，避免后台改过系统字号后显示过期 */
  private openSettings(): void {
    if (this.ctx !== undefined) {
      this.systemFontScale = FontScaleService.systemScale(this.ctx);
    }
    this.showSettings = true;
  }

  /** 同意协议：记录接受事实与协议版本，之后不再弹出 */
  private acceptAgreement(): void {
    this.agreed = true;
    PrefStore.put(KEY_AGREE_ACCEPTED, true).catch(() => {
    });
    PrefStore.put(KEY_AGREE_VERSION, AGREEMENT_VERSION).catch(() => {
    });
  }

  /** 不同意：退出应用（数据仍保留在本机，下次启动会再次询问） */
  private declineAgreement(): void {
    if (this.ctx !== undefined) {
      this.ctx.terminateSelf().catch(() => {
      });
    }
  }

  private changeFontMode(key: number): void {
    const next: AppSettings = this.settings.copy();
    next.fontMode = key;
    if (this.ctx !== undefined) {
      FontScaleService.applyNow(this.ctx, key);
    }
    this.saveSettings(next, false);
  }

  private changeMaterialLevel(key: number): void {
    const next: AppSettings = this.settings.copy();
    next.materialLevel = key;
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
      await repo.clearAll();
      await this.afterChange();
      this.toast('已清空');
    } catch (err) {
      this.toast('清空失败：' + (err as Error).message);
    }
  }

  /* ==================== 操作 ==================== */

  /** 统一新建入口：由填写弹窗提交，写库后走既有的刷新链路 */
  private createTask(title: string, quadrant: number, dueAt: number, important: boolean): void {
    TaskRepository.getInstance().insert(title, quadrant, dueAt, important)
      .then(() => {
        this.afterChange();
      })
      .catch((err: Error) => {
        this.toast('添加失败：' + err.message);
      });
  }

  /* ==================== 圆形 dock + 贴键盘填写弹窗 ==================== */

  /** 卡片出现后主动聚焦输入框，确保键盘弹起、keyboardHeight 有值 */
  private focusCreateInput(): void {
    setTimeout(() => {
      focusControl.requestFocus('createInput');
    }, 60);
  }

  /** dock 左侧按钮：展开 / 收起填写弹窗 */
  private toggleCreateCard(): void {
    if (this.createOpen) {
      this.closeCreateCard();
      return;
    }
    this.createQuadrant = this.settings.defaultQuadrant;
    this.createOpen = true;
    this.focusCreateInput();
  }

  /** dock 右侧象限键：选中该象限并展开填写弹窗 */
  private selectCreateQuadrant(key: number): void {
    this.createQuadrant = key;
    this.createOpen = true;
    this.focusCreateInput();
  }

  private closeCreateCard(): void {
    this.createOpen = false;
    this.createTitle = '';
    this.createDue = 0;
    this.createImportant = false;
  }

  private commitCreate(): void {
    const value: string = this.createTitle.trim();
    if (value.length === 0) {
      return;
    }
    this.createTask(value, this.createQuadrant, this.createDue, this.createImportant);
    this.closeCreateCard();
  }

  private createDuePicked(offset: number): boolean {
    if (offset < 0) {
      return this.createDue === 0;
    }
    return this.createDue === DateUtil.dayOffset(offset);
  }

  /** 贴键盘时阴影朝上且收窄，避免下投影在键盘上形成视觉缝隙 */
  private cardShadow(): ShadowOptions {
    if (this.keyboardHeight > 0) {
      return { radius: 12, color: '#1F2563EB', offsetX: 0, offsetY: -2 };
    }
    return { radius: 24, color: '#332563EB', offsetX: 0, offsetY: 8 };
  }

  /** 贴键盘时下沿改方角，卡片底边与键盘上沿严丝合缝 */
  private createCardRadius(): BorderRadiuses {
    if (this.keyboardHeight > 0) {
      return { topLeft: 18, topRight: 18, bottomLeft: 0, bottomRight: 0 };
    }
    return { topLeft: 18, topRight: 18, bottomLeft: 18, bottomRight: 18 };
  }

  /** 键盘弹起时卡片底边 = 键盘高度（零间隙）；未弹起时贴在 dock 上方 6vp */
  private createCardBottom(): number {
    if (this.keyboardHeight > 0) {
      return this.keyboardHeight;
    }
    return DOCK_HEIGHT + 16 + 6;
  }

  /** 键盘弹起时 dock 上移：卡片展开则贴其上方，卡片收起则直接贴键盘上沿 */
  private dockBottom(): number {
    if (this.keyboardHeight > 0) {
      return this.keyboardHeight + (this.createOpen ? this.createCardHeight + 6 : 0);
    }
    return 16;
  }

  /** dock 阴影随光感档位增强，六档差异只集中在 dock 栏 */
  private dockShadow(): ShadowOptions {
    return {
      radius: 14 + this.settings.materialLevel * 3,
      color: '#332563EB',
      offsetX: 0,
      offsetY: 6
    };
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
      const repo: TaskRepository = TaskRepository.getInstance();
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

  /* ==================== 视图 ==================== */

  @Builder
  Header() {
    Row() {
      Text(this.quoteLine())
        .fontSize(12)
        .fontColor($r('app.color.muted'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)

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

      Row() {
        SymbolGlyph($r('sys.symbol.gearshape'))
          .fontSize(17)
          .fontColor([$r('app.color.fg')])
      }
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)
      .width(30)
      .height(28)
      .backgroundColor($r('app.color.card'))
      .borderRadius(13)
      .margin({ left: 5 })
      .onClick(() => {
        this.openSettings();
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
    // 底部留出胶囊 dock（60 + 16 边距）的空间，避免遮住第四象限的任务
    .padding({ left: 12, right: 12, bottom: 84 })
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
          }, (item: TaskItem) => `task-${item.id}-${item.updatedAt}`)
        }
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Off)
        .padding({ top: 6 })
      }

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
            .constraintSize({ minHeight: 44 })
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
          .constraintSize({ minHeight: 44 })
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
          Text('归类说明')
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
              this.openSettings();
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
            }, (item: TaskItem) => `done-${item.id}-${item.updatedAt}`)
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

  /** 设置分组标题：灰色小字，位于卡片外（参考系统设置风格） */
  @Builder
  GroupTitle(text: string) {
    Text(text)
      .fontSize(12)
      .fontColor($r('app.color.muted'))
      .width('100%')
      .margin({ top: 18, bottom: 8 })
  }

  /** 设置卡片内的行：标题 + 右侧箭头 */
  @Builder
  RowArrow(title: string, onTap: () => void) {
    Row() {
      Text(title)
        .fontSize(14)
        .fontColor($r('app.color.fg'))
        .layoutWeight(1)
      SymbolGlyph($r('sys.symbol.chevron_right'))
        .fontSize(13)
        .fontColor([$r('app.color.muted')])
    }
    .width('100%')
    .padding({ top: 13, bottom: 13 })
    .onClick(() => {
      onTap();
    })
  }

  /** 设置卡片内的行分隔线 */
  @Builder
  RowDivider() {
    Divider()
      .strokeWidth(0.5)
      .color($r('app.color.border'))
  }

  /** 设置选项 chip */
  @Builder
  OptChip(label: string, selected: boolean) {
    Text(label)
      .fontSize(11)
      .fontColor(selected ? $r('app.color.on_accent') : $r('app.color.fg'))
      .padding({ left: 10, right: 10, top: 5, bottom: 5 })
      .backgroundColor(selected ? $r('app.color.accent') : $r('app.color.bg'))
      .borderRadius(12)
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
  AgreementSection(title: string, body: string) {
    Column({ space: 6 }) {
      Text(title)
        .fontSize(15)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.fg'))
      Text(body)
        .fontSize(13)
        .lineHeight(22)
        .fontColor($r('app.color.fg'))
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  /** 首启用户协议页：全屏覆盖，同意前无法使用应用 */
  @Builder
  AgreementPanel() {
    Column() {
      Text('用户协议')
        .fontSize(22)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.fg'))
        .width('100%')
      Text('请完整阅读用户协议与免责声明')
        .fontSize(12)
        .fontColor($r('app.color.muted'))
        .width('100%')
        .margin({ top: 4 })

      Scroll() {
        Column({ space: 16 }) {
          Text('在使用 象限待办（下称「本软件」）之前，请仔细阅读并充分理解本协议与免责声明。点击「同意并继续」即视为您已阅读、理解并同意接受全部内容；如不同意，请点击「不同意并退出」，停止使用本软件。')
            .fontSize(13)
            .lineHeight(22)
            .fontColor($r('app.color.fg'))
            .width('100%')

          this.AgreementSection('一、软件性质与知识产权',
            '本软件由作者独立开发，源码通过 GitHub（仓库 quadrant-todo）公开，供学习研究与非商业使用；软件的界面设计、图标、文档等内容归作者所有。请在遵循仓库附带许可的前提下使用与分发，不得去除或篡改本软件的版权与来源声明后再分发，不得将本软件用于任何违法违规用途。')

          this.AgreementSection('二、数据与隐私',
            '任务数据默认仅保存在本机数据库中，本软件不会在后台上传您的任何数据。仅当您主动开启「云备份」「本机日历」「日历订阅」等功能时，相关数据才会传输到对应第三方服务，且可随时在设置中关闭。卸载本软件即清除全部本地数据。')

          this.AgreementSection('三、第三方服务',
            '华为账号、Gitee、系统日历等功能依赖相应第三方提供的服务，其可用性、准确性与安全性由服务提供方负责，作者对第三方服务的变更或中断不承担责任。')

          this.AgreementSection('四、免责声明',
            '本软件按「现状」提供，不作出任何形式的担保。因系统故障、误操作、卸载重装或其他原因导致的任务数据丢失或损坏，作者不承担责任；重要数据请通过「云备份」或「导出备份」定期自行备份。本软件写入系统日历、日历订阅等功能在具体设备上的实际表现以真机为准。')

          this.AgreementSection('五、协议的更新',
            '本协议可能随版本更新而调整。协议内容发生实质变更后，应用将在下次启动时重新提示确认；若您在提示后继续使用本软件，即视为接受更新后的协议。')
        }
        .width('100%')
        .padding({ top: 10, bottom: 10 })
      }
      .layoutWeight(1)
      .scrollBar(BarState.Auto)
      .align(Alignment.Top)
      .margin({ top: 14 })

      Button() {
        Text('同意并继续')
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.on_accent'))
      }
      .width('100%')
      .height(44)
      .backgroundColor($r('app.color.accent'))
      .onClick(() => {
        this.acceptAgreement();
      })

      Button() {
        Text('不同意并退出')
          .fontSize(15)
          .fontColor($r('app.color.fg'))
      }
      .width('100%')
      .height(44)
      .backgroundColor($r('app.color.card'))
      .margin({ top: 10 })
      .onClick(() => {
        this.declineAgreement();
      })
    }
    .width('100%')
    .height('100%')
    .padding(20)
    .backgroundColor($r('app.color.bg'))
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
            .fontSize(18)
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
            /* ==================== 通用 ==================== */
            this.GroupTitle('通用')
            Column() {
              this.RowArrow('归类说明', () => {
                this.showSettings = false;
                this.showRuler = true;
              })
              this.RowDivider()

              Column() {
                Text('任务排序')
                  .fontSize(14)
                  .fontColor($r('app.color.fg'))
                Flex({ wrap: FlexWrap.Wrap }) {
                  ForEach(SORT_OPTIONS, (opt: SettingOption) => {
                    Row() {
                      this.OptChip(opt.label, this.settings.sortMode === opt.key)
                    }
                    .onClick(() => {
                      this.changeSortMode(opt.key);
                    })
                    .margin({ right: 8, top: 8 })
                  }, (opt: SettingOption) => `sort-${opt.key}-${this.settings.sortMode === opt.key ? 1 : 0}`)
                }
                .width('100%')
                .margin({ top: 10 })
              }
              .width('100%')
              .padding({ top: 13, bottom: 13 })
              .alignItems(HorizontalAlign.Start)
              this.RowDivider()

              Column() {
                Text('外观')
                  .fontSize(14)
                  .fontColor($r('app.color.fg'))
                Flex({ wrap: FlexWrap.Wrap }) {
                  ForEach(COLOR_MODE_OPTIONS, (opt: SettingOption) => {
                    Row() {
                      this.OptChip(opt.label, this.settings.colorMode === opt.key)
                    }
                    .onClick(() => {
                      this.changeColorMode(opt.key);
                    })
                    .margin({ right: 8, top: 8 })
                  }, (opt: SettingOption) => `mode-${opt.key}-${this.settings.colorMode === opt.key ? 1 : 0}`)
                }
                .width('100%')
                .margin({ top: 10 })
                Text('「跟随系统」与系统深色模式同步，切换后立即生效')
                  .fontSize(10)
                  .fontColor($r('app.color.muted'))
                  .margin({ top: 8 })
              }
              .width('100%')
              .padding({ top: 13, bottom: 13 })
              .alignItems(HorizontalAlign.Start)
              this.RowDivider()

              Column() {
                Row() {
                  Text('沉浸光感')
                    .fontSize(14)
                    .fontColor($r('app.color.fg'))
                    .layoutWeight(1)
                  Text(this.materialLevelLabel())
                    .fontSize(12)
                    .fontColor($r('app.color.muted'))
                }
                .width('100%')

                Flex({ wrap: FlexWrap.Wrap }) {
                  ForEach(MATERIAL_OPTIONS, (opt: SettingOption) => {
                    Row() {
                      this.OptChip(opt.label, this.settings.materialLevel === opt.key)
                    }
                    .onClick(() => {
                      this.changeMaterialLevel(opt.key);
                    })
                    .margin({ right: 8, top: 8 })
                  }, (opt: SettingOption) => `mat-${opt.key}-${this.settings.materialLevel === opt.key ? 1 : 0}`)
                }
                .width('100%')
                .margin({ top: 10 })

                Text('沉浸光感只作用于底部 dock 栏；档位越高，栏上的光晕越明显。主界面与填写界面保持纯色，关闭档位恢复无光感。')
                  .fontSize(10)
                  .fontColor($r('app.color.muted'))
                  .margin({ top: 8 })
                Text(this.materialCapabilityText())
                  .fontSize(10)
                  .fontColor($r('app.color.muted'))
                  .margin({ top: 4 })
              }
              .width('100%')
              .padding({ top: 13, bottom: 13 })
              .alignItems(HorizontalAlign.Start)
              this.RowDivider()

              Column() {
                Row() {
                  Text('字体大小')
                    .fontSize(14)
                    .fontColor($r('app.color.fg'))
                    .layoutWeight(1)
                  Text(this.fontModeLabel())
                    .fontSize(12)
                    .fontColor($r('app.color.muted'))
                }
                .width('100%')

                Flex({ wrap: FlexWrap.Wrap }) {
                  ForEach(FONT_MODE_OPTIONS, (opt: SettingOption) => {
                    Row() {
                      this.OptChip(opt.label, this.settings.fontMode === opt.key)
                    }
                    .onClick(() => {
                      this.changeFontMode(opt.key);
                    })
                    .margin({ right: 8, top: 8 })
                  }, (opt: SettingOption) => `font-${opt.key}-${this.settings.fontMode === opt.key ? 1 : 0}`)
                }
                .width('100%')
                .margin({ top: 10 })

                Text(this.settings.fontMode === FONT_FOLLOW
                  ? '字号随系统「设置 → 显示和亮度 → 字体大小」变化，应用最多放大 1.75 倍'
                  : '自定义档位覆盖系统字号；改回「跟随系统」后重新打开应用即恢复跟随')
                  .fontSize(10)
                  .fontColor($r('app.color.muted'))
                  .margin({ top: 8 })
              }
              .width('100%')
              .padding({ top: 13, bottom: 13 })
              .alignItems(HorizontalAlign.Start)
              this.RowDivider()

              Column() {
                Text('大卡片（6*4）显示条数')
                  .fontSize(14)
                  .fontColor($r('app.color.fg'))
                Flex({ wrap: FlexWrap.Wrap }) {
                  ForEach(WIDGET_LINE_OPTIONS, (opt: SettingOption) => {
                    Row() {
                      this.OptChip(opt.label, this.settings.widgetLines === opt.key)
                    }
                    .onClick(() => {
                      this.changeWidgetLines(opt.key);
                    })
                    .margin({ right: 8, top: 8 })
                  }, (opt: SettingOption) => `lines-${opt.key}-${this.settings.widgetLines === opt.key ? 1 : 0}`)
                }
                .width('100%')
                .margin({ top: 10 })
              }
              .width('100%')
              .padding({ top: 13, bottom: 13 })
              .alignItems(HorizontalAlign.Start)
            }
            .width('100%')
            .padding({ left: 14, right: 14 })
            .backgroundColor($r('app.color.card'))
            .borderRadius(16)
            .alignItems(HorizontalAlign.Start)

            /* ==================== 华为账号 ==================== */
            this.GroupTitle('华为账号')
            Column() {
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
                      .fontSize(14)
                      .fontColor($r('app.color.fg'))
                    Text('华为账号已连接')
                      .fontSize(10)
                      .fontColor($r('app.color.muted'))
                      .margin({ top: 2 })
                  }
                  .alignItems(HorizontalAlign.Start)
                  .layoutWeight(1)
                  .margin({ left: 10 })

                  this.Chip('退出', () => {
                    this.hwLogout();
                  }, true)
                } else {
                  Column() {
                    Text('未登录')
                      .fontSize(14)
                      .fontColor($r('app.color.fg'))
                    Text('登录后可使用云备份')
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
              .padding({ top: 13, bottom: 13 })

              if (this.hwError.length > 0) {
                this.RowDivider()
                Text(this.hwError)
                  .fontSize(10)
                  .fontColor($r('app.color.danger'))
                  .width('100%')
                  .padding({ top: 10, bottom: 10 })
              }
              this.RowDivider()
              Text('需要 AGC「账号服务」与 module.json5 中的 client_id 配置，详见 README')
                .fontSize(10)
                .fontColor($r('app.color.muted'))
                .width('100%')
                .padding({ top: 10, bottom: 12 })
            }
            .width('100%')
            .padding({ left: 14, right: 14 })
            .backgroundColor($r('app.color.card'))
            .borderRadius(16)
            .alignItems(HorizontalAlign.Start)

            /* ==================== 云备份 ==================== */
            this.GroupTitle('云备份')
            Column() {
              Row() {
                Text('自动备份')
                  .fontSize(14)
                  .fontColor($r('app.color.fg'))
                  .layoutWeight(1)
                Toggle({ type: ToggleType.Switch, isOn: this.autoBackup })
                  .selectedColor($r('app.color.accent'))
                  .onChange((isOn: boolean) => {
                    this.toggleAutoBackup(isOn);
                  })
              }
              .width('100%')
              .padding({ top: 6, bottom: 6 })
              this.RowDivider()

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
              .padding({ top: 12, bottom: 12 })
              this.RowDivider()

              Row({ space: 8 }) {
                this.Chip('导出到文件', () => {
                  this.doExportFile();
                }, false)
                this.Chip('从文件恢复', () => {
                  this.doImportFile();
                }, false)
              }
              .width('100%')
              .padding({ top: 12, bottom: 12 })
              this.RowDivider()
              Text('导出/导入走系统文件选择器，不需要华为账号；云端备份需登录华为账号并在 AGC 开通云存储')
                .fontSize(10)
                .fontColor($r('app.color.muted'))
                .width('100%')
                .padding({ top: 10, bottom: 12 })
            }
            .width('100%')
            .padding({ left: 14, right: 14 })
            .backgroundColor($r('app.color.card'))
            .borderRadius(16)
            .alignItems(HorizontalAlign.Start)

            /* ==================== 本机日历 ==================== */
            this.GroupTitle('本机日历')
            Column() {
              Row() {
                Column() {
                  Text('同步到系统日历')
                    .fontSize(14)
                    .fontColor($r('app.color.fg'))
                  Text(this.localCalEnabled ?
                    (this.localCalLast.length > 0 ? `上次同步：${this.localCalLast}` : '等待首次同步')
                    : '带截止日的待办写成全天事件')
                    .fontSize(10)
                    .fontColor($r('app.color.muted'))
                    .margin({ top: 2 })
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)
                Toggle({ type: ToggleType.Switch, isOn: this.localCalEnabled })
                  .selectedColor($r('app.color.accent'))
                  .onChange((isOn: boolean) => {
                    this.localCalToggle(isOn);
                  })
              }
              .width('100%')
              .padding({ top: 13, bottom: 13 })

              if (this.localCalEnabled) {
                this.RowDivider()
                Row({ space: 8 }) {
                  this.Chip(this.localCalBusy ? '同步中…' : '立即同步', () => {
                    this.localCalSync(true);
                  }, false)
                  this.Chip('清除事件', () => {
                    this.confirmLocalCalClear();
                  }, true)
                }
                .width('100%')
                .padding({ top: 12, bottom: 12 })
              }
              this.RowDivider()
              Text('带截止日、未完成的任务会以「全天事件」写入系统默认日历账户，完成后自动移除。只操作本应用创建的事件，不会改动你手动添加的日程；首次同步需授予日历读写权限。')
                .fontSize(10)
                .fontColor($r('app.color.muted'))
                .width('100%')
                .padding({ top: 10, bottom: 12 })
            }
            .width('100%')
            .padding({ left: 14, right: 14 })
            .backgroundColor($r('app.color.card'))
            .borderRadius(16)
            .alignItems(HorizontalAlign.Start)

            /* ==================== 日历订阅 ==================== */
            this.GroupTitle('日历订阅（iPhone / Google）')
            Column() {
              Row() {
                Text('同步到日历订阅')
                  .fontSize(14)
                  .fontColor($r('app.color.fg'))
                  .layoutWeight(1)
                Toggle({ type: ToggleType.Switch, isOn: this.calEnabled })
                  .selectedColor($r('app.color.accent'))
                  .onChange((isOn: boolean) => {
                    this.calToggle(isOn);
                  })
              }
              .width('100%')
              .padding({ top: 6, bottom: 6 })

              if (this.calEnabled) {
                this.RowDivider()
                Column({ space: 8 }) {
                  TextInput({ placeholder: 'Gitee 用户名', text: this.calOwner })
                    .fontSize(12)
                    .fontColor($r('app.color.fg'))
                    .placeholderColor($r('app.color.muted'))
                    .height(38)
                    .width('100%')
                    .backgroundColor($r('app.color.bg'))
                    .borderRadius(10)
                    .padding({ left: 10, right: 10 })
                    .onChange((value: string) => {
                      this.calOwner = value;
                    })
                  TextInput({ placeholder: '仓库名（须为公开仓库）', text: this.calRepo })
                    .fontSize(12)
                    .fontColor($r('app.color.fg'))
                    .placeholderColor($r('app.color.muted'))
                    .height(38)
                    .width('100%')
                    .backgroundColor($r('app.color.bg'))
                    .borderRadius(10)
                    .padding({ left: 10, right: 10 })
                    .onChange((value: string) => {
                      this.calRepo = value;
                    })
                  TextInput({ placeholder: 'Gitee 私人令牌（勾选 projects 权限）', text: this.calToken })
                    .fontSize(12)
                    .fontColor($r('app.color.fg'))
                    .placeholderColor($r('app.color.muted'))
                    .height(38)
                    .width('100%')
                    .backgroundColor($r('app.color.bg'))
                    .borderRadius(10)
                    .padding({ left: 10, right: 10 })
                    .onChange((value: string) => {
                      this.calToken = value;
                    })
                  Row({ space: 8 }) {
                    this.Chip('保存配置', () => {
                      this.calSave();
                    }, false)
                    this.Chip(this.calBusy ? '同步中…' : '立即同步', () => {
                      this.calSyncNow();
                    }, false)
                    if (this.calUrl.length > 0) {
                      this.Chip('复制订阅链接', () => {
                        this.calCopyUrl();
                      }, false)
                    }
                  }
                  .width('100%')

                  if (this.calUrl.length > 0) {
                    Text(this.calUrl)
                      .fontSize(10)
                      .fontColor($r('app.color.muted'))
                      .width('100%')
                      .maxLines(2)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                  }
                  if (this.calLastSync.length > 0) {
                    Text(`上次同步：${this.calLastSync}`)
                      .fontSize(10)
                      .fontColor($r('app.color.muted'))
                      .width('100%')
                  }
                }
                .width('100%')
                .padding({ top: 12, bottom: 12 })
                .alignItems(HorizontalAlign.Start)
              }
              this.RowDivider()
              Text('带截止日的未完成任务会以「全天事件」推送到你的 Gitee 仓库；iPhone 在「日历 → 账户 → 添加订阅日历」粘贴链接即可，订阅约每 30 分钟自动刷新。链接含随机段，仅持有完整地址者可见。')
                .fontSize(10)
                .fontColor($r('app.color.muted'))
                .width('100%')
                .padding({ top: 10, bottom: 12 })
            }
            .width('100%')
            .padding({ left: 14, right: 14 })
            .backgroundColor($r('app.color.card'))
            .borderRadius(16)
            .alignItems(HorizontalAlign.Start)

            /* ==================== 数据清理 ==================== */
            this.GroupTitle('数据清理')
            Column() {
              Row({ space: 10 }) {
                this.Chip('清理已完成', () => {
                  this.confirmClearCompleted();
                }, false)
                this.Chip('清空本账号', () => {
                  this.confirmClearAll();
                }, true)
              }
              .width('100%')
              .padding({ top: 12, bottom: 12 })
            }
            .width('100%')
            .padding({ left: 14, right: 14 })
            .backgroundColor($r('app.color.card'))
            .borderRadius(16)
            .alignItems(HorizontalAlign.Start)

            /* ==================== 关于 ==================== */
            this.GroupTitle('关于')
            Column() {
              /* 折叠头：点按展开 / 收起 */
              Row() {
                Text('象限待办')
                  .fontSize(14)
                  .fontColor($r('app.color.fg'))
                  .layoutWeight(1)
                Text(`v${APP_VERSION}`)
                  .fontSize(12)
                  .fontColor($r('app.color.muted'))
                SymbolGlyph($r('sys.symbol.chevron_down'))
                  .fontSize(13)
                  .fontColor([$r('app.color.muted')])
                  .margin({ left: 6 })
                  .rotate({ angle: this.aboutExpanded ? 180 : 0 })
              }
              .width('100%')
              .padding({ top: 13, bottom: 13 })
              .onClick(() => {
                this.aboutExpanded = !this.aboutExpanded;
              })

              if (this.aboutExpanded) {
                this.RowDivider()

                Row() {
                  Text('应用')
                    .fontSize(14)
                    .fontColor($r('app.color.fg'))
                    .layoutWeight(1)
                  Text('象限待办')
                    .fontSize(12)
                    .fontColor($r('app.color.muted'))
                }
                .width('100%')
                .padding({ top: 13, bottom: 13 })

                this.RowDivider()

                Row() {
                  Text('系统要求')
                    .fontSize(14)
                    .fontColor($r('app.color.fg'))
                    .layoutWeight(1)
                  Text('HarmonyOS 7.0（API 26）+')
                    .fontSize(12)
                    .fontColor($r('app.color.muted'))
                }
                .width('100%')
                .padding({ top: 13, bottom: 13 })

                this.RowDivider()

                Row() {
                  Text('源码')
                    .fontSize(14)
                    .fontColor($r('app.color.fg'))
                    .layoutWeight(1)
                  Text('GitHub · quadrant-todo')
                    .fontSize(12)
                    .fontColor($r('app.color.muted'))
                    .maxLines(1)
                }
                .width('100%')
                .padding({ top: 13, bottom: 13 })

                this.RowDivider()

                Column({ space: 6 }) {
                  Text('一款本地优先的四象限任务管理应用：按「重要 / 紧急」两维把待办放进四个象限，任务默认只存在本机数据库（RDB），可选备份到云端或写入系统日历。')
                    .fontSize(10)
                    .fontColor($r('app.color.muted'))
                  Text('任务与账号均不上传（云备份由你主动开启除外），卸载应用即清除全部本地数据。')
                    .fontSize(10)
                    .fontColor($r('app.color.muted'))
                  Text('源码说明：本应用是开源项目 quadrant-todo（github.com/jailedxiu/quadrant-todo）的 HarmonyOS 移植版，界面与数据层为 ArkTS 重写，遵循原项目开源许可。')
                    .fontSize(10)
                    .fontColor($r('app.color.muted'))
                  Text('免责条款：本应用按「现状」提供，不作任何明示或默示的担保。任务数据保存在本机，请定期使用备份功能；因设备故障、误操作、卸载或第三方服务（华为云 / Gitee）异常导致的数据丢失，开发者不承担任何责任。')
                    .fontSize(10)
                    .fontColor($r('app.color.muted'))
                }
                .width('100%')
                .padding({ top: 12, bottom: 16 })
                .alignItems(HorizontalAlign.Start)
              }
            }
            .width('100%')
            .padding({ left: 14, right: 14 })
            .backgroundColor($r('app.color.card'))
            .borderRadius(16)
            .alignItems(HorizontalAlign.Start)

            Text('')
              .width('100%')
              .height(10)
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
        }
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Off)
        .align(Alignment.Top)
      }
      .width('100%')
      .height('88%')
      .padding({ left: 18, right: 18, top: 18, bottom: 22 })
      .backgroundColor($r('app.color.bg'))
      .borderRadius({ topLeft: 20, topRight: 20 })
    }
    .width('100%')
    .height('100%')
  }

  /** 底部常驻悬浮栏：五个 44vp 圆形大色块，圆角弧与圆形四角等距 8vp */
  @Builder
  FloatingBar() {
    Stack({ alignContent: Alignment.Center }) {
      if (this.settings.materialLevel > MAT_OFF) {
        Column()
          .width('100%')
          .height('100%')
          .radialGradient({
            center: ['20%', '0%'],
            radius: glowRadiusOf(this.settings.materialLevel),
            colors: this.glowStops()
          })
          .opacity(glowOpacityOf(this.settings.materialLevel))
          .hitTestBehavior(HitTestMode.None)
      }

      Row() {
        // 左侧唯一「新建待办」：圆形大色块，图标与文字都在圆内
        Column() {
          Text(this.createOpen ? '−' : '＋')
            .fontSize(19)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.on_accent'))
            .height(21)
          Text(this.createOpen ? '收起' : '新建')
            .fontSize(9)
            .fontColor($r('app.color.on_accent'))
        }
        .width(DOCK_KEY_SIZE)
        .height(DOCK_KEY_SIZE)
        .justifyContent(FlexAlign.Center)
        .backgroundColor($r('app.color.accent'))
        .borderRadius(DOCK_KEY_SIZE / 2)
        .onClick(() => {
          this.toggleCreateCard();
        })

        Blank()

        Row({ space: 6 }) {
          ForEach(QUADRANTS, (meta: QuadrantMeta) => {
            this.QuadrantKey(meta)
          }, (meta: QuadrantMeta) => `bar-${meta.key}-${this.createQuadrant === meta.key ? 1 : 0}`)
        }
      }
      .width('100%')
      .height(DOCK_KEY_SIZE)
      .padding({ left: DOCK_PADDING, right: DOCK_PADDING })
    }
    .width('calc(100% - 24vp)')
    .height(DOCK_HEIGHT)
    .backgroundColor($r('app.color.card'))
    .borderRadius(DOCK_RADIUS)
    .border({ width: 0.5, color: $r('app.color.border') })
    .shadow(this.dockShadow())
    .clip(true)
    .margin({ right: 12, bottom: this.dockBottom() })
  }

  /** dock 象限键：44vp 实心圆形大色块，选中时切到饱和象限色并加白色外环 */
  @Builder
  QuadrantKey(meta: QuadrantMeta) {
    Text(`${meta.key}`)
      .fontSize(18)
      .fontWeight(FontWeight.Bold)
      .fontColor(this.createQuadrant === meta.key ? $r('app.color.on_accent') : quadrantDot(meta.key))
      .width(DOCK_KEY_SIZE)
      .height(DOCK_KEY_SIZE)
      .textAlign(TextAlign.Center)
      .backgroundColor(this.createQuadrant === meta.key ? quadrantDot(meta.key) : quadrantFill(meta.key))
      .borderRadius(DOCK_KEY_SIZE / 2)
      .border({
        width: this.createQuadrant === meta.key ? 2 : 0.5,
        color: this.createQuadrant === meta.key ? $r('app.color.card') : $r('app.color.border')
      })
      .onClick(() => {
        this.selectCreateQuadrant(meta.key);
      })
  }

  /** 填写小弹窗：贴在键盘上沿，保持纯色；沉浸光感不作用于此 */
  @Builder
  CreateCard() {
    Column() {
      Row({ space: 6 }) {
        Circle()
          .width(7)
          .height(7)
          .fill(quadrantDot(this.createQuadrant))
        Text(quadrantMeta(this.createQuadrant).name)
          .fontSize(12)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.fg'))
        Text('· dock 切换象限')
          .fontSize(10)
          .fontColor($r('app.color.muted'))
        Blank()
        Text('✕')
          .fontSize(14)
          .fontColor($r('app.color.muted'))
          .padding({ left: 8, right: 2, top: 2, bottom: 2 })
          .onClick(() => {
            this.closeCreateCard();
          })
      }
      .width('100%')
      .margin({ bottom: 8 })

      Row({ space: 8 }) {
        TextInput({ placeholder: '要做什么？', text: this.createTitle })
          .id('createInput')
          .defaultFocus(true)
          .placeholderColor($r('app.color.muted'))
          .placeholderFont({ size: 13 })
          .fontSize(14)
          .fontColor($r('app.color.fg'))
          .height(40)
          .layoutWeight(1)
          .borderRadius(12)
          .padding({ left: 12, right: 12 })
          .backgroundColor($r('app.color.bg'))
          .onChange((value: string) => {
            this.createTitle = value;
          })
          .onSubmit(() => {
            this.commitCreate();
          })

        Button() {
          Text('↑')
            .fontSize(18)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.on_accent'))
        }
        .width(40)
        .height(40)
        .backgroundColor($r('app.color.accent'))
        .borderRadius(12)
        .opacity(this.createTitle.trim().length > 0 ? 1 : 0.5)
        .enabled(this.createTitle.trim().length > 0)
        .onClick(() => {
          this.commitCreate();
        })
      }
      .width('100%')

      Row({ space: 5 }) {
        ForEach(DUE_OPTIONS, (opt: DueOption) => {
          this.CreateDueChip(opt)
        }, (opt: DueOption) => `cdue-${opt.offset}-${this.createDuePicked(opt.offset) ? 1 : 0}`)

        Blank()
        Text(this.createImportant ? '● 重要' : '○ 重要')
          .fontSize(10)
          .fontColor(this.createImportant ? $r('app.color.on_accent') : $r('app.color.muted'))
          .padding({ left: 9, right: 9, top: 5, bottom: 5 })
          .backgroundColor(this.createImportant ? $r('app.color.accent') : $r('app.color.bg'))
          .borderRadius(10)
          .onClick(() => {
            this.createImportant = !this.createImportant;
          })
      }
      .width('100%')
      .margin({ top: 8 })
    }
    .width('calc(100% - 24vp)')
    .padding({ left: 12, right: 12, top: 12, bottom: 12 })
    .backgroundColor($r('app.color.card'))
    .borderRadius(this.createCardRadius())
    .border({ width: 0.5, color: $r('app.color.border') })
    .shadow(this.cardShadow())
    .margin({ right: 12, bottom: this.createCardBottom() })
    .onAreaChange((_old: Area, newValue: Area) => {
      // 实测高度供 dock 上移使用；字体跟随系统缩放后依然不会与卡片重叠
      this.createCardHeight = newValue.height as number;
    })
  }

  @Builder
  CreateDueChip(opt: DueOption) {
    Text(opt.label)
      .fontSize(10)
      .fontColor(this.createDuePicked(opt.offset) ? $r('app.color.on_accent') : $r('app.color.fg'))
      .padding({ left: 9, right: 9, top: 5, bottom: 5 })
      .backgroundColor(this.createDuePicked(opt.offset) ? $r('app.color.accent') : $r('app.color.bg'))
      .borderRadius(10)
      .onClick(() => {
        this.createDue = opt.offset < 0 ? 0 : DateUtil.dayOffset(opt.offset);
      })
  }

  build() {
    Stack({ alignContent: Alignment.BottomEnd }) {
      // 主页面为纯色背景，与透明状态栏同色；沉浸光感只作用于底部 dock 栏
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

      // 全应用唯一的「新建待办」模块：圆形 dock 常驻，填写小弹窗紧贴键盘按需展开
      if (this.ready && this.agreed && !this.showEditor && !this.showRuler &&
        !this.showDone && !this.showSettings) {
        if (this.createOpen) {
          this.CreateCard()
        }
        this.FloatingBar()
      }

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

      if (!this.agreed) {
        this.AgreementPanel()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.bg'))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .padding({ top: this.topInset, bottom: this.bottomInset })
  }
}
