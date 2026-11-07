# 象限待办 · HarmonyOS 版

一款**本地优先**的四象限任务管理应用，使用 ArkTS + ArkUI 声明式范式、Stage 模型开发。

灵感来自 [jailedxiu/quadrant-todo](https://github.com/jailedxiu/quadrant-todo)（网页版象限待办）。本仓库是原生鸿蒙实现：任务默认只存在本机数据库，不依赖任何账号体系；需要跨设备或与系统日历联动时，再按需开启对应能力。

- 应用包名：`com.quadrant.todo`
- 版本：**1.1.5**
- 技术要求：HarmonyOS 6.0（API 20）及以上

## 功能一览

| 能力 | 说明 |
|---|---|
| 四象限看板 | 2×2 网格，按「重要 / 紧急」两维判定，每格独立快速输入框 |
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
│   ├── module.json5                               # Ability / Form 扩展 / 权限
│   ├── resources/base/profile/
│   │   ├── main_pages.json                        # 页面路由
│   │   └── form_config.json                       # 卡片声明（4*4、6*4）
│   └── ets/
│       ├── entryability/EntryAbility.ets           # 入口：启动前应用外观与字号
│       ├── entryformability/EntryFormAbility.ets   # 卡片提供者
│       ├── pages/Index.ets                         # 主界面 + 设置 + 协议 + 各抽屉面板
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
│       ├── data/HttpUtil.ets                       # 轻量 HTTP 封装
│       └── common/DateUtil.ets                     # 日期工具（逾期 / 今天 / 明天）
├── tools/gen_icon.py                               # 图标生成脚本（纯标准库）
├── tools/sign_hap.sh                               # 命令行签名
└── build.sh                                        # 命令行构建
```

## 构建运行

### 方式一：DevEco Studio（推荐，可装真机）

1. 用 DevEco Studio 打开本目录（6.0 及以上）；
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
- **交互**：卡片单击进编辑、长按删确认；四格输入框回车或「＋」快速入库；编辑、归类说明、已完成均为底部抽屉。
- **数据**：本地 RDB 表 `task`，`account_id` 做账号隔离，`completed` 标记完成（不物理删除，便于统计「今日完成」）。
- **卡片与界面同源**：`WidgetData.build()` 与主界面走同一个 `TaskRepository`，卡片只读不写，避免两套逻辑漂移。
- **设置即时生效**：外观走 `setColorMode`、字号走 `setFontSizeScale`，都在 `loadContent` 之前应用，避免启动闪烁与字号跳变。

## 已知限制

- 日历订阅依赖第三方仓库可用性，仓库需可公开读取 raw 文件。
- `getCalendar()` 若无默认本地日历账户会抛错，届时以提示呈现而非静默失败。
- 华为账号登录受签名约束，见上文「签名兼容边界」。
- 大字号（1.75×）下的极端排版（四象限格内多条任务）尚未逐档真机验证。

## 后续路线（可选）

1. 卡片内直接勾选完成（`postCardAction` + `onFormEvent`）。
2. 截止日系统提醒（reminderAgentManager）。
3. 跨象限拖拽（`onDragStart` / `onDrop`）。
4. 账号级云同步（华为云 DB 或自建服务）。

## 许可

界面与数据层为 ArkTS 实现，参考项目遵循其原始开源许可。使用前请阅读应用内「用户协议与免责声明」。
