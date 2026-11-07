/**
 * 沉浸光感（HarmonyOS 7 / API 26）档位服务。
 *
 * 官方文档的关键约束：组件级 systemMaterial 只在弹窗类组件、Slider/Toggle/Select、
 * Navigation 标题栏与底部悬浮 TabBar 上生效；普通 Column/Row 设置不生效。
 * 因此本应用的系统材质统一交给 CustomDialog 的 options.systemMaterial，
 * 主界面的氛围光晕用渐变层独立实现（见 Index.ets 的 AmbientGlow）。
 *
 * 五档材质仅在高、中算力设备上有区分度；低算力设备由系统降级为纯色 + 阴影，
 * 此处通过 isImmersiveMaterialSupported() 主动回退，避免出现「设了却没效果」的困惑。
 */
import { uiMaterial } from '@kit.ArkUI';
import { MAT_OFF, MAT_REGULAR, MAT_THICK, MAT_THIN } from '../model/AppSettings';

/** 档位索引与 AppSettings 中的 MAT_* 常量一一对应 */
const STYLE_TABLE: uiMaterial.ImmersiveStyle[] = [
  uiMaterial.ImmersiveStyle.ULTRA_THIN,
  uiMaterial.ImmersiveStyle.ULTRA_THIN,
  uiMaterial.ImmersiveStyle.THIN,
  uiMaterial.ImmersiveStyle.REGULAR,
  uiMaterial.ImmersiveStyle.THICK,
  uiMaterial.ImmersiveStyle.ULTRA_THICK
];

/** 档位 → 系统材质样式 */
export function materialStyleOf(level: number): uiMaterial.ImmersiveStyle {
  if (level < 0 || level >= STYLE_TABLE.length) {
    return uiMaterial.ImmersiveStyle.REGULAR;
  }
  return STYLE_TABLE[level];
}

/** 当前设备是否支持沉浸式材质（由设备算力决定，不可修改） */
export function immersiveSupported(): boolean {
  try {
    return uiMaterial.isImmersiveMaterialSupported();
  } catch (err) {
    return false;
  }
}

/** 设备算力等级文案，用于设置页展示 */
export function deviceLevelLabel(): string {
  try {
    const level: uiMaterial.MaterialLevel = uiMaterial.getGlobalMaterialLevel();
    if (level === uiMaterial.MaterialLevel.EXQUISITE) {
      return '精致（高算力）';
    }
    if (level === uiMaterial.MaterialLevel.GENTLE) {
      return '柔和（中算力）';
    }
    return '流畅（低算力）';
  } catch (err) {
    return '未知';
  }
}

/**
 * 生成弹窗材质对象。
 * - 关闭档位 / 设备不支持 → Material.empty（显式关闭，不能传 undefined，undefined 是恢复默认效果）
 * - 其余档位 → ImmersiveMaterial，档位越高越厚，并开启交互形变与触点光感
 */
export function dialogMaterialOf(level: number): uiMaterial.Material {
  if (level <= MAT_OFF || !immersiveSupported()) {
    return uiMaterial.Material.empty;
  }
  const options: uiMaterial.ImmersiveOptions = {
    style: materialStyleOf(level),
    colorInvert: false,
    applyShadow: true,
    interactive: level >= MAT_THIN,
    lightEffect: level >= MAT_THICK ? { color: Color.White } : null
  };
  return new uiMaterial.ImmersiveMaterial(options);
}

/** 主界面氛围光晕透明度：关闭为 0，其余随档位递增（0.10 → 0.26） */
export function glowOpacityOf(level: number): number {
  if (level <= MAT_OFF) {
    return 0;
  }
  return 0.10 + (level - 1) * 0.04;
}

/** 氛围光晕半径（vp）：档位越高光域越收敛，形成更明确的视觉焦点 */
export function glowRadiusOf(level: number): number {
  if (level <= MAT_OFF) {
    return 0;
  }
  return 340 - (level - 1) * 30;
}
