# dsh-go root 增强补丁集

给 [dsh-go](https://github.com/ccch1mneyyy/dsh-Go) 加一套**真 root 能力**的补丁仓库：不改上游代码风格，不提交 PR（上游明确不接受外部 PR），只以补丁 + 构建脚本的形式，把"手机容器里能用真 root 干活"这件事做到可用、可复现。

> 基线：upstream `v1.0.15` · 补丁量：19 个 · 目标 ABI：arm64-v8a

---

## 这个仓库解决什么问题

dsh-go 本体用 **PRoot** 在 Android 上跑 Ubuntu。PRoot 是"假 root"：`id` 显示 0，但没有任何真实权限，而且它用 **ptrace 劫持每个子进程**、伪造 `/proc`。这带来三个实际痛点：

| 痛点 | 现象 |
|---|---|
| 看不到系统分区 | `/product`、`/vendor`、`/my_product` 等全部不存在 |
| 写不了手机数据 | 只能看到 App 自己的沙箱目录 |
| 动态调试做不了 | frida 报 `ptrace seize: Operation not supported`、`Unsupported Android linker`；frida-server 一 attach 就 SIGABRT |

根因不是权限，是**进程在 PRoot 里**：任何子进程 `TracerPid` 都指向 `libproot.so`，嵌套 ptrace 必然失败；它读到的 `/proc/maps` 也是伪造的。

本补丁集做两件事：**让 PRoot 本身以真 root 跑**（解锁文件系统），**再给一个绕开 PRoot 的执行通道**（解锁 ptrace / 命名空间）。

---

## 功能

### 1. root 模式（PRoot 以真 uid 0 运行）

通过 KernelSU / Magisk 的 `su` 启动 proot，使 proot 自身 `uid=0`、SELinux 域为 `u:r:ksu:s0`。

- 入口：**设置 → 诊断 → 开发者选项 → root 模式**（默认关，需 su 授权）
- 生效时机：下一次启动引擎
- 启动日志出现 `root mode: launching proot via su` 即生效

### 2. 多分区可写挂载

root 模式下自动把手机分区 bind 进容器（**只绑真实存在的**，缺的自动跳过）：

```
/data /product /system_ext /vendor /odm /vendor_dlkm /system_dlkm
/my_product /my_bigball /my_heytap /my_region /my_carrier
/my_company /my_stock /my_engineering /my_manifest /my_preload
/mnt/vendor /mnt/opex /metadata /config /linkerconfig /data_mirror
```

> 注意：`/product`、`/vendor`、`/my_*` 等在真机上是 **erofs 只读**，绑进来可以读、改不了系统文件；真正可写的是 `/data`、`/metadata`、`/config`、`/linkerconfig`。

### 3. root-exec 通道（`dsh-root`）—— 绕开 PRoot

这是**解决 ptrace 限制的关键**：由 **App 进程**（不在 PRoot 里）执行 `su -c`，子进程 `TracerPid` 为 **0**，处于真实的 Android 挂载命名空间。

- App 侧：私有抽象 socket + token，暴露一个 `root_exec` 工具（`rootexec/RootExec.kt`）
- 容器侧：`/usr/local/bin/dsh-root`（Node 客户端，读 `/var/lib/dsh-app/root/bridge.json`）

```bash
dsh-root 'id'                              # uid=0, TracerPid: 0
dsh-root --bg 'setsid /data/local/tmp/frida-server -l 127.0.0.1:27042 &'
dsh-root 'ps -o PID,TracerPid -p <pid>'    # 验证 TracerPid=0
```

### 4. rootfs 属主自愈（修复"解压时出错"）

root 模式会在 App 的运行时目录写出 **root 属主**文件；之后 App（普通 uid）升级/重置运行时会被 `EACCES` 拒绝，界面误报成"解压时出错"。三层兜底：

1. `deleteRecursivelySafely()` 删不掉时回落 `su rm -rf`
2. root 模式停止时把 `/root`、`/tmp`、`var/lib/dsh-app` **chown 回 App uid**
3. 进入 root 模式写 `runtime/.root-dirty` 标记；下次启动若发现标记 → 先 reclaim 再清标记（**崩溃后自愈**）

### 5. 构建与签名

- `applicationId` 改为 `io.github.ccch1mneyyy.dsh_app.dev` → **与官方版并存**，不丢数据
- 固定 keystore（同一签名）→ 后续版本可覆盖升级，无需卸载
- CI 复用**官方 release APK 里的 runtime**（`assets/runtime` + `libproot*.so`），跳过 `runtime/build-runtime.sh`，构建从数小时降到约 8 分钟

---

## 环境要求

- Android arm64-v8a，Android 8.0+（targetSdk 28）
- **root 模式需要 KernelSU 或 Magisk**（检测 `/system/bin/su` 等候选路径）
- 构建：Flutter 3.47.7、JDK 17、Gradle 9.3.1、Android SDK 34–36

---

## 构建

### GitHub Actions（推荐）

```bash
gh workflow run build-apk.yml -r <branch> -f flavor=arm64
```

需要的 Secrets：

| Secret | 说明 |
|---|---|
| `DSH_KEYSTORE_BASE64` | keystore 文件 base64 |
| `DSH_KEYSTORE_PASSWORD` | store password |
| `DSH_KEY_PASSWORD` | key password |
| `DSH_KEY_ALIAS` | key alias |

产物：`dsh-go-apk` artifact（`app-arm64-release.apk`）。

### 本地

```bash
# 1. 取上游源码（指定 tag）
git clone --depth 1 --branch v1.0.15 https://github.com/ccch1mneyyy/dsh-Go.git
cd dsh-Go

# 2. 应用补丁
git am /path/to/patches/*.patch

# 3. 复用官方 runtime（跳过 runtime/build-runtime.sh）
curl -fL -o /tmp/official.apk \
  https://github.com/ccch1mneyyy/dsh-Go/releases/download/v1.0.15/dsh-go-1.0.15-arm64.apk
mkdir -p /tmp/official && (cd /tmp/official && unzip -q /tmp/official.apk)
mkdir -p runtime/out/arm64-v8a/assets runtime/out/arm64-v8a/jniLibs/arm64-v8a
cp -a /tmp/official/assets/runtime/. runtime/out/arm64-v8a/assets/runtime/
cp -a /tmp/official/lib/arm64-v8a/libproot*.so runtime/out/arm64-v8a/jniLibs/arm64-v8a/

# 4. 本地化 + 构建
cd app && flutter pub get && cd ..
python3 app/tool/l10n_merge.py
tooling/build-apk.sh --release -f arm64
```

---

## 安装

同签名覆盖安装即可，**不用卸载**（`.dev` 包与官方版并存）：

```bash
adb install -r dsh-go-arm64-dev-root-1013.apk
```

首次启用 root 模式：设置 → 诊断 → 开发者选项 → 打开 **root 模式** → 重启引擎 → KernelSU 弹授权 → 允许。

---

## 验证

```bash
# 1. root 模式生效？（启动参数应含 -b /data:/data）
tr '\0' ' ' < /proc/$(pgrep -f libproot.so | head -1)/cmdline | grep -o -- '-b /data:/data'

# 2. root-exec 通道（关键：TracerPid 必须是 0）
dsh-root 'id; grep TracerPid /proc/self/status'

# 3. 分区可见
ls /my_product/etc/permissions | head
```

预期：

```
uid=0(root) gid=0(root) groups=0(root) context=u:r:ksu:s0
TracerPid:	0
```

---

## 已知限制

| 限制 | 说明 |
|---|---|
| PRoot 内不能 `mount` / `nsenter` | proot 拦截 syscall，`/proc/1/ns/mnt` 打不开。要 mount 必须走 `dsh-root` |
| 系统分区只读 | `/product`、`/vendor`、`/my_*` 是 erofs，改系统需 KernelSU 模块 |
| root 模式启动较慢 | 每次启动要过一次 su 授权检查（20s 上限） |
| 引擎升级（v1.0.15+） | 仅替换上游管理的精确引擎路径，保留 apt/npm/pip 工具与配置；root 模式升级前归还这些引擎路径及父目录属主。保留备份，升级受阻时不要重置或卸载 |
| 与"手机操控"共用 socket 层 | root-exec 复用 `PhoneBridge` 的抽象 socket 实现，允许 uid 0 连接 |

---

## 故障排查

| 现象 | 原因 | 处理 |
|---|---|---|
| `cannot remove stale runtime pid file` | root 模式下 pid 文件属主是 root，`/tmp` 有 sticky 位 | 已在补丁中修（回落 `su rm -f`）；旧版可手动 `chmod 777 rootfs/tmp` |
| 界面报"解压时出错" | rootfs 里有 root 属主文件，`renameTo` 被拒 | 已在补丁中修（删除回落 + chown 归还 + 崩溃自愈） |
| `dsh-root: command not found` | 运行时升级清了 `/usr/local/bin` | `bash /root/tools/install-re.sh` |
| frida 报 `ptrace seize: Operation not supported` | 在 PRoot 内启动 | 用 `dsh-root --bg` 在 PRoot 外启动 frida-server |
| 开了 root 但分区看不到 | 启动没生效 | 重启引擎，确认日志有 `root mode: launching proot via su` |

---

## 目录结构

```
app/android/app/src/main/kotlin/io/github/ccch1mneyyy/dsh_app/
├── runtime/
│   ├── RootMode.kt           # su 检测/授权、命令包装、进程清理、chown 归还
│   ├── DshProcess.kt         # 通过 su 启动 proot、多分区 bind、pid 兜底、自愈标记
│   ├── RuntimeController.kt  # rootMode 状态与开关
│   ├── RuntimePlugin.kt      # setRootMode 方法通道
│   └── RuntimeInstaller.kt   # 删除兜底（su rm -rf）
├── rootexec/
│   └── RootExec.kt           # App 侧 root_exec 工具 + 桥生命周期
└── phone/PhoneBridge.kt      # 允许 uid 0 对端（root 模式 proot）

app/lib/
├── runtime/runtime_bridge.dart              # RuntimeStatus + setRootMode
└── ui/settings/direct_engine_settings.dart  # root 开关 UI

.github/workflows/build-apk.yml              # 复用官方 runtime 的 CI
```

---

## 设计取舍

- **不改上游风格、不提 PR**：上游 `AGENTS.md` 明确不接受外部 PR，且项目 AGPL-3.0。这里只做本地补丁层。
- **为什么不用 MCP 做 root 执行**：MCP 只是接口包装，能力不变；真正卡住的是"进程在 PRoot 里"，必须在 App 侧（Kotlin + su）执行。所以 root-exec 是一条极简私有通道，而不是一个 MCP 工具集。
- **为什么 `/data` 直接映射而不是 `/host-data`**：早期版本映射到 `/host-data` 以避免误操作；现在改为直挂 `/data`，脚本里 `cp`/`rsync` 更直观，危险操作靠约定（本仓库不提供批量删除脚本）。
- **为什么复用官方 runtime**：`runtime/build-runtime.sh` 需要 x86_64 交叉构建，产出 `assets/runtime` 和 `libproot*.so`（约 190MB，gitignore 掉了）。直接复用官方 release 里的产物，CI 从数小时降到 8 分钟。

---

## 版本对应

| 本仓库分支 | upstream 基线 | 说明 |
|---|---|---|
| `root-115` | v1.0.15 | 当前：保留 Linux 系统的升级流程 + root 引擎路径属主归还；CI 增加升级事务及属主命令测试 |
| `root-114` | v1.0.14 | 适配 McpServer/PhoneBridge 新签名；官方支持导入宠物包 |
| `root-113` | v1.0.13 | root 模式 + 多分区 + root-exec + 属主自愈 |
| `root-112` | v1.0.12 | 历史 |
| `root-111` | v1.0.11 | 历史：首次加入 root 开关 UI |

升级上游的流程：`git checkout -b root-1xx v1.0.1x` → `git cherry-pick` 补丁区间 → 解冲突（`DshProcess.kt`、`RuntimeController.kt`、`PhoneBridge.kt` 是高频冲突点）→ 更新 CI 里的官方 APK 版本号。

---

## 免责声明

- 真 root 意味着**没有沙箱**。容器里一条 `rm -rf /data/*` 删的是手机真数据。请自担风险。
- 本项目与上游 `ccch1mneyyy/dsh-Go` 作者无关，不是官方发行版。
- 上游 AGPL-3.0：本补丁集同样以 AGPL-3.0 分发；分发二进制时请遵守相应义务。
