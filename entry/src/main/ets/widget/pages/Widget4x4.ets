/**
 * 4*4 桌面卡片（中卡片，接近方形）
 * 四象限铺满整卡：每格头部是名称与计数，格内直接列出该象限的任务标题。
 */
let storage4x4: LocalStorage = new LocalStorage();

interface CardAction4x4 {
  action: string;
  abilityName: string;
  params: Record<string, string>;
}

interface WTask4x4 {
  t: string;
  o: boolean;
  d: string;
}

@Entry(storage4x4)
@Component
struct Widget4x4 {
  @LocalStorageProp('accountName') accountName: string = '我';
  @LocalStorageProp('total') total: number = 0;
  @LocalStorageProp('q1') q1: number = 0;
  @LocalStorageProp('q2') q2: number = 0;
  @LocalStorageProp('q3') q3: number = 0;
  @LocalStorageProp('q4') q4: number = 0;
  @LocalStorageProp('q1Json') q1Json: string = '[]';
  @LocalStorageProp('q2Json') q2Json: string = '[]';
  @LocalStorageProp('q3Json') q3Json: string = '[]';
  @LocalStorageProp('q4Json') q4Json: string = '[]';

  /** 4*4 格子小，每格最多展示 3 条 */
  private static MAX_LINES: number = 3;

  private tasksOf(key: number): WTask4x4[] {
    const raw: string = key === 1 ? this.q1Json : key === 2 ? this.q2Json :
      key === 3 ? this.q3Json : this.q4Json;
    try {
      const list: WTask4x4[] = JSON.parse(raw) as WTask4x4[];
      return list.slice(0, Widget4x4.MAX_LINES);
    } catch (err) {
      return [];
    }
  }

  private countOf(key: number): number {
    return key === 1 ? this.q1 : key === 2 ? this.q2 : key === 3 ? this.q3 : this.q4;
  }

  private open(): void {
    const action: CardAction4x4 = {
      action: 'router',
      abilityName: 'EntryAbility',
      params: {}
    };
    postCardAction(this, action);
  }

  @Builder
  TaskLine(item: WTask4x4) {
    Row({ space: 4 }) {
      Row()
        .width(3)
        .height(3)
        .borderRadius(2)
        .backgroundColor($r('app.color.muted'))
        .opacity(0.7)
      Text(item.t)
        .fontSize(9)
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
          .fontSize(9)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.muted'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
        Text(this.countOf(key).toString())
          .fontSize(10)
          .fontWeight(FontWeight.Bold)
          .fontColor(key === 4 ? $r('app.color.muted') : $r('app.color.fg'))
      }
      .width('100%')

      if (this.tasksOf(key).length > 0) {
        Column({ space: 2 }) {
          ForEach(this.tasksOf(key), (item: WTask4x4, idx: number) => {
            this.TaskLine(item)
          }, (item: WTask4x4) => `${key}-${item.t}`)
        }
        .width('100%')
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
      } else {
        Column() {
          Text('空')
            .fontSize(9)
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
    .padding(6)
    .borderRadius(12)
    .backgroundColor(key === 1 ? $r('app.color.q1_bg') : key === 2 ? $r('app.color.q2_bg') :
      key === 3 ? $r('app.color.q3_bg') : $r('app.color.q4_bg'))
  }

  build() {
    Column({ space: 5 }) {
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
    .padding(8)
    .backgroundColor($r('app.color.card'))
    .onClick(() => {
      this.open();
    })
  }
}
