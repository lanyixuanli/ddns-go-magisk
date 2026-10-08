#!/system/bin/sh
WORK_DIR="/data/adb/ddns_go_module"
LOG_FILE="/data/local/tmp/ddns-go.log"
WATCHDOG_LOG="/data/local/tmp/ddns-watchdog.log"
PID_FILE="/data/local/tmp/ddns-go.pid"
ARCHIVE_FILE="${WORK_DIR}/enable_log_archive"
WATCHDOG_SWITCH="${WORK_DIR}/watchdog_enabled"
AUTOSTART_FILE="${WORK_DIR}/autostart"

echo "==================== DDNS-GO 模块状态 ===================="
echo "持久工作目录: ${WORK_DIR}"
echo "临时目录:     /data/local/tmp"
echo

# ---- 归档开关 ----
if [ -f "${ARCHIVE_FILE}" ]; then
    ARC=$(cat "${ARCHIVE_FILE}" 2>/dev/null)
    if [ "${ARC}" = "1" ]; then
        echo "日志归档开关: ✅ 开启（开机自动归档上一轮日志到 old_logs，保留 10 组）"
    else
        echo "日志归档开关: ❌ 关闭（开机直接清空 tmp 日志）"
    fi
else
    echo "日志归档开关: ❌ 关闭（开关文件不存在，默认关闭）"
fi

# ---- 看门狗开关 ----
WD=1
[ -f "${WATCHDOG_SWITCH}" ] && WD=$(cat "${WATCHDOG_SWITCH}" 2>/dev/null)
if [ "${WD}" = "0" ]; then
    echo "看门狗开关:   ❌ 关闭（ddns-go 异常退出不会自动拉起）"
else
    echo "看门狗开关:   ✅ 开启（ddns-go 异常退出会自动拉起）"
fi

# ---- 开机自启开关 ----
AUTO=1
[ -f "${AUTOSTART_FILE}" ] && AUTO=$(cat "${AUTOSTART_FILE}" 2>/dev/null)
if [ "${AUTO}" = "0" ]; then
    echo "开机自启:     ❌ 关闭（重启手机后不自动启动，需手动开）"
else
    echo "开机自启:     ✅ 开启（重启手机后自动启动）"
fi
echo

# ---- PID / 进程 ----
if [ ! -d "${WORK_DIR}" ]; then
    echo "❌ 错误：持久目录不存在！模块可能未启动或已卸载"
    exit 1
fi
if [ -f "${PID_FILE}" ]; then
    PID=$(cat "${PID_FILE}")
    echo "✅ PID 文件存在，PID=${PID}"
    if ps -p "${PID}" >/dev/null 2>&1; then
        echo "✅ ddns-go 进程正在运行"
    else
        echo "⚠️  PID 文件存在，但 ddns-go 进程已经消失"
    fi
else
    echo "❌ PID 文件不存在，ddns-go 未启动"
fi
echo

# ---- 日志文件存在状态 ----
echo "---------------- 日志文件 ----------------"
if [ -f "${LOG_FILE}" ]; then
    echo "✅ ddns-go.log: $(du -h "${LOG_FILE}" | cut -f1)"
else
    echo "❌ ddns-go.log: 不存在"
fi
if [ -f "${WATCHDOG_LOG}" ]; then
    echo "✅ ddns-watchdog.log: $(du -h "${WATCHDOG_LOG}" | cut -f1)"
else
    echo "❌ ddns-watchdog.log: 不存在"
fi
echo

# ---- 尾部 20 行（终端手动查看用） ----
echo "---------------- ddns-go.log 尾部 20 行 ----------------"
if [ -f "${LOG_FILE}" ]; then
    tail -n 20 "${LOG_FILE}"
else
    echo "（日志文件不存在）"
fi
echo
echo "---------------- ddns-watchdog.log 尾部 20 行 ----------------"
if [ -f "${WATCHDOG_LOG}" ]; then
    tail -n 20 "${WATCHDOG_LOG}"
else
    echo "（日志文件不存在）"
fi
echo "=========================================================="
