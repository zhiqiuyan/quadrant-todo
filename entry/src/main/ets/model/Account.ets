/**
 * 本地账号：同一台设备上可以有多份互不干扰的四象限清单。
 * 账号只保存在本机（不联网、不上传），作用是「切换身份 / 分隔数据」。
 */
export class Account {
  id: number = 0;
  name: string = '';
  /** 头像配色下标，对应 AVATAR_COLORS */
  colorIndex: number = 0;
  createdAt: number = 0;

  copy(): Account {
    const next: Account = new Account();
    next.id = this.id;
    next.name = this.name;
    next.colorIndex = this.colorIndex;
    next.createdAt = this.createdAt;
    return next;
  }
}

/** 供 JSON 解析使用的原始结构 */
export interface AccountJson {
  id: number;
  name: string;
  colorIndex: number;
  createdAt: number;
}

/** 头像底色候选，尽量覆盖常见色相，保证深色模式下也够亮 */
export const AVATAR_COLORS: string[] = [
  '#2563EB', '#7C3AED', '#DB2777', '#EA580C', '#059669', '#0891B2', '#4B5563', '#B45309'
];

export function avatarColor(index: number): string {
  if (index < 0 || index >= AVATAR_COLORS.length) {
    return AVATAR_COLORS[0];
  }
  return AVATAR_COLORS[index];
}

/** 头像上的文字：取昵称首字 */
export function accountInitial(name: string): string {
  const trimmed: string = name.trim();
  if (trimmed.length === 0) {
    return '我';
  }
  return trimmed.substring(0, 1);
}
