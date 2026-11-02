# 象限待办 · HarmonyOS 版

参考 [jailedxiu/quadrant-todo](https://github.com/jailedxiu/quadrant-todo)（网页版象限待办，联动微软 To Do）实现的 **HarmonyOS 原生应用**，使用 ArkTS + ArkUI 声明式范式、Stage 模型开发。

## 功能对照

| 能力 | 网页参考版 | 本鸿蒙版 |
|---|---|---|
| 四象限看板（重要紧急 / 重要不紧急 / 紧急不重要 / 不重要不紧急） | ✅ | ✅ 2×2 网格 |
| 快速添加任务（每格独立输入框） | ✅ | ✅ |
| 完成 / 取消完成 | ✅ | ✅ 点勾选圈 |
| 编辑标题、截止日期、重要标记 | ✅ contenteditable | ✅ 底部编辑面板 |
| 跨象限移动（复制 + 删除） | ✅（Graph 限制） | ✅ 编辑面板直接改象限，无副作用 |
| 逾期 / 今天 / 明天等日期标签 | ✅ | ✅ 且本地化更快 |
| 长按删除 + 二次确认 | — | ✅ |
| 已完成历史 / 恢复 / 删除 | — | ✅ 底部抽屉 |
| 归类尺子（判定说明） | ✅ | ✅ 底部抽屉 |
| **桌面卡片** | — | ✅ **4\*4 看板卡 + 6\*4 看板卡（任务按象限格内展示）** |
| **账号管理** | — | ✅ 多账号，任务按账号隔离 |
| **华为账号登录** | — | ✅ Account Kit 授权（1.4.0 修复 401） |
| **云备份** | — | ✅ 云存储备份 + **本地文件导出/导入** |
| **设置项** | — | ✅ 排序 / 外观 / 计数 / 卡片条数 / 自动备份 |
| **微软 To Do 同步** | ✅ MSAL | ✅ 内置 OAuth 2.0 PKCE + Graph REST，无需 MSAL |
| 数据存储 | 微软 To Do（Graph API + OAuth） | 本地 RDB 为主，可选云同步 |
| 深色模式 | prefers-color-scheme | ✅ resources/dark + 应用内三档切换 |
| 适配设备 | 浏览器 | phone / tablet / 2in1 |

## 微软 To Do 同步（1.2.0 新增）

设置 → 「微软 To Do」→ 填 Client ID → 连接微软账号，登录在应用内 Web 完成（OAuth 2.0 授权码 + PKCE，S256），token 按本地账号隔离存储、临期自动刷新。

**准备工作（一次性，约 5 分钟）**：

1. 打开 [Azure 门户 - 应用注册](https://portal.azure.com/#blade/Microsoft_AAD_RegisteredApps/ApplicationsListBlade) → 新注册；
2. 受支持的账户类型选「个人 Microsoft 账户」（或同时含工作/学校）；
3. 平台选「移动和桌面应用程序」，回调 URI 填：`https://login.microsoftonline.com/common/oauth2/nativeclient`；
4. 注册后复制「应用程序（客户端）ID」，填进应用设置即可。

**同步规则**：

- 四个象限对应微软 To Do 的四个同名清单（重要紧急 / 重要不紧急 / 紧急不重要 / 不重要不紧急），云端不存在则自动创建；
- 每轮顺序：远端删除（墓碑队列）→ 推送本地改动 → 拉取远端变更；
- 冲突按「最后修改时间胜出」；象限变更 = 旧清单删 + 新清单建（To Do 无跨清单移动 API）；
- 自动同步默认开：改动后自动推送/拉取，也可在设置里手动「立即同步」。

**已知限制**：token 存于应用 preferences（明文，卸载即清）；更新远端任务用「删+建」实现（PATCH 方法要求较新系统版本）；单次拉取上限 200 条。

## 桌面卡片

两种尺寸，均可在「长按桌面空白处 → 卡片 → 象限待办」添加：

| 卡片 | 尺寸 | 内容 | 适用 |
|---|---|---|---|
| 四象限看板 | `4*4` | 2×2 四格：格内直接列出该象限的任务标题（最多 3 条） | phone / tablet / 2in1 |
| 四象限看板（大） | `6*4` | 同样的四象限布局（每格条数随设置）+ 账号/总数/今日完成一行 | phone / tablet / 2in1 |

> **尺寸说明**：HarmonyOS 的卡片尺寸是严格枚举，`form_config.json` 的 `supportDimensions` 只接受 `1*1 / 1*2 / 2*2 / 2*3 / 2*4 / 3*3 / 4*4 / 6*4`，**不存在 `4*6`**（填 `4*6` 会在 PreBuild 阶段报 `Schema validate failed`）。因此大卡片使用平台定义的 `6*4` 即「6 列 × 4 行」宽幅卡片；若你的目标是竖长卡片，平台当前没有对应档位，只能横向扩展。

刷新机制：`EntryFormAbility` 记录每个卡片实例的 formId（存 preferences），主界面任何写操作后由 `WidgetBridge.refreshAll()` 主动 `updateForm` 推送；另有 `updateDuration: 2`（约 1 小时）兜底刷新。

## 账号管理

- 账号存在本机 `preferences`（`accounts_json` + `active_account_id`），**不联网、不上传**。
- 任务表新增 `account_id` 列，所有查询按当前账号过滤，切换账号即切换整份清单。
- 老版本数据库自动迁移：`ALTER TABLE task ADD COLUMN account_id INTEGER NOT NULL DEFAULT 1`，旧数据归入默认账号「我」。
- 支持新建（含头像配色）、改名、删除（连带清空该账号任务）；最后一个账号不允许删除。

## 设置项（全部真实生效）

| 设置 | 取值范围 | 作用点 |
|---|---|---|
| 新建任务默认象限 | 四象限之一 | 打开「新建任务」时的初值 |
| 任务排序 | 最新创建 / 截止优先 / 重要优先 | 每格列表与卡片清单的排序 |
| 外观 | 跟随系统 / 浅色 / 深色 | `ApplicationContext.setColorMode()`，启动前先应用避免闪烁 |
| 顶栏显示今日完成 | 开 / 关 | 顶栏副标题 |
| 大卡片显示条数 | 2 / 3 / 5 | 6\*4 卡片每格的任务行数 |
| 自动备份 | 开 / 关 | 改动后自动上传云备份 |
| 数据 | 清理已完成 / 清空本账号 | 数据库删除 |

## 华为账号与云备份（1.3.0 新增）

设置面板新增「华为账号」与「云备份」两个区块：华为账号登录用 Account Kit 授权（获取 openid / 昵称 / 头像），云备份用云基础服务的云存储。

**运行前提（一次性，需在 AGC 完成约 10 分钟）**：

1. 登录 [AppGallery Connect](https://developer.huawei.com/consumer/cn/service/josp/agc/index.html) → 我的账号 → 创建应用（包名需与 `AppScope/app.json5` 的 `bundleName` 一致）；
2. 开通「账号服务」（Account Kit）；开通「云基础服务」→ 云存储 → 创建默认实例；
3. 把 AGC 分配的 **Client ID** 填进 `entry/src/main/module.json5` 顶部的 `metadata` → `client_id`（当前为空串占位）；
4. 使用带 Profile 的有效签名（DevEco 自动签名即可）。

未配置时点击登录会弹出带错误码与排查清单的对话框，不影响应用其它功能。

**常见错误码**：

| 错误码 | 含义 | 处理 |
| --- | --- | --- |
| 401 | 参数校验失败：授权页面拿不到界面上下文 | 1.4.0 已修（`AuthenticationController` 必须传 `UIAbilityContext`） |
| 1001502003 | `Invalid clientId or profile` | 安装包签名不是 AGC 签发的 Profile（本地测试证书过不了校验），或 `client_id` 未配置 |
| 1001500001 | 应用信息校验失败 | AGC 应用包名 / `client_id` / 签名证书指纹三者不一致 |
| 1001500003 | 设备未登录华为账号 | 先在系统「设置 → 华为账号」登录 |
| 1001502014 | 用户取消授权 | 重新点登录即可 |

> **关键结论（1.4.1 实测 1001502003）**：命令行用 OpenHarmony 测试证书签的包，签名指纹不在 AGC 登记表里，Account Kit 一律拒绝。
> 能登录的唯一路径：DevEco Studio 登录华为账号 → File → Project Structure → Signing Configs 勾选 **Automatically generate signature** → 用 DevEco 直接 Run 安装；同时 AGC 创建应用（包名 `com.quadrant.todo`）、开通「账号服务」，把 AGC 的 Client ID 填进 `module.json5` 的 `metadata.client_id`。

**不依赖账号的备份**：设置 → 云备份 → 「导出到文件 / 从文件恢复」，走系统文件选择器把 JSON 备份存到本地或网盘，未登录也能用。

**备份机制**：

- 内容：全部账号的任务（标题/象限/截止/重要/完成态）序列化为 JSON；
- 路径：云存储 `quadrant-todo/hw-<openID前缀>/backup-latest.json`，按华为账号隔离，多设备同账号共享同一份；
- 自动备份：默认开启，改动后触发（内置 60s 防抖，避免频繁上传）；失败静默，不打扰；
- 恢复：「从云端恢复」下载最近备份，任务并入**当前本地账号**，同象限同标题去重；
- 注意：云存储依赖华为账号鉴权，未登录或 AGC 未开服务时不可用。

## 工程结构

```
quadrant-todo-harmony/
├── AppScope/                        # 应用级配置与图标
├── entry/src/main/
│   ├── module.json5                 # 模块配置（Ability / Form 扩展 / 页面 / 设备类型）
│   ├── resources/base/profile/
│   │   ├── main_pages.json          # 页面路由
│   │   └── form_config.json         # 卡片声明（4*4、6*4）
│   └── ets/
│       ├── entryability/EntryAbility.ets        # 应用入口（启动前应用外观设置）
│       ├── entryformability/EntryFormAbility.ets# 卡片提供者（onAddForm / onUpdateForm）
│       ├── pages/Index.ets                      # 主界面（看板 / 编辑 / 账号 / 设置 / 尺子 / 已完成）
│       ├── widget/WidgetData.ets                # 卡片数据构建（与主界面共用仓储）
│       ├── widget/pages/Widget4x4.ets           # 4*4 看板卡片
│       ├── widget/pages/Widget6x4.ets           # 6*4 清单卡片
│       ├── model/TaskItem.ets                   # 任务模型与四象限元数据
│       ├── model/Account.ets                    # 账号模型与头像配色
│       ├── model/AppSettings.ets                # 设置模型与选项元数据
│       ├── data/TaskRepository.ets              # relationalStore 持久化（按账号维度）
│       ├── data/AccountStore.ets                # 账号 CRUD 与切换
│       ├── data/SettingsStore.ets               # 设置读写
│       ├── data/PrefStore.ets                   # preferences 封装
│       ├── data/FormStore.ets                   # 卡片 formId 登记
│       ├── data/WidgetBridge.ets                # 主界面 → 卡片的主动刷新
│       └── common/DateUtil.ets                  # 日期工具（逾期/今天/明天判断）
├── preview/quadrant-todo-preview.html           # 网页交互原型（含账号、设置、卡片预览）
└── tools/gen_icon.py                            # 图标生成脚本（纯标准库，可重复执行）
```

## 构建运行

### 方式一：DevEco Studio（推荐，可装真机）

1. 用 **DevEco Studio** 打开本目录（建议 6.0 及以上；首次打开若提示 Sync / 迁移工程模型，按提示确认即可）。
2. 等待 hvigor 同步完成（会自动下载依赖）。
3. 启动模拟器或连接真机，点击 Run。
4. 真机运行需要签名：`File → Project Structure → Signing Configs → Automatically generate signature`，登录华为账号一键生成调试证书。

### 方式二：命令行构建（无需打开 IDE）

```bash
./build.sh          # debug 构建
./build.sh release  # release 构建
```

脚本会自动指向 DevEco 自带的 SDK / Node / JBR，产物位于
`entry/build/default/outputs/default/entry-default-unsigned.hap`。
通过 `DEVECO_HOME` 环境变量可覆盖 DevEco 安装位置。

### 方式三：命令行打包并签名

```bash
./build.sh              # 先编译出 unsigned HAP
./tools/sign_hap.sh     # 用 SDK 内置测试证书链签成 dist/quadrant-todo-signed.hap
```

签名产物可用 `hap-sign-tool verify-app` 自检（脚本已内置该校验步骤）。

**签名的兼容边界（重要）**：

| 签名方式 | 证书来源 | 可安装范围 |
|---|---|---|
| 本脚本（已产出） | SDK 自带 `OpenHarmony.p12` 测试根 | 信任 OpenHarmony 测试根的设备 / 部分模拟器镜像 |
| DevEco 自动签名 | 华为账号签发，绑定设备 UDID | **华为商用真机**（唯一可行路径，需登录账号后一键生成） |

即：`dist/quadrant-todo-signed.hap` 证明打包链路完整、可校验，但**装不到华为商用手机上**。
装真机请在 DevEco 里 `File → Project Structure → Signing Configs` 勾选自动签名后 Run。

技术要求：`compatibleSdkVersion = 6.0.0(20)`，即 HarmonyOS 6.0（API 20）及以上设备。未显式指定 `compileSdkVersion`，编译时使用 IDE 配套 SDK。**已在 DevEco Studio 26.0.0（SDK API 26 / hvigor 6.26.9 / JBR 25）下实测编译通过，ArkTS 告警为 0。**

## 设计说明

- **配色**与参考版一致：四格底色 `q1~q4`、强调蓝 `accent`、危险红 `danger`，浅色/深色两套资源，通过 `$r('app.color.*')` 引用，系统切换深色模式时自动生效。
- **交互**：卡片单击进编辑、长按删确认；四格输入框回车或「＋」即快速入库；「归类尺子」与「编辑」均为底部抽屉，符合移动端习惯。
- **数据**：本地 RDB 表 `task`，`account_id` 做账号隔离，`completed` 标记完成（不物理删除，可查「今日完成」统计），「清理已完成」提供显式清理入口。
- **卡片与界面同源**：`WidgetData.build()` 与主界面走同一个 `TaskRepository`，卡片只做展示，不做写入，避免两套逻辑漂移。
- **图标**：`tools/gen_icon.py` 生成 1024px 圆角四格图标，改色板后重跑脚本即可换肤。

## 后续路线（可选增量）

1. **卡片内交互**：`postCardAction` 的 `message` 动作 + `onFormEvent` 支持在卡片上直接勾选完成任务。
2. **提醒**：reminderAgentManager 对 `dueAt` 设置系统提醒。
3. **跨象限拖拽**：用 `onDragStart` / `onDrop` 替换当前的编辑面板改象限。
4. **凭据加密存储**：把微软 token 迁到 `@ohos.security.asset`（当前为 preferences 明文）。
5. **账号云同步**：接华为云 DB 或自建服务，实现多设备同账号同步（当前账号体系是纯本地）。
