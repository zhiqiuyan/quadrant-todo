# 象限待办 · HarmonyOS 版

一款**本地优先**的四象限任务管理应用，使用 ArkTS + ArkUI 声明式范式、Stage 模型开发。

灵感来自 [jailedxiu/quadrant-todo](https://github.com/jailedxiu/quadrant-todo)（网页版象限待办）。本仓库是原生鸿蒙实现：任务默认只存在本机数据库，不依赖任何账号体系；需要跨设备或与系统日历联动时，再按需开启对应能力。

- 应用包名：`com.quadrant.todo`
- 版本：**1.1.5**（版本记录见 [CHANGELOG.md](CHANGELOG.md)）
- 技术要求：HarmonyOS 7.0（API 26）及以上

## 功能一览

| 能力 | 说明 |
|---|---|
| 四象限看板 | 2×2 网格，按「重要 / 紧急」两维判定；收起时是胶囊 dock，输入时 dock 与填写栏融合成一个贴键盘的大胶囊 |
| 任务编辑 | 底部面板修改标题、象限、截止日、重要标记，改象限无需复制删除 |
| 完成与历史 | 勾选圈切换完成状态，「已完成」抽屉可恢复或删除 |
| 归类说明 | 内置四象限判定尺子，说明每格的处理策略 |
| 每日一言 | 顶栏按日期轮换名言，替代传统的标题区域 |
| 桌面卡片 | `4*4` 看板卡与 `6*4` 宽幅卡，格内直接列出任务，与主界面同源 |
| 多账号 | 账号仅作数据维度，任务按账号隔离，全程不出本机 |
| 华为账号（可选） | Account Kit 授权，仅用于云备份的存储归属 |
| 云备份（可选） | 云存储自动备份 + 本地 JSON 文件导出与导入 |
| 系统日历（可选） | Calendar Kit 把带截止日且未完成的任务写成全天事件，对账式同步 |
| 日历订阅（可选） | 生成 ICS 推送到 Git 仓库，iPhone / Google 日历可订阅同一份数据 |
| 字号 | 跟随系统字体大小（上限 1.75×），也可在应用内指定档位 |
| 沉浸光感 | 六档可选，只作用于底部 dock 及其融合后的大胶囊（渐变光晕 + 阴影）；主界面保持纯色 |
| 外观 | 跟随系统 / 浅色 / 深色，启动前应用以避免闪烁 |
| 用户协议 | 首次启动全屏展示，同意后进入，不同意直接退出 |
| 设置页 | 系统设置风格的单页分组卡片，「关于」默认折叠 |

## 数据与隐私

- 任务、账号、设置全部保存在本机（RDB + preferences），**后台上传为零**。
- 仅当你主动开启以下功能时才会联网：云备份（华为云存储）、日历订阅（Git 仓库）。
- 华为账号登录只获取 openid / 昵称 / 头像，用于云存储路径隔离。
- 卸载应用即清除全部本地数据；重要数据请用「导出到文件」留档。

## 桌面卡片

两种尺寸，均可在「长按桌面空白处 → 卡片 → 象限待办」添加：

| 卡片 | 尺寸 | 内容 |
|---|---|---|
| 四象限看板 | `4*4` | 2×2 四格，格内列出该象限的任务标题 |
| 四象限看板（大） | `6*4` | 四象限布局（每格条数可设）+ 总数 / 今日完成 / 每日一言 |

> **尺寸说明**：HarmonyOS 卡片尺寸是严格枚举，`form_config.json` 的 `supportDimensions` 只接受 `1*1 / 1*2 / 2*2 / 2*3 / 2*4 / 3*3 / 4*4 / 6*4`，不存在 `4*6`（填了会在 PreBuild 阶段报 `Schema validate failed`）。

刷新机制：`EntryFormAbility` 记录每个卡片实例的 formId，主界面任何写操作后由 `WidgetBridge.refreshAll()` 主动 `updateForm` 推送；另有 `updateDuration` 兜底刷新。

## 系统日历同步

设置 →「本机日历」开关 → 申请 `READ_CALENDAR` / `WRITE_CALENDAR` → 写入系统默认日历账户的全天事件。

设计要点是**对账式同步**，不做全量重建：

| 条件 | 动作 |
|---|---|
| 有截止日且未完成 | 进入目标事件集 |
| 新任务 | `addEvent` |
| 标题 / 象限 / 截止日 / 更新时间有变 | `updateEvent`（id 失效则重建） |
| 已完成、移除截止日、任务被删 | `deleteEvent` |

`preferences` 中保存 `taskId → eventId` 映射，因此每轮只做差异操作。事件描述带 `quad-todo:task=<id>` 标记，首次同步会扫描日历认领历史事件，避免重装后出现两套；只操作带该标记的事件，不会改动你手动添加的日程。关闭开关不会删除已写入的事件，需要清空请用「清除事件」。

## 日历订阅

设置 →「日历订阅」→ 填写仓库 owner / repo / token → 同步。应用把任务生成为 ICS（RFC 5545，全天 VEVENT，`REFRESH-INTERVAL:PT30M`）推送到仓库固定路径，订阅地址形如：

```
https://gitee.com/{owner}/{repo}/raw/master/quadrant-todo/cal-<pathId>.ics
```

iPhone「设置 → 日历 → 账户 → 添加订阅日历」、Google 日历「通过网址添加」均可使用。内容相同时跳过推送，避免无意义提交。

## 字号与无障碍

应用默认**跟随系统字体大小**：`AppScope/resources/base/profile/configuration.json` 声明 `fontSizeScale: followSystem`，上限 `fontSizeMaxScale: 1.75`。ArkUI 中 `fontSize` 的数值单位为 fp，配置到位后随「设置 → 显示和亮度 → 字体大小」自动缩放。

设置 → 通用 →「字体大小」提供 跟随系统 / 小 0.9× / 标准 1.0× / 大 1.15× / 特大 1.3×。

> **已知约束**：`ApplicationContext.setFontSizeScale` 一旦被调用，应用字体即不再跟随系统（官方行为）。因此实现上「跟随系统」档位绝不调用该接口；在应用内选了自定义档位后，切回「跟随系统」会立即对齐当前系统比例，但要完全恢复实时跟随需要重新打开一次应用。

## 新建模块：dock / 融合输入胶囊、背景与沉浸光感

**收起态 · 小胶囊 dock**：底部常驻一条胶囊形悬浮栏，宽度与看板卡片一致（`calc(100% - 24vp)`，左右各 12vp，与 `Board` 的 padding 对齐，不设最大宽度）。栏内是五个 **44vp 实心圆形大色块**：左侧唯一的「＋ 新建」按钮（主色实心圆，圆内图标 + 小字，展开后变「− 收起」），右侧四个象限键（1~4）——未选中用象限浅色底 + 同色数字，选中切到饱和象限色 + 白字 + 白色外环。点新建按钮展开 / 收起；点任意象限键即选中该象限并展开。四个象限格子只负责展示，不再各自带输入框。

**展开态 · 融合大胶囊**：唤起键盘输入时，dock 与填写栏不再是上下分离的两个卡片，而是**合并为同一个 30vp 圆角的大胶囊**（`MergedDock`）——同宽、同圆角、同背景、同阴影，中间无边界、无间隙、无遮罩。顶行仍是那五个圆形大色块（抽出为 `DockKeys`，两种形态完全一致），底行是贴键盘的输入框；象限键在输入过程中随时可切。视觉上就是小胶囊 dock 被纵向「拉高」，而不是叠了两层浮层。键盘收起或新建完成后，容器回到小胶囊 dock。

**四角等距几何**：圆形按键直径 44vp（半径 22vp），dock 四边内边距 8vp，于是 dock 高 `44 + 8×2 = 60vp`、圆角半径 `8 + 22 = 30vp`（恰好为高度一半，呈胶囊形）。此时四个边角的圆角弧圆心与两端圆形按键的圆心重合，弧线与圆形之间的间隙在左上 / 左下 / 右上 / 右下恒为 8vp，与四边边距一致；这些关系统一由 `DOCK_KEY_SIZE` / `DOCK_PADDING` / `DOCK_HEIGHT` / `DOCK_RADIUS` 四个常量表达。

**贴键盘零间隙**：融合胶囊底边距窗口底部就等于键盘高度。容器底部两个圆角由一层同色衬底（`height = DOCK_RADIUS = 30vp`）填平，既保留大胶囊的圆润外形，又不会在两角留下三角空隙；贴键盘时阴影收窄朝上。通过 `window.on('keyboardHeightChange')` 把键盘高度换算为 vp，键盘未弹起时容器回到底部 16vp。不再有 dock 上移、卡片上移两套定位，也不再需要 `onAreaChange` 实测高度算避让。

**避免三重避让叠加**：输入框与键盘之间的大片空白并非间距过大，而是位移叠加。ArkUI 默认 `KeyboardAvoidMode.OFFSET` 会在键盘弹起时把整个页面上移，页面又按 `keyboardHeight` 手动抬融合胶囊，两次位移叠加；根布局的导航条避让 `bottomInset` 再算一次。因此页面挂载时显式 `setKeyboardAvoidMode(KeyboardAvoidMode.NONE)` 关闭页面级避让，只保留手动定位；键盘期间把根布局 `padding.bottom` 从 `bottomInset` 置 0（键盘本身已占据底部）。展开后用 `focusControl.requestFocus` 主动聚焦输入框保证键盘弹起、回调有值，输入框另有 `defaultFocus(true)` 兜底。

**融合胶囊内部四行**（自上而下）：`DockKeys` 圆形按键行 → 当前象限 + 收起按钮 → 截止日 chips + 重要标记 → **标题输入 + 提交按钮（最底行）**。四边内边距 8vp，行间距 6/4/6vp，底内边距 6vp 就是输入框到键盘的全部距离，整卡约 154vp。没有元素间的边框或分割线，输入区、快捷选项与键盘连成一个视觉组；提交按钮落在右下角，单手拇指可直接够到。展开后用 `focusControl.requestFocus` 主动聚焦保证键盘弹起、回调有值，输入框另有 `defaultFocus(true)` 兜底；回车或「↑」即入库，象限由顶行 dock 决定，返回键优先收起，编辑已有任务仍走底部面板。

**背景与状态栏**：`EntryAbility` 开启全屏布局并将系统状态栏设为透明，应用根背景（浅色 `#F5F6F8` / 深色 `#14161A`）延伸到状态栏区域，主页面与状态栏始终同色；切换深浅色时自动跟随，无需维护第二套颜色。主界面不再叠加全屏氛围光晕。

**沉浸光感只作用于 dock / 融合大胶囊**：六档控制径向渐变光晕与投影强度。融合后整个大胶囊就是 dock 的放大形态，渐变铺满容器；主界面保持纯色。

| 档位 | dock / 融合胶囊光晕透明度 | 光域半径 | dock 阴影半径 |
|---|---|---|---|
| 关闭 | 0 | — | 14vp |
| 极薄 | 0.10 | 340vp | 17vp |
| 轻薄 | 0.14 | 310vp | 20vp |
| 标准（默认） | 0.18 | 280vp | 23vp |
| 浓郁 | 0.22 | 250vp | 26vp |
| 极致 | 0.26 | 220vp | 29vp |

实现说明：组件级 `systemMaterial` 只在弹窗类组件、Slider / Toggle / Select、Navigation 标题栏与底部悬浮 TabBar 上生效，普通容器不生效；dock 与融合胶囊都是 `Stack` + `Column`，因此用自绘渐变与阴影表达档位。`uiMaterial` 仅用于设备算力探测与设置页能力展示；`module.json5` 保留 `ohos.arkui.UIMaterial.state = enable`，对 Toggle 等受支持控件仍有效。

## 华为账号与云备份

设置面板的「华为账号」「云备份」两个区块：华为账号走 Account Kit 授权，云备份走云基础服务的云存储。

**运行前提（一次性，AGC 约 10 分钟）**：

1. 登录 [AppGallery Connect](https://developer.huawei.com/consumer/cn/service/josp/agc/index.html) → 创建应用（包名需与 `AppScope/app.json5` 的 `bundleName` 一致）；
2. 开通「账号服务」（Account Kit）；开通「云基础服务」→ 云存储 → 创建默认实例；
3. 把 AGC 分配的 **Client ID** 填进 `entry/src/main/module.json5` 的 `metadata.client_id`（当前为空串占位）；
4. 使用带 Profile 的有效签名（DevEco 自动签名即可）。

未配置时点击登录会弹出带错误码与排查清单的对话框，不影响其它功能。

| 错误码 | 含义 | 处理 |
|---|---|---|
| 401 | 授权页拿不到界面上下文 | 实现中已修正（`AuthenticationController` 需传 `UIAbilityContext`） |
| 1001502003 | `Invalid clientId or profile` | 安装包签名不是 AGC 签发的 Profile，或 `client_id` 未配置 |
| 1001500001 | 应用信息校验失败 | AGC 侧包名 / client_id / 证书指纹不一致 |
| 1001500003 | 设备未登录华为账号 | 先在系统设置登录华为账号 |
| 1001502014 | 用户取消授权 | 重新点登录 |

> **关键结论**：命令行用 OpenHarmony 测试证书签的包，证书指纹不在 AGC 登记表里，Account Kit 一律拒绝（1001502003）。能登录的唯一路径是 DevEco Studio 登录华为账号 → Signing Configs 勾选 **Automatically generate signature** → 用 DevEco 直接 Run。

**不依赖账号的备份**：设置 → 云备份 →「导出到文件 / 从文件恢复」，走系统文件选择器把 JSON 存到本地或网盘。

## 工程结构

```
quadrant-todo-harmony/
├── AppScope/
│   ├── app.json5                                  # 应用配置（含 configuration 指向字体配置）
│   └── resources/base/profile/configuration.json  # 字号跟随系统声明
├── entry/src/main/
│   ├── module.json5                               # Ability / Form 扩展 / 权限 / 沉浸光感 metadata
│   ├── resources/base/profile/
│   │   ├── main_pages.json                        # 页面路由
│   │   └── form_config.json                       # 卡片声明（4*4、6*4）
│   └── ets/
│       ├── entryability/EntryAbility.ets           # 入口：启动前应用外观与字号
│       ├── entryformability/EntryFormAbility.ets   # 卡片提供者
│       ├── pages/Index.ets                         # 主界面 + 圆形 dock/融合输入大胶囊 + 设置 + 协议 + 抽屉面板
│       ├── widget/WidgetData.ets                   # 卡片数据构建（与主界面同仓储）
│       ├── widget/pages/Widget4x4.ets              # 4*4 看板卡片
│       ├── widget/pages/Widget6x4.ets              # 6*4 宽幅卡片
│       ├── model/TaskItem.ets                      # 任务模型与象限元数据
│       ├── model/Account.ets                       # 账号模型与头像配色
│       ├── model/AppSettings.ets                   # 设置模型与选项元数据
│       ├── model/Quote.ets                         # 每日一言语料
│       ├── data/TaskRepository.ets                 # relationalStore 持久化（按账号维度）
│       ├── data/AccountStore.ets                   # 账号 CRUD 与切换
│       ├── data/SettingsStore.ets                  # 设置读写
│       ├── data/PrefStore.ets                      # preferences 封装
│       ├── data/FormStore.ets                      # 卡片 formId 登记
│       ├── data/WidgetBridge.ets                   # 主界面 → 卡片主动刷新
│       ├── data/HuaweiAuthService.ets              # Account Kit 授权
│       ├── data/BackupService.ets                  # 云备份 + 本地文件导入导出
│       ├── data/LocalCalService.ets                # 系统日历对账式同步
│       ├── data/CalSyncService.ets                 # ICS 生成与仓库推送
│       ├── data/FontScaleService.ets               # 字号档位与系统比例读取
│       ├── data/MaterialService.ets                # 沉浸光感档位、渐变强度与设备能力查询
│       ├── data/HttpUtil.ets                       # 轻量 HTTP 封装
│       └── common/DateUtil.ets                     # 日期工具（逾期 / 今天 / 明天）
├── tools/gen_icon.py                               # 图标生成脚本（纯标准库）
├── tools/sign_hap.sh                               # 命令行签名
└── build.sh                                        # 命令行构建
```

## 构建运行

### 方式一：DevEco Studio（推荐，可装真机）

1. 用 DevEco Studio 打开本目录（26.0.0 及以上，需 API 26 SDK）；
2. 等待 hvigor 同步完成；
3. 连接真机或启动模拟器，Run；
4. 真机运行需要签名：`File → Project Structure → Signing Configs → Automatically generate signature`。

### 方式二：命令行构建

```bash
./build.sh            # debug 构建（未签名）
./build.sh release    # release 构建（未签名）
```

脚本自动指向 DevEco 自带的 SDK / Node / JBR，产物位于
`entry/build/default/outputs/default/entry-default-unsigned.hap`；可用 `DEVECO_HOME` 覆盖安装位置。

### 方式三：命令行打包并签名

```bash
./build.sh
./tools/sign_hap.sh   # 用 SDK 内置测试证书链签成 dist/quadrant-todo-signed.hap
```

签名产物可用 `hap-sign-tool verify-app` 自检（脚本已内置校验）。

**签名兼容边界（重要）**：

| 签名方式 | 证书来源 | 可安装范围 |
|---|---|---|
| 本项目脚本 | SDK 自带 `OpenHarmony.p12` 测试根 | 信任 OpenHarmony 测试根的设备 / 部分模拟器镜像 |
| DevEco 自动签名 | 华为账号签发，绑定设备 UDID | **华为商用真机**（唯一可行路径） |

即：`dist/quadrant-todo-signed.hap` 证明打包链路完整、可校验，但通常**装不到华为商用手机**。装真机请在 DevEco 里勾选自动签名后 Run。

已在 DevEco Studio 26.0.0（SDK API 26 / hvigor 6.26.9 / JBR 25）下编译通过。

## 设计说明

- **配色**：四格底色 `q1~q4`、强调蓝 `accent`、危险红 `danger`，浅色 / 深色两套资源，通过 `$r('app.color.*')` 引用。
- **交互**：卡片单击进编辑、长按删确认；新建统一走底部胶囊 dock，键盘弹起时 dock 与填写栏融合为一个贴键盘的大胶囊（顶行仍是五个圆形大色块按键）；编辑、归类说明、已完成均为底部抽屉。
- **数据**：本地 RDB 表 `task`，`account_id` 做账号隔离，`completed` 标记完成（不物理删除，便于统计「今日完成」）。
- **卡片与界面同源**：`WidgetData.build()` 与主界面走同一个 `TaskRepository`，卡片只读不写，避免两套逻辑漂移。
- **设置即时生效**：外观走 `setColorMode`、字号走 `setFontSizeScale`，都在 `loadContent` 之前应用，避免启动闪烁与字号跳变。

## 已知限制

- 日历订阅依赖第三方仓库可用性，仓库需可公开读取 raw 文件。
- `getCalendar()` 若无默认本地日历账户会抛错，届时以提示呈现而非静默失败。
- 华为账号登录受签名约束，见上文「签名兼容边界」。
- 大字号（1.75×）下的极端排版（四象限格内多条任务）尚未逐档真机验证。
- 五个圆形按键的触控热区与等距圆角观感、融合大胶囊的高宽比与底部衬底填角观感、dock 六档光感、`KeyboardAvoidMode.NONE` 下不同输入法的 `keyboardHeightChange` 回调高度（是否含候选栏 / 导航条）、融合胶囊与键盘的零间隙贴合均尚未在真机验证。

## 后续路线（可选）

1. 卡片内直接勾选完成（`postCardAction` + `onFormEvent`）。
2. 截止日系统提醒（reminderAgentManager）。
3. 跨象限拖拽（`onDragStart` / `onDrop`）。
4. 账号级云同步（华为云 DB 或自建服务）。

## 许可

界面与数据层为 ArkTS 实现，参考项目遵循其原始开源许可。使用前请阅读应用内「用户协议与免责声明」。
