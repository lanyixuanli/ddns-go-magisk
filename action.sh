#!/system/bin/sh
# ============================================================
# action.sh
# 用途 1：KSU / APatch / FolkPatch 模块卡片右侧操作按钮（无参调用）
#         -> 唤起浏览器打开 ddns-go 原生管理面板 http://127.0.0.1:9876
# 用途 2：终端手动执行带参动作（WebUI 面板本身已直接 exec，这里留作 shell 入口）
#         sh action.sh restart         重启 ddns-go
#         sh action.sh clear           清空两个日志
#         sh action.sh toggle_archive   翻转归档开关 0/1
# ============================================================

WORK_DIR="/data/adb/ddns_go_module"
LOG_FILE="/data/local/tmp/ddns-go.log"
WATCHDOG_LOG="/data/local/tmp/ddns-watchdog.log"
PID_FILE="/data/local/tmp/ddns-go.pid"
ARCHIVE_FILE="${WORK_DIR}/enable_log_archive"
WATCHDOG_SWITCH="${WORK_DIR}/watchdog_enabled"
WATCHDOG_INTERVAL_FILE="${WORK_DIR}/watchdog_interval"
AUTOSTART_FILE="${WORK_DIR}/autostart"
PORT_FILE="${WORK_DIR}/listen_port"

# ddns-go 二进制完整路径
DDNS_BIN="/system/bin/ddns-go"
[ ! -x "${DDNS_BIN}" ] && DDNS_BIN="${0%/*}/system/bin/ddns-go"
chmod 755 "${DDNS_BIN}" 2>/dev/null

# 读端口
get_port() {
    local p=9876
    [ -f "${PORT_FILE}" ] && p=$(cat "${PORT_FILE}" 2>/dev/null)
    case "${p}" in (''|*[!0-9]*) p=9876 ;; esac
    if [ "${p}" -lt 1024 ] 2>/dev/null; then p=9876; fi
    if [ "${p}" -gt 65535 ] 2>/dev/null; then p=9876; fi
    echo "${p}"
}

# ---------- 无参数：卡片按钮，打开原生面板 ----------
if [ $# -eq 0 ]; then
    am start --user 0 -a android.intent.action.VIEW -d "http://127.0.0.1:$(get_port)" >/dev/null 2>&1
    exit 0
fi

# ---------- 带参数：动作分支 ----------
case "$1" in
    restart)
        # 彻底杀所有 ddns-go 进程
        pkill -f "bin/ddns-go" 2>/dev/null
        sleep 1
        rm -f "${PID_FILE}"
        P=$(get_port)
        nohup "${DDNS_BIN}" -l "0.0.0.0:${P}" -c "${WORK_DIR}/config.yaml" >> "${LOG_FILE}" 2>&1 &
        echo $! > "${PID_FILE}"
        echo "ddns-go 已重启，PID=$!，端口=${P}"
        ;;
    stop)
        # 关闭 ddns-go（pkill 彻底杀）
        pkill -f "bin/ddns-go" 2>/dev/null
        rm -f "${PID_FILE}"
        echo "ddns-go 已关闭"
        ;;
    start)
        # 开启 ddns-go
        pkill -f "bin/ddns-go" 2>/dev/null
        sleep 0.5
        rm -f "${PID_FILE}"
        P=$(get_port)
        nohup "${DDNS_BIN}" -l "0.0.0.0:${P}" -c "${WORK_DIR}/config.yaml" >> "${LOG_FILE}" 2>&1 &
        echo $! > "${PID_FILE}"
        echo "ddns-go 已启动，PID=$!，端口=${P}"
        ;;
    watchdog_on)
        echo 1 > "${WATCHDOG_SWITCH}"
        echo "看门狗已开启"
        ;;
    watchdog_off)
        echo 0 > "${WATCHDOG_SWITCH}"
        echo "看门狗已关闭（不会自动拉起 ddns-go）"
        ;;
    autostart_on)
        echo 1 > "${AUTOSTART_FILE}"
        echo "开机自启已开启（重启手机后自动启动 ddns-go）"
        ;;
    autostart_off)
        echo 0 > "${AUTOSTART_FILE}"
        echo "开机自启已关闭（重启手机后需手动启动 ddns-go）"
        ;;
    clear)
        > "${LOG_FILE}"
        > "${WATCHDOG_LOG}"
        ;;
    toggle_archive)
        V=$(cat "${ARCHIVE_FILE}" 2>/dev/null)
        if [ "${V}" = "1" ]; then
            echo 0 > "${ARCHIVE_FILE}"
            echo "归档开关已关闭"
        else
            echo 1 > "${ARCHIVE_FILE}"
            echo "归档开关已开启"
        fi
        ;;
    *)
        echo "用法: $0 [restart|start|stop|watchdog_on|watchdog_off|autostart_on|autostart_off|clear|toggle_archive]"
        exit 1
        ;;
esac
exit 0
