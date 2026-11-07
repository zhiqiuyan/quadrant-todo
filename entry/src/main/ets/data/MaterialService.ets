/**
 * 沉浸光感档位服务（HarmonyOS 7 / API 26）。
 *
 * 官方约束：组件级 systemMaterial 只在弹窗类组件、Slider/Toggle/Select、
 * Navigation 标题栏与底部悬浮 TabBar 上生效，普通 Column / Row 设置不生效。
 * 本应用的新建模块是「底部 dock 栏 + 键盘上方填写小弹窗」，均为普通容器。
 * 六档光感只作用于 dock 栏，用自绘径向渐变与阴影表达；填写弹窗与主界面保持纯色。
 * uiMaterial 在此仅用于设备算力探测，供设置页展示与低算力降级判断。
 */
import { uiMaterial } from '@kit.ArkUI';
import { MAT_OFF } from '../model/AppSettings';

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

/** 氛围光晕透明度：关闭为 0，其余随档位递增（0.10 → 0.26） */
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
