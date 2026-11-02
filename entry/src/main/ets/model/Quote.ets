/** 每日一言条目 */
export interface QuoteItem {
  text: string;
  author: string;
}

/** 名言库：主界面顶栏与 6*4 桌面卡片共用，按当天日期轮换 */
export const QUOTES: QuoteItem[] = [
  { text: '千里之行，始于足下', author: '老子' },
  { text: '不积跬步，无以至千里', author: '荀子' },
  { text: '学而不思则罔，思而不学则殆', author: '孔子' },
  { text: '逝者如斯夫，不舍昼夜', author: '孔子' },
  { text: '三人行，必有我师焉', author: '孔子' },
  { text: '天行健，君子以自强不息', author: '《周易》' },
  { text: '业精于勤，荒于嬉', author: '韩愈' },
  { text: '明日复明日，明日何其多', author: '钱福' },
  { text: '少壮不努力，老大徒伤悲', author: '《长歌行》' },
  { text: '宝剑锋从磨砺出，梅花香自苦寒来', author: '《警世贤文》' },
  { text: '一寸光阴一寸金，寸金难买寸光阴', author: '《增广贤文》' },
  { text: '纸上得来终觉浅，绝知此事要躬行', author: '陆游' },
  { text: '问渠那得清如许，为有源头活水来', author: '朱熹' },
  { text: '山重水复疑无路，柳暗花明又一村', author: '陆游' },
  { text: '长风破浪会有时，直挂云帆济沧海', author: '李白' },
  { text: '世上无难事，只怕有心人', author: '谚语' }
];

/** 按当天日期取一条（每天固定一条，自然轮换） */
export function dailyQuote(): QuoteItem {
  const now: Date = new Date();
  const start: Date = new Date(now.getFullYear(), 0, 1);
  const day: number = Math.floor((now.getTime() - start.getTime()) / 86400000);
  return QUOTES[day % QUOTES.length];
}
