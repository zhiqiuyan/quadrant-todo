/**
 * 4*4 桌面卡片（中卡片，接近方形）
 * 只呈现「四格各有多少」与当前账号，不复述任务标题，保证小尺寸下不拥挤。
 */
let storage4x4: LocalStorage = new LocalStorage();

interface CardAction4x4 {
  action: string;
  abilityName: string;
  params: Record<string, string>;
}

@Entry(storage4x4)
@Component
struct Widget4x4 {
  @LocalStorageProp('accountName') accountName: string = '我';
  @LocalStorageProp('total') total: number = 0;
  @LocalStorageProp('doneToday') doneToday: number = 0;
  @LocalStorageProp('q1') q1: number = 0;
  @LocalStorageProp('q2') q2: number = 0;
  @LocalStorageProp('q3') q3: number = 0;
  @LocalStorageProp('q4') q4: number = 0;

  private open(): void {
    const action: CardAction4x4 = {
      action: 'router',
      abilityName: 'EntryAbility',
      params: {}
    };
    postCardAction(this, action);
  }

  @Builder
  Cell(key: number, title: string) {
    Column({ space: 2 }) {
      Text(title)
        .fontSize(10)
        .fontColor($r('app.color.muted'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      Text(key === 1 ? this.q1.toString() : key === 2 ? this.q2.toString() :
        key === 3 ? this.q3.toString() : this.q4.toString())
        .fontSize(19)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.fg'))
    }
    .layoutWeight(1)
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .borderRadius(12)
    .backgroundColor(key === 1 ? $r('app.color.q1_bg') : key === 2 ? $r('app.color.q2_bg') :
      key === 3 ? $r('app.color.q3_bg') : $r('app.color.q4_bg'))
  }

  build() {
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
        Text(this.total > 0 ? `${this.total} 项` : '清空')
          .fontSize(10)
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
