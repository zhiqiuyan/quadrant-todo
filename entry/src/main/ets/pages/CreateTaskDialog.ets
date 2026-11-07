/**
 * 全局唯一的「新建待办」入口弹窗（HarmonyOS 7 / API 26 空间化风格）。
 *
 * 设计要点：
 * 1. 四个象限不再各自带输入框，所有新建动作统一由本弹窗承接；象限在弹窗内一次点选，
 *    不再出现二次选择弹层。
 * 2. 弹窗容器通过 CustomDialogControllerOptions.systemMaterial 获得系统沉浸材质；
 *    档位由设置页控制，关闭档位使用 Material.empty 回退到自绘纯色卡片。
 * 3. 内部叠加一层「光随指动」的径向渐变光晕，按档位调整强度与半径。
 *    该层用 HitTestMode.None 让出触摸事件，不影响 TextInput 与按钮。
 */
import { QuadrantMeta, QUADRANTS } from '../model/TaskItem';
import { MAT_OFF, MAT_REGULAR } from '../model/AppSettings';
import { glowOpacityOf, glowRadiusOf } from '../data/MaterialService';
import { DateUtil } from '../common/DateUtil';

class DueOption {
  label: string;
  offset: number;

  constructor(label: string, offset: number) {
    this.label = label;
    this.offset = offset;
  }
}

/** offset < 0 代表「不设截止日」 */
const DUE_OPTIONS: DueOption[] = [
  new DueOption('无', -1),
  new DueOption('今天', 0),
  new DueOption('明天', 1),
  new DueOption('七天后', 7)
];

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

@CustomDialog
export struct CreateTaskDialog {
  controller: CustomDialogController;
  /** 打开时预选的象限（取设置里的默认象限） */
  initialQuadrant: number = 1;
  /** 沉浸光感档位，驱动光晕强度 */
  materialLevel: number = MAT_REGULAR;
  /** (标题, 象限, 截止日, 重要) */
  onSave: (title: string, quadrant: number, dueAt: number, important: boolean) => void =
    (title: string, quadrant: number, dueAt: number, important: boolean) => {
    };

  @State title: string = '';
  @State quadrant: number = 1;
  @State dueAt: number = 0;
  @State important: boolean = false;
  /** 光斑中心（vp，相对弹窗左上角） */
  @State glowX: number = 180;
  @State glowY: number = 30;
  private lastGlowMove: number = 0;

  aboutToAppear(): void {
    this.quadrant = this.initialQuadrant;
  }

  private duePicked(offset: number): boolean {
    if (offset < 0) {
      return this.dueAt === 0;
    }
    return this.dueAt === DateUtil.dayOffset(offset);
  }

  private commit(): void {
    const value: string = this.title.trim();
    if (value.length === 0) {
      return;
    }
    this.onSave(value, this.quadrant, this.dueAt, this.important);
    this.controller.close();
  }

  /** 显式类型，避免 ArkTS 对对象字面量三元推断失败 */
  private optionShadow(selected: boolean): ShadowOptions {
    if (selected) {
      return { radius: 12, color: '#1A2563EB', offsetX: 0, offsetY: 3 };
    }
    return { radius: 0, color: '#00000000', offsetX: 0, offsetY: 0 };
  }

  /** 显式类型，满足 RadialGradientOptions.colors 的元组要求 */
  private glowStops(): [ResourceColor, number][] {
    return [['#60A5FA', 0], ['#00000000', 1]];
  }

