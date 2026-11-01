/** 日期工具：全部以「日」为粒度计算，避免时区与时分秒带来的误判。 */
export class DateUtil {
  static readonly DAY_MS: number = 24 * 60 * 60 * 1000;

  /** 取某时间戳当天 00:00:00 的时间戳 */
  static startOfDay(ts: number): number {
    const d: Date = new Date(ts);
    d.setHours(0, 0, 0, 0);
    return d.getTime();
  }

  static todayStart(): number {
    return DateUtil.startOfDay(Date.now());
  }

  /** 相对今天偏移 n 天的 00:00 时间戳 */
  static dayOffset(n: number): number {
    return DateUtil.todayStart() + n * DateUtil.DAY_MS;
  }

  /** 是否已逾期（截止日早于今天） */
  static isOverdue(dueAt: number): boolean {
    if (dueAt <= 0) {
      return false;
    }
    return DateUtil.startOfDay(dueAt) < DateUtil.todayStart();
  }

  /** 是否今天到期 */
  static isToday(dueAt: number): boolean {
    if (dueAt <= 0) {
      return false;
    }
    return DateUtil.startOfDay(dueAt) === DateUtil.todayStart();
  }

  /** 人类可读的截止日期标签 */
  static dueLabel(dueAt: number): string {
    if (dueAt <= 0) {
      return '';
    }
    const diffDays: number =
      Math.round((DateUtil.startOfDay(dueAt) - DateUtil.todayStart()) / DateUtil.DAY_MS);
    if (diffDays === 0) {
      return '今天';
    }
    if (diffDays === 1) {
      return '明天';
    }
    if (diffDays === 2) {
      return '后天';
    }
    if (diffDays === -1) {
      return '逾期 1 天';
    }
    if (diffDays < -1) {
      return `逾期 ${Math.abs(diffDays)} 天`;
    }
    const d: Date = new Date(dueAt);
    return `${d.getMonth() + 1}月${d.getDate()}日`;
  }
}
