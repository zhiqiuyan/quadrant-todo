/**
 * 6*4 桌面卡片（大卡片，宽幅：6 列 × 4 行）
 * 左侧四象限计数，右侧今日优先清单。
 *
 * 说明：HarmonyOS 卡片尺寸枚举只支持 1*1 / 1*2 / 2*2 / 2*3 / 2*4 / 3*3 / 4*4 / 6*4，
 * 不存在 4*6；「6*4」即用户口语中的「4×6 大卡片」，主要出现在平板与 2in1 上。
 */
let storage6x4: LocalStorage = new LocalStorage();

interface CardAction6x4 {
  action: string;
  abilityName: string;
  params: Record<string, string>;
}

interface WidgetLine6x4 {
  q: number;
  t: string;
  l: string;
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
  @LocalStorageProp('linesJson') linesJson: string = '[]';
  @LocalStorageProp('updatedText') updatedText: string = '';

  private lines(): WidgetLine6x4[] {
    try {
      return JSON.parse(this.linesJson) as WidgetLine6x4[];
    } catch (err) {
      const empty: WidgetLine6x4[] = [];
      return empty;
    }
  }

  private dotColor(quadrant: number): Resource {
    if (quadrant === 1) {
      return $r('app.color.q1_dot');
    }
    if (quadrant === 2) {
      return $r('app.color.q2_dot');
    }
    if (quadrant === 3) {
      return $r('app.color.q3_dot');
    }
    return $r('app.color.q4_dot');
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
  Cell(key: number, title: string, count: number) {
    Column({ space: 2 }) {
      Text(count.toString())
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor(key === 4 ? $r('app.color.muted') : $r('app.color.fg'))
      Text(title)
        .fontSize(9)
        .fontColor($r('app.color.muted'))
        .maxLines(1)
    }
    .layoutWeight(1)
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .borderRadius(12)
    .backgroundColor(key === 1 ? $r('app.color.q1_bg') : key === 2 ? $r('app.color.q2_bg') :
      key === 3 ? $r('app.color.q3_bg') : $r('app.color.q4_bg'))
  }

  build() {
    Row({ space: 12 }) {
      Column({ space: 6 }) {
        Row() {
          Text(this.accountName.substring(0, 1))
            .fontSize(10)
            .fontColor('#FFFFFF')
            .width(18)
            .height(18)
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
        }
        .width('100%')

        Row({ space: 6 }) {
          this.Cell(1, '重要紧急', this.q1)
          this.Cell(2, '重要不急', this.q2)
        }
        .width('100%')
        .layoutWeight(1)

        Row({ space: 6 }) {
          this.Cell(3, '紧急不重', this.q3)
          this.Cell(4, '都不重要', this.q4)
        }
        .width('100%')
        .layoutWeight(1)
      }
      .width('38%')
      .height('100%')

      Column({ space: 5 }) {
        Row() {
          Text(`${this.total} 项待办`)
            .fontSize(11)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.fg'))
          Blank()
          Text(`今日完成 ${this.doneToday}`)
            .fontSize(9)
            .fontColor($r('app.color.muted'))
        }
        .width('100%')

        if (this.lines().length === 0) {
          Column() {
            Text('还没有待办')
              .fontSize(11)
              .fontColor($r('app.color.muted'))
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else {
          Column({ space: 2 }) {
            ForEach(this.lines(), (line: WidgetLine6x4, index: number) => {
              Row({ space: 6 }) {
                Row()
                  .width(5)
                  .height(5)
                  .borderRadius(3)
                  .backgroundColor(this.dotColor(line.q))
                Text(line.t)
                  .fontSize(12)
                  .fontColor($r('app.color.fg'))
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .layoutWeight(1)
                if (line.l.length > 0) {
                  Text(line.l)
                    .fontSize(9)
                    .fontColor($r('app.color.muted'))
                }
              }
              .width('100%')
              .height(24)
            }, (line: WidgetLine6x4, index: number) => `line-${index}`)
          }
          .width('100%')
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)
        }

        Text(this.updatedText)
          .fontSize(8)
          .fontColor($r('app.color.muted'))
          .opacity(0.7)
          .width('100%')
      }
      .layoutWeight(1)
      .height('100%')
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .height('100%')
    .padding(12)
    .backgroundColor($r('app.color.card'))
    .onClick(() => {
      this.open();
    })
  }
}