  @Builder
  QuadOption(meta: QuadrantMeta) {
    Row() {
      Column() {
        Circle()
          .width(9)
          .height(9)
          .fill(quadrantDot(meta.key))
          .margin({ right: 6 })
      }
      .justifyContent(FlexAlign.Center)

      Column() {
        Text(meta.name)
          .fontSize(13)
          .fontWeight(this.quadrant === meta.key ? FontWeight.Medium : FontWeight.Normal)
          .fontColor(this.quadrant === meta.key ? $r('app.color.accent') : $r('app.color.fg'))
          .maxLines(1)
        Text(meta.hint)
          .fontSize(9)
          .fontColor($r('app.color.muted'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ top: 2 })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
    }
    .width('48%')
    .padding({ left: 10, right: 8, top: 10, bottom: 10 })
    .margin({ bottom: 8 })
    .backgroundColor(this.quadrant === meta.key ? $r('app.color.accent_soft') : $r('app.color.bg'))
    .borderRadius(14)
    .border({
      width: this.quadrant === meta.key ? 1.5 : 0.5,
      color: this.quadrant === meta.key ? $r('app.color.accent') : $r('app.color.border')
    })
    .shadow(this.optionShadow(this.quadrant === meta.key))
    .onClick(() => {
      this.quadrant = meta.key;
    })
  }

  @Builder
  DueChip(opt: DueOption) {
    Text(opt.label)
      .fontSize(12)
      .fontColor(this.duePicked(opt.offset) ? $r('app.color.on_accent') : $r('app.color.fg'))
      .padding({ left: 14, right: 14, top: 7, bottom: 7 })
      .backgroundColor(this.duePicked(opt.offset) ? $r('app.color.accent') : $r('app.color.bg'))
      .borderRadius(14)
      .margin({ right: 8, bottom: 8 })
      .onClick(() => {
        this.dueAt = opt.offset < 0 ? 0 : DateUtil.dayOffset(opt.offset);
      })
  }

  build() {
    Stack({ alignContent: Alignment.Top }) {
      // 空间化光晕：光随指动，档位越高越亮、光域越收敛
      if (this.materialLevel > MAT_OFF) {
        Column()
          .width('100%')
          .height('100%')
          .radialGradient({
            center: [this.glowX, this.glowY],
            radius: glowRadiusOf(this.materialLevel),
            colors: this.glowStops()
          })
          .opacity(glowOpacityOf(this.materialLevel))
          .hitTestBehavior(HitTestMode.None)
      }

      Column() {
        // 7.0 半模态把手
        Row()
          .width(38)
          .height(4)
          .borderRadius(2)
          .backgroundColor($r('app.color.border'))
          .margin({ top: 10, bottom: 4 })

        Row() {
          Column() {
            Text('新建待办')
              .fontSize(20)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.fg'))
            Text('选择象限，填写内容')
              .fontSize(11)
              .fontColor($r('app.color.muted'))
              .margin({ top: 2 })
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)

          Text('✕')
            .fontSize(16)
            .fontColor($r('app.color.muted'))
            .padding(8)
            .onClick(() => {
              this.controller.close();
            })
        }
        .width('100%')

        TextInput({ placeholder: '要做什么？', text: this.title })
          .placeholderColor($r('app.color.muted'))
          .placeholderFont({ size: 14 })
          .fontSize(15)
          .fontColor($r('app.color.fg'))
          .height(48)
          .width('100%')
          .borderRadius(16)
          .padding({ left: 14, right: 14 })
          .backgroundColor($r('app.color.bg'))
          .margin({ top: 18 })
          .onChange((value: string) => {
            this.title = value;
          })
          .onSubmit(() => {
            this.commit();
          })

        Text('归入象限')
          .fontSize(12)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.muted'))
          .margin({ top: 20, bottom: 10 })
          .width('100%')

        Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.SpaceBetween }) {
          ForEach(QUADRANTS, (meta: QuadrantMeta) => {
            this.QuadOption(meta)
          }, (meta: QuadrantMeta) => `quad-${meta.key}-${this.quadrant === meta.key ? 1 : 0}`)
        }
        .width('100%')

        Text('截止日期')
          .fontSize(12)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.muted'))
          .margin({ top: 8, bottom: 10 })
          .width('100%')

        Flex({ wrap: FlexWrap.Wrap }) {
          ForEach(DUE_OPTIONS, (opt: DueOption) => {
            this.DueChip(opt)
          }, (opt: DueOption) => `due-${opt.offset}-${this.duePicked(opt.offset) ? 1 : 0}`)
        }
        .width('100%')

        Row() {
          Column() {
            Text('标记为重要')
              .fontSize(13)
              .fontColor($r('app.color.fg'))
            Text('在日历与卡片中优先呈现')
              .fontSize(10)
              .fontColor($r('app.color.muted'))
              .margin({ top: 2 })
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)

          Toggle({ type: ToggleType.Switch, isOn: this.important })
            .selectedColor($r('app.color.accent'))
            .onChange((isOn: boolean) => {
              this.important = isOn;
            })
        }
        .width('100%')
        .padding({ top: 10, bottom: 10 })
        .margin({ top: 4 })

        Row({ space: 10 }) {
          Button() {
            Text('取消')
              .fontSize(14)
              .fontColor($r('app.color.fg'))
          }
          .layoutWeight(1)
          .constraintSize({ minHeight: 46 })
          .backgroundColor($r('app.color.bg'))
          .borderRadius(14)
          .onClick(() => {
            this.controller.close();
          })

          Button() {
            Text('创建待办')
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.on_accent'))
          }
          .layoutWeight(1)
          .constraintSize({ minHeight: 46 })
          .backgroundColor($r('app.color.accent'))
          .borderRadius(14)
          .opacity(this.title.trim().length > 0 ? 1 : 0.5)
          .enabled(this.title.trim().length > 0)
          .onClick(() => {
            this.commit();
          })
        }
        .width('100%')
        .margin({ top: 12 })
      }
      .width('100%')
      .padding({ left: 20, right: 20, top: 6, bottom: 28 })
      .backgroundColor($r('app.color.card'))
      .borderRadius({ topLeft: 28, topRight: 28 })
      .border({ width: 0.5, color: $r('app.color.border') })
      .clip(true)
      .onTouch((event: TouchEvent) => {
        if (this.materialLevel <= MAT_OFF || event.touches.length === 0) {
          return;
        }
        const now: number = Date.now();
        if (now - this.lastGlowMove < 60) {
          return;
        }
        this.lastGlowMove = now;
        const x: number = event.touches[0].x;
        const y: number = event.touches[0].y;
        this.getUIContext().animateTo({ duration: 140, curve: Curve.EaseOut }, () => {
          this.glowX = x;
          this.glowY = y;
        });
      })
    }
    .width('100%')
    .borderRadius({ topLeft: 28, topRight: 28 })
    .clip(true)
  }
}
