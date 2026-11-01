# 四象限待办 · HarmonyOS 版

参考 [jailedxiu/quadrant-todo](https://github.com/jailedxiu/quadrant-todo)（网页版四象限待办，联动微软 To Do）实现的 **HarmonyOS 原生应用**，使用 ArkTS + ArkUI 声明式范式、Stage 模型开发。

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
| 数据存储 | 微软 To Do（Graph API + OAuth） | 本地 RDB（relationalStore），开箱即用 |
| 深色模式 | prefers-color-scheme | ✅ resources/dark 自动适配 |
| 适配设备 | 浏览器 | phone / tablet / 2in1 |

**关于微软 To Do 同步**：参考版的核心依赖是 Microsoft Graph OAuth（MSAL + Azure 应用注册）。鸿蒙端没有 MSAL SDK，需要自行实现 PKCE 授权 + WebView 登录 + Graph REST 调用，且必须先在 Azure 注册应用并实名验证。为保证当前版本开箱可用，本版先做**本地持久化**，Graph 同步作为独立增量（见文末路线）。

## 工程结构

```
quadrant-todo-harmony/
├── AppScope/                      # 应用级配置与图标
├── entry/src/main/
│   ├── module.json5               # 模块配置（EntryAbility、页面、设备类型）
│   └── ets/
│       ├── entryability/EntryAbility.ets   # 应用入口
│       ├── pages/Index.ets                 # 主界面（看板 + 编辑面板 + 归类尺子）
│       ├── model/TaskItem.ets              # 数据模型与四象限元数据
│       ├── data/TaskRepository.ets         # relationalStore 持久化（单例）
│       └── common/DateUtil.ets             # 日期工具（逾期/今天/明天判断）
├── preview/quadrant-todo-preview.html      # 网页交互原型（预览用，非交付主体）
└── tools/gen_icon.py                       # 图标生成脚本（纯标准库，可重复执行）
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
- **数据**：本地 RDB 表 `task`，`completed` 标记完成（不物理删除，可查「今日完成」统计），「清理已完成」提供显式清理入口。
- **图标**：`tools/gen_icon.py` 生成 1024px 圆角四格图标，改色板后重跑脚本即可换肤。

## 后续路线（可选增量）

1. **微软 To Do 同步**：`@ohos.net.http` + Web 组件实现 OAuth 2.0 PKCE；四个象限映射为四个 Graph 列表；写操作走乐观更新。需要 Azure 应用注册（SPA 重定向改为 `msauth://` 回调）。
2. **桌面小组件**：Form 卡片展示「重要紧急」剩余项。
3. **提醒**：reminderAgentManager 对 `dueAt` 设置系统提醒。
4. **跨象限拖拽**：用 `onDragStart` / `onDrop` 替换当前的编辑面板改象限。
