#!/system/bin/sh
MODDIR=${0%/*}
# ========== SELinux 放行（Magisk 动态注入；KSU/APatch/FolkPatch 由 sepolicy.rule 加载） ==========
magiskpolicy --live "allow untrusted_app self tcp_socket { name_bind listen create }" 2>/dev/null
magiskpolicy --live "allow untrusted_app shell_data_file file { read write open create append unlink }" 2>/dev/null
magiskpolicy --live "allow untrusted_app shell_data_file dir { read write search add_name remove_name }" 2>/dev/null

# ========== ddns-go 二进制路径：优先 /system/bin（magic mount），fallback 到模块目录 ==========
DDNS_BIN="/system/bin/ddns-go"
if [ ! -x "${DDNS_BIN}" ]; then
    DDNS_BIN="${MODDIR}/system/bin/ddns-go"
fi
chmod 755 "${DDNS_BIN}" 2>/dev/null
chcon u:object_r:system_file:s0 "${DDNS_BIN}" 2>/dev/null

# ========== 路径 ==========
# 持久目录：config.yaml、归档目录 old_logs、归档开关 enable_log_archive；卸载整体删除
WORK_DIR="/data/adb/ddns_go_module"
# 临时目录：每次开机脚本清空模块相关文件
LOG_FILE="/data/local/tmp/ddns-go.log"
WATCHDOG_LOG="/data/local/tmp/ddns-watchdog.log"
PID_FILE="/data/local/tmp/ddns-go.pid"
ARCHIVE_FILE="${WORK_DIR}/enable_log_archive"
OLD_LOGS_DIR="${WORK_DIR}/old_logs"
WATCHDOG_SWITCH="${WORK_DIR}/watchdog_enabled"
WATCHDOG_INTERVAL_FILE="${WORK_DIR}/watchdog_interval"
AUTOSTART_FILE="${WORK_DIR}/autostart"
PORT_FILE="${WORK_DIR}/listen_port"

mkdir -p "${WORK_DIR}"

# ========== 日志滚动裁剪（运行中防日志无限涨）：最多 5000 行，兜底 2MB ==========
MAX_LINE=5000
MAX_SIZE_KB=2048
rotate_log() {
    LOG_PATH="$1"
    if [ -f "${LOG_PATH}" ]; then
        LINE_COUNT=$(wc -l < "${LOG_PATH}")
        if [ "${LINE_COUNT}" -gt "${MAX_LINE}" ]; then
            tail -n "${MAX_LINE}" "${LOG_PATH}" > "${LOG_PATH}.tmp"
            mv "${LOG_PATH}.tmp" "${LOG_PATH}"
            echo "$(date '+%Y-%m-%d %H:%M:%S'): 日志超过${MAX_LINE}行，已裁剪旧记录" >> "${LOG_PATH}"
        fi
        FILE_SIZE=$(du -k "${LOG_PATH}" | cut -f1)
        if [ "${FILE_SIZE}" -gt "${MAX_SIZE_KB}" ]; then
            tail -n 1000 "${LOG_PATH}" > "${LOG_PATH}.tmp"
            mv "${LOG_PATH}.tmp" "${LOG_PATH}"
            echo "$(date '+%Y-%m-%d %H:%M:%S'): 日志超过${MAX_SIZE_KB}KB，强制裁剪至1000行" >> "${LOG_PATH}"
        fi
    fi
}

# ========== 开机归档逻辑 ==========
# 读开关：=1 把上一轮 tmp 两份日志归档到 old_logs（最多保留 10 组），然后清空 tmp；
#        =0/不存在 不归档，直接清空 tmp。
do_boot_archive() {
    ARCHIVE_ON=0
    [ -f "${ARCHIVE_FILE}" ] && ARCHIVE_ON=$(cat "${ARCHIVE_FILE}" 2>/dev/null)

    if [ "${ARCHIVE_ON}" = "1" ]; then
        mkdir -p "${OLD_LOGS_DIR}"
        TS=$(date '+%Y%m%d_%H%M%S')
        ARCHIVE_DIR="${OLD_LOGS_DIR}/${TS}"
        mkdir -p "${ARCHIVE_DIR}"
        [ -f "${LOG_FILE}" ] && cp "${LOG_FILE}" "${ARCHIVE_DIR}/ddns-go.log"
        [ -f "${WATCHDOG_LOG}" ] && cp "${WATCHDOG_LOG}" "${ARCHIVE_DIR}/ddns-watchdog.log"
        echo "$(date '+%Y-%m-%d %H:%M:%S'): 开机归档完成" > "${ARCHIVE_DIR}/boot.txt"
        # 最多保留 10 组，按时间倒序，删第 11 个及以后（最旧的）
        ls -1t "${OLD_LOGS_DIR}" 2>/dev/null | tail -n +11 | while read -r d; do
            [ -n "${d}" ] && rm -rf "${OLD_LOGS_DIR}/${d}"
        done
    fi

    # 清空 tmp 下模块相关文件
    rm -f "${LOG_FILE}" "${WATCHDOG_LOG}" "${PID_FILE}"
}

# ========== 等待系统开机完成 ==========
until [ "$(getprop sys.boot_completed)" = "1" ]; do
    sleep 5
done

# ========== 开机归档 + 清空 tmp ==========
do_boot_archive

# ========== 动态等待网络连通，多 DNS 探测，最多 60 秒 ==========
NET_WAIT_MAX=60
NET_WAIT=0
DNS_LIST="223.5.5.5 114.114.114.114 180.76.76.76"
echo "$(date '+%Y-%m-%d %H:%M:%S'): 系统开机完成，开始等待网络连通" >> "${WATCHDOG_LOG}"
while true; do
    UP=0
    for ip in ${DNS_LIST}; do
        if ping -c1 -W2 "${ip}" >/dev/null 2>&1; then
            UP=1
            break
        fi
    done
    if [ "${UP}" -eq 1 ]; then
        break
    fi
    sleep 3
    NET_WAIT=$((NET_WAIT + 3))
    if [ "${NET_WAIT}" -ge "${NET_WAIT_MAX}" ]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S'): 网络等待超时(${NET_WAIT_MAX}s)，直接启动 ddns-go" >> "${WATCHDOG_LOG}"
        break
    fi
done
if [ "${NET_WAIT}" -lt "${NET_WAIT_MAX}" ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S'): 网络已连通，耗时${NET_WAIT}秒" >> "${WATCHDOG_LOG}"
fi

start_ddns() {
    # 启动前先滚动日志（开机已清空，这里主要给看门狗重启时用）
    rotate_log "${LOG_FILE}"
    rotate_log "${WATCHDOG_LOG}"
    # 兜底杀所有 ddns-go 进程（防止 PID 文件记录的 PID 不准）
    pkill -f "bin/ddns-go" 2>/dev/null
    sleep 1
    rm -f "${PID_FILE}"
    echo "$(date '+%Y-%m-%d %H:%M:%S'): 启动 ddns-go" >> "${LOG_FILE}"
    # 读自定义端口，默认 9876
    DDNS_PORT=9876
    [ -f "${PORT_FILE}" ] && DDNS_PORT=$(cat "${PORT_FILE}" 2>/dev/null)
    case "${DDNS_PORT}" in (''|*[!0-9]*) DDNS_PORT=9876 ;; esac
    if [ "${DDNS_PORT}" -lt 1024 ] 2>/dev/null; then DDNS_PORT=9876; fi
    if [ "${DDNS_PORT}" -gt 65535 ] 2>/dev/null; then DDNS_PORT=9876; fi
    # 读监听模式：local=仅本机(127.0.0.1)，其他=内网可访问(0.0.0.0)
    LISTEN_MODE=$(cat "${WORK_DIR}/listen_mode" 2>/dev/null)
    if [ "${LISTEN_MODE}" = "local" ]; then
        LISTEN_ADDR="127.0.0.1"
    else
        LISTEN_ADDR="0.0.0.0"
    fi
    "${DDNS_BIN}" -l "${LISTEN_ADDR}:${DDNS_PORT}" -c "${WORK_DIR}/config.yaml" >> "${LOG_FILE}" 2>&1 &
    echo $! > "${PID_FILE}"
}

watchdog() {
    while true; do
        # 自检：如果模块目录已被删除（用户卸载了模块），清理所有残留后自杀
        if [ ! -d "${MODDIR}" ]; then
            echo "$(date '+%Y-%m-%d %H:%M:%S'): 模块目录已消失，执行卸载自清理" >> /data/local/tmp/ddns-watchdog.log 2>/dev/null
            pkill -9 -f "bin/ddns-go" 2>/dev/null
            rm -f /data/local/tmp/ddns-go.log /data/local/tmp/ddns-watchdog.log /data/local/tmp/ddns-go.pid
            [ -d "/data/adb/ddns_go_module" ] && rm -rf /data/adb/ddns_go_module
            exit 0
        fi
        rotate_log "${WATCHDOG_LOG}"
        # 读用户自定义的看门狗检测间隔（秒），默认 30，限制 5~300
        WD_INTERVAL=30
        [ -f "${WATCHDOG_INTERVAL_FILE}" ] && WD_INTERVAL=$(cat "${WATCHDOG_INTERVAL_FILE}" 2>/dev/null)
        case "${WD_INTERVAL}" in (''|*[!0-9]*) WD_INTERVAL=30 ;; esac
        if [ "${WD_INTERVAL}" -lt 5 ] 2>/dev/null; then WD_INTERVAL=5; fi
        if [ "${WD_INTERVAL}" -gt 300 ] 2>/dev/null; then WD_INTERVAL=300; fi
        # 开机自启开关：=0 时完全手动，不自动拉起
        AUTO_ON=1
        [ -f "${AUTOSTART_FILE}" ] && AUTO_ON=$(cat "${AUTOSTART_FILE}" 2>/dev/null)
        if [ "${AUTO_ON}" = "0" ]; then
            echo "$(date '+%Y-%m-%d %H:%M:%S'): 开机自启已关闭，跳过自动拉起" >> "${WATCHDOG_LOG}"
            sleep 60
            continue
        fi
        # 看门狗开关：=0 时不拉起，只记日志；文件不存在/=1 视为开启
        WD_ON=1
        [ -f "${WATCHDOG_SWITCH}" ] && WD_ON=$(cat "${WATCHDOG_SWITCH}" 2>/dev/null)
        if [ "${WD_ON}" = "0" ]; then
            echo "$(date '+%Y-%m-%d %H:%M:%S'): 看门狗已被手动关闭，跳过自动拉起" >> "${WATCHDOG_LOG}"
            sleep 30
            continue
        fi
        if [ ! -f "${PID_FILE}" ]; then
            echo "$(date '+%Y-%m-%d %H:%M:%S'): PID 文件不存在，重启 ddns-go" >> "${WATCHDOG_LOG}"
        else
            PID=$(cat "${PID_FILE}")
            if [ -z "${PID}" ] || ! ( [ "${PID}" -eq "${PID}" ] 2>/dev/null && ps -p "${PID}" >/dev/null 2>&1 ); then
                echo "$(date '+%Y-%m-%d %H:%M:%S'): ddns-go 进程已停止，尝试重启" >> "${WATCHDOG_LOG}"
                start_ddns
            fi
        fi
        sleep "${WD_INTERVAL}"
    done
}

# 【模块停止钩子】模块禁用/卸载时清理进程
trap '
if [ -f "$PID_FILE" ]; then
    OLD_PID=$(cat "$PID_FILE")
    if [ -n "$OLD_PID" ] && [ "$OLD_PID" -eq "$OLD_PID" ] 2>/dev/null; then
        kill "$OLD_PID" 2>/dev/null
    fi
fi
rm -f "$PID_FILE"
pkill -f watchdog 2>/dev/null
exit 0
' SIGTERM SIGINT

# 首次启动：读 autostart 开关，=0 则不自动拉起
AUTO_ON=1
[ -f "${AUTOSTART_FILE}" ] && AUTO_ON=$(cat "${AUTOSTART_FILE}" 2>/dev/null)
if [ "${AUTO_ON}" = "1" ]; then
    start_ddns
else
    echo "$(date '+%Y-%m-%d %H:%M:%S'): 开机自启已关闭，不自动启动 ddns-go（如需启动请用 WebUI 或 sh action.sh start）" >> "${WATCHDOG_LOG}"
fi
# 看门狗后台运行（看门狗循环内部会再读一次 autostart，=0 时只记日志不拉起）
watchdog &
