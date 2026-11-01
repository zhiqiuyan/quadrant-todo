/**
 * 6*4 桌面卡片（大卡片）
 * 四象限铺满整卡：每格头部是名称与计数，格内列出该象限的任务标题；
 * 顶部一行保留账号与今日完成，底部右侧保留更新时间。
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
  @LocalStorageProp('accountName') accountName: string = '我';
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

  private open(): void {
    const action: CardAction6x4 = {
      action: 'router',
      abilityName: 'EntryAbility',
      params: {}
    };
    postCardAction(this, action);
  }

  @Builder
  TaskLine(item: WTask6x4) {
    Row({ space: 4 }) {
      Row()
        .width(4)
        .height(4)
        .borderRadius(2)
        .backgroundColor(item.o ? $r('app.color.danger') : $r('app.color.muted'))
        .opacity(item.o ? 1 : 0.7)
        .margin({ top: 4 })
      Text(item.t)
        .fontSize(10)
        .fontColor(item.o ? $r('app.color.danger') : $r('app.color.fg'))
        .opacity(item.o ? 1 : 0.85)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
    }
    .width('100%')
  }

  @Builder
  Cell(key: number, title: string) {
    Column({ space: 3 }) {
      Row() {
        Text(title)
          .fontSize(10)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.muted'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
        Text(this.countOf(key).toString())
          .fontSize(12)
          .fontWeight(FontWeight.Bold)
          .fontColor(key === 4 ? $r('app.color.muted') : $r('app.color.fg'))
      }
      .width('100%')

      if (this.tasksOf(key).length > 0) {
        Column({ space: 3 }) {
          ForEach(this.tasksOf(key), (item: WTask6x4) => {
            this.TaskLine(item)
          }, (item: WTask6x4) => `${key}-${item.t}`)
        }
        .width('100%')
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
      } else {
        Column() {
          Text('空')
            .fontSize(10)
            .fontColor($r('app.color.muted'))
            .opacity(0.7)
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
    .borderRadius(14)
    .backgroundColor(key === 1 ? $r('app.color.q1_bg') : key === 2 ? $r('app.color.q2_bg') :
      key === 3 ? $r('app.color.q3_bg') : $r('app.color.q4_bg'))
  }

  build() {
    Column({ space: 6 }) {
      Row() {
        Text(this.accountName.substring(0, 1))
          .fontSize(10)
          .fontColor('#FFFFFF')
          .width(17)
          .height(17)
          .textAlign(TextAlign.Center)
          .borderRadius(9)
          .backgroundColor($r('app.color.accent'))
        Text(this.accountName)
          .fontSize(11)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.fg'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
          .margin({ left: 5 })
        Text(`${this.total} 项 · 今日完成 ${this.doneToday}`)
          .fontSize(9)
          .fontColor($r('app.color.muted'))
      }
      .width('100%')

      Row({ space: 6 }) {
        this.Cell(1, '重要紧急')
        this.Cell(2, '重要不急')
      }
      .width('100%')
      .layoutWeight(1)

      Row({ space: 6 }) {
        this.Cell(3, '紧急不重')
        this.Cell(4, '都不重要')
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
