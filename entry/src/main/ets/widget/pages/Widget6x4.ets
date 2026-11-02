/**
 * 6*4 桌面卡片（大卡片）
 * 与主界面保持同一套视觉：顶栏为每日一言 + 今日完成；
 * 四象限格 = 象限全名 + 数量 + 空态提示（与主界面同文案）+ 任务行（勾选框样式）。
 * （HarmonyOS 卡片尺寸枚举没有 4*6，宽幅档位即 6*4。）
 */
let storage6x4: LocalStorage = new LocalStorage();

interface CardAction6x4 {
  action: string;
  abilityName: string;
  params: Record<string, string>;
}

interface WTask6x4 {
  t: string;
  o: boolean;
  d: string;
}

@Entry(storage6x4)
@Component
struct Widget6x4 {
  @LocalStorageProp('total') total: number = 0;
  @LocalStorageProp('doneToday') doneToday: number = 0;
  @LocalStorageProp('q1') q1: number = 0;
  @LocalStorageProp('q2') q2: number = 0;
  @LocalStorageProp('q3') q3: number = 0;
  @LocalStorageProp('q4') q4: number = 0;
  @LocalStorageProp('q1Json') q1Json: string = '[]';
  @LocalStorageProp('q2Json') q2Json: string = '[]';
  @LocalStorageProp('q3Json') q3Json: string = '[]';
  @LocalStorageProp('q4Json') q4Json: string = '[]';
  @LocalStorageProp('linesPerQ') linesPerQ: number = 3;
  @LocalStorageProp('quoteText') quoteText: string = '';
  @LocalStorageProp('updatedText') updatedText: string = '';

  private tasksOf(key: number): WTask6x4[] {
    const raw: string = key === 1 ? this.q1Json : key === 2 ? this.q2Json :
      key === 3 ? this.q3Json : this.q4Json;
    try {
      const list: WTask6x4[] = JSON.parse(raw) as WTask6x4[];
      const max: number = this.linesPerQ > 0 ? this.linesPerQ : 3;
      return list.slice(0, max);
    } catch (err) {
      return [];
    }
  }

  private countOf(key: number): number {
    return key === 1 ? this.q1 : key === 2 ? this.q2 : key === 3 ? this.q3 : this.q4;
  }

  private hintOf(key: number): string {
    return key === 1 ? '立刻做完，尽量清空' : key === 2 ? '主战场，预约进日历' :
      key === 3 ? '委托 / 缩短 / 批量处理' : '删掉，或只在闲时碰';
  }

  private open(): void {
    const action: CardAction6x4 = {
      action: 'router',
      abilityName: 'EntryAbility',
      params: {}
    };
    postCardAction(this, action);
  }

  /** 任务行：与主界面 TaskCard 同款勾选框 + 标题 + 到期标签 */
  @Builder
  TaskLine(item: WTask6x4) {
    Row({ space: 5 }) {
      Stack() {
        if (item.o) {
          Text('!')
            .fontSize(9)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.danger'))
        }
      }
      .width(12)
      .height(12)
      .borderRadius(6)
      .border({
        width: 1.5,
        color: item.o ? $r('app.color.danger') : $r('app.color.border')
      })
      .margin({ top: 1 })

      Text(item.t)
        .fontSize(11)
        .fontColor($r('app.color.fg'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)

      if (item.d.length > 0) {
        Text(item.d)
          .fontSize(9)
          .fontColor(item.o ? $r('app.color.danger') : $r('app.color.muted'))
      }
    }
    .width('100%')
  }

  /** 象限格：头部 = 象限全名 + 数量（同主界面）；空态 = 主界面同款提示语 */
  @Builder
  Cell(key: number, title: string) {
    Column() {
      Row() {
        Text(title)
          .fontSize(11)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.fg'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
        Text(this.countOf(key).toString())
          .fontSize(10)
          .fontColor($r('app.color.muted'))
      }
      .width('100%')
      .padding({ left: 2, right: 2 })

      if (this.tasksOf(key).length > 0) {
        Column({ space: 5 }) {
          ForEach(this.tasksOf(key), (item: WTask6x4) => {
            this.TaskLine(item)
          }, (item: WTask6x4) => `${key}-${item.t}`)
        }
        .width('100%')
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
        .margin({ top: 5 })
      } else {
        Column() {
          Text(this.hintOf(key))
            .fontSize(10)
            .fontColor($r('app.color.muted'))
            .textAlign(TextAlign.Center)
            .opacity(0.8)
            .maxLines(2)
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      }
    }
    .layoutWeight(1)
    .height('100%')
    .padding(8)
    .borderRadius(16)
    .backgroundColor(key === 1 ? $r('app.color.q1_bg') : key === 2 ? $r('app.color.q2_bg') :
      key === 3 ? $r('app.color.q3_bg') : $r('app.color.q4_bg'))
  }

  build() {
    Column({ space: 6 }) {
      Row() {
        Text(this.quoteText)
          .fontSize(10)
          .fontColor($r('app.color.muted'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)

        Text(`已完成 ${this.doneToday}`)
          .fontSize(9)
          .fontColor($r('app.color.fg'))
          .padding({ left: 7, right: 7, top: 3, bottom: 3 })
          .backgroundColor($r('app.color.card'))
          .borderRadius(9)
          .margin({ left: 6 })
      }
      .width('100%')

      Row({ space: 6 }) {
        this.Cell(1, '重要紧急')
        this.Cell(2, '重要不紧急')
      }
      .width('100%')
      .layoutWeight(1)

      Row({ space: 6 }) {
        this.Cell(3, '紧急不重要')
        this.Cell(4, '不重要不紧急')
      }
      .width('100%')
      .layoutWeight(1)

      Text(this.updatedText)
        .fontSize(8)
        .fontColor($r('app.color.muted'))
        .opacity(0.7)
        .width('100%')
        .textAlign(TextAlign.End)
    }
    .width('100%')
    .height('100%')
    .padding(10)
    .backgroundColor($r('app.color.card'))
    .onClick(() => {
      this.open();
    })
  }
}
