import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { QuadrantMeta, QUADRANTS, TaskItem, Q1 } from '../model/TaskItem';
import { TaskRepository } from '../data/TaskRepository';
import { DateUtil } from '../common/DateUtil';

const DOMAIN: number = 0x0000;
const TAG: string = 'QuadrantTodo';

@Entry
@Component
struct Index {
  /** 未完成任务全集，四个格子按象限过滤渲染 */
  @State tasks: TaskItem[] = [];
  @State ready: boolean = false;
  @State completedToday: number = 0;

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

  aboutToAppear(): void {
    this.boot();
  }

  /* ==================== 数据 ==================== */

  private async boot(): Promise<void> {
    try {
      const context: common.UIAbilityContext =
        this.getUIContext().getHostContext() as common.UIAbilityContext;
      await TaskRepository.getInstance().init(context);
      await this.reload();
      this.ready = true;
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'boot failed: %{public}s', (err as Error).message);
      this.toast('初始化失败：' + (err as Error).message);
    }
  }

  private async reload(): Promise<void> {
    try {
      this.tasks = await TaskRepository.getInstance().listActive();
      this.completedToday = await TaskRepository.getInstance().countCompletedSince(DateUtil.todayStart());
      if (this.showDone) {
        await this.loadDone();
      }
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'reload failed: %{public}s', (err as Error).message);
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
      await this.reload();
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
    if (this.tasks.length === 0) {
      return '把事放进格子里，脑子就空出来了';
    }
    return `${this.tasks.length} 项待办 · 今日完成 ${this.completedToday}`;
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
      await this.reload();
    } catch (err) {
      this.toast('添加失败：' + (err as Error).message);
    }
  }

  private async toggle(item: TaskItem): Promise<void> {
    try {
      await TaskRepository.getInstance().setCompleted(item.id, !item.completed);
      await this.reload();
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
      this.draftQuadrant = Q1;
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
      await this.reload();
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
      await this.reload();
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
      autoCancel: true,      primaryButton: {
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
      await this.reload();
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
  Header() {
    Row() {
      Column() {
        Text('四象限待办')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.fg'))
        Text(this.subtitle())
          .fontSize(11)
          .fontColor($r('app.color.muted'))
          .margin({ top: 3 })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Text('尺子')
        .fontSize(12)
        .fontColor($r('app.color.accent'))
        .padding({ left: 10, right: 10, top: 7, bottom: 7 })
        .backgroundColor($r('app.color.accent_soft'))
        .borderRadius(14)
        .onClick(() => {
          this.showRuler = true;
        })

      Text('已完成')
        .fontSize(12)
        .fontColor($r('app.color.fg'))
        .padding({ left: 10, right: 10, top: 7, bottom: 7 })
        .backgroundColor($r('app.color.card'))
        .borderRadius(14)
        .margin({ left: 6 })
        .onClick(() => {
          this.openDone();
        })
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 14, bottom: 10 })
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

            Text('清理已完成任务')
              .fontSize(12)
              .fontColor($r('app.color.danger'))
              .padding({ left: 12, right: 12, top: 8, bottom: 8 })
              .backgroundColor($r('app.color.bg'))
              .borderRadius(12)
              .onClick(() => {
                this.confirmClearCompleted();
              })
          }
          .alignItems(HorizontalAlign.Start)
          .width('100%')
          .padding({ top: 12 })
        }
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Off)
      }
      .width('100%')
      .height('72%')
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
    }
    .width('100%')
    .height('100%')
  }
}
