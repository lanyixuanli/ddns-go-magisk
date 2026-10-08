# ddns-go-Magisk 模块

把 [ddns-go](https://github.com/jeessy2/ddns-go) 跑在 Android 手机上的 Magisk / KernelSU / APatch / FolkPatch 模块，带 Web 控制面板、看门狗保活、日志管理。项目开源在 GitHub：[lanyixuanli/ddns-go-magisk](https://github.com/lanyixuanli/ddns-go-magisk)，欢迎 Star。

## 功能特性

- **多 root 管理器兼容**：Magisk / KernelSU / APatch / FolkPatch 通用
- **Web 控制面板**：集成在 KSU/APatch 管理器里，点图标直接打开
- **看门狗保活**：ddns-go 进程意外退出自动拉起，间隔可自定义（默认 30 秒）
- **开机自启**：刷入后自动启动，WebUI 可一键开关
- **一键开关**：不用时可以关掉 ddns-go 和看门狗，不重启手机
- **自定义端口**：默认 9876，WebUI 里直接改，保存自动重启生效
- **日志查看**：tail 50 行实时查看 ddns-go 和看门狗日志，支持一键清空
- **日志归档**：可选开机自动归档上一轮日志（最多保留 10 组）
- **IP 地址显示**：自动获取本机 IPv4 / IPv6 地址，一键打开后台
- **主题切换**：深色 / 浅色 / 跟随系统，选择自动记住
- **卸载干净**：自动清理所有残留，重启后无文件残留

## 安装要求

- Android 8.0+ arm64 设备
- 已刷入 Magisk / KernelSU / APatch 任一 root 管理器
- 预编译好的 ddns-go arm64 二进制（已内置在 `system/bin/ddns-go`）

## 安装方法

1. 把模块打包成 zip
2. 在 root 管理器里刷入 zip
3. 重启手机
4. 打开 root 管理器，点 ddns-go-Module 图标打开 Web 控制面板
5. 点"打开后台"按钮进入 ddns-go 原生配置页，配置你的 DDNS 服务商

## 目录结构

```
ddns-go-magisk/
├── module.prop              # 模块元信息
├── service.sh               # 开机常驻脚本（看门狗、自启、归档）
├── action.sh                # 终端快捷操作（start/stop/restart 等）
├── uninstall.sh             # 卸载清理脚本
├── sepolicy.rule            # SELinux 规则
├── webroot/
│   └── index.html           # Web 控制面板
├── system/
│   └── bin/
│       └── ddns-go          # 预编译 arm64 二进制
└── META-INF/
    └── com/google/android/
        └── update-binary    # 安装脚本
```

## 文件位置

| 路径 | 说明 |
|---|---|
| `/data/adb/ddns_go_module/` | 持久目录（config.yaml、开关文件、归档日志） |
| `/data/adb/ddns_go_module/config.yaml` | ddns-go 配置文件 |
| `/data/adb/ddns_go_module/enable_log_archive` | 日志归档开关（=1 开启） |
| `/data/adb/ddns_go_module/watchdog_enabled` | 看门狗开关（=0 关闭） |
| `/data/adb/ddns_go_module/autostart` | 开机自启开关（=0 不自动启动） |
| `/data/adb/ddns_go_module/listen_port` | 自定义监听端口（默认 9876） |
| `/data/adb/ddns_go_module/watchdog_interval` | 看门狗检测间隔秒数（默认 30） |
| `/data/local/tmp/ddns-go.log` | ddns-go 运行日志 |
| `/data/local/tmp/ddns-watchdog.log` | 看门狗日志 |
| `/data/local/tmp/ddns-go.pid` | 进程 PID 文件 |

## Web 控制面板按钮说明

| 按钮 | 作用 |
|---|---|
| 刷新状态 | 重新加载所有状态信息 |
| 电源（开/关） | 启动或停止 ddns-go 进程 |
| 重启 | 杀掉进程后立即重新启动 |
| 打开后台 | 浏览器打开 ddns-go 原生管理页面 |
| 清空日志 | 清空 ddns-go 和看门狗日志 |
| 看门狗保活 | 开关看门狗自动拉起功能 |
| 开机自启 DDNS-GO | 开关开机时自动启动 ddns-go |
| 日志归档 | 开关开机自动归档上一轮日志 |
| 主题下拉 | 深色 / 浅色 / 跟随系统 |

## 终端命令（action.sh）

在终端里执行 `sh /data/adb/modules/ddns-go-Module/action.sh [命令]`：

| 命令 | 作用 |
|---|---|
| 无参数 | 浏览器打开 ddns-go 后台 |
| start | 启动 ddns-go |
| stop | 停止 ddns-go |
| restart | 重启 ddns-go |
| watchdog_on | 开启看门狗 |
| watchdog_off | 关闭看门狗 |
| autostart_on | 开启开机自启 |
| autostart_off | 关闭开机自启 |
| clear | 清空日志 |
| toggle_archive | 切换日志归档开关 |

## 注意事项

- 首次安装重启后，ddns-go 会自动启动，不需要手动开
- 修改端口后 ddns-go 会自动重启生效，不用手动重启手机
- 手机如果没有公网 IP 或 IPv6，DDNS 域名解析可能不生效
- 卸载模块后看门狗会在 30 秒内自动清理所有残留文件
- 默认监听 `0.0.0.0:9876`，局域网内其他设备可以访问；如果只想本机访问，改 service.sh 里的 `-l` 参数为 `127.0.0.1:${DDNS_PORT}`

## 故障排查

### Web 面板显示 ddns-go 未运行
1. 开机后等 10~30 秒，模块会自动等网络就绪再启动
2. 点"重启"按钮手动拉起
3. 查看 ddns-go.log 和 ddns-watchdog.log 里的错误信息

### 卸载后有残留文件
1. 等 30 秒，看门狗会自动检测模块消失并清理残留
2. 手动删除 `/data/adb/ddns_go_module` 和 `/data/local/tmp/ddns-*` 即可

## 作者

蓝逸轩

- 酷安：[https://www.coolapk.com/u/1034657](https://www.coolapk.com/u/1034657)
- 微博：[https://weibo.com/u/5249612129](https://weibo.com/u/5249612129)
- 个人网站：[https://www.12xf.cn](https://www.12xf.cn)
- 个人网站：[https://www.lyx6.com](https://www.lyx6.com)
