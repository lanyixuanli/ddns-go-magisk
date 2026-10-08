#!/system/bin/sh
# 卸载清理：杀进程、删 tmp 日志、整体删持久目录
LOG="/data/local/tmp/ddns-uninstall.log"
PID_FILE="/data/local/tmp/ddns-go.pid"
PERSIST_DIR="/data/adb/ddns_go_module"

echo "$(date): === uninstall.sh 开始执行 ===" > "${LOG}"

# 1. 杀 ddns-go 进程
if [ -f "${PID_FILE}" ]; then
    OLD_PID=$(cat "${PID_FILE}" 2>/dev/null)
    if [ -n "${OLD_PID}" ]; then
        kill "${OLD_PID}" 2>/dev/null
        sleep 1
        kill -9 "${OLD_PID}" 2>/dev/null
    fi
    rm -f "${PID_FILE}"
fi
# 兜底强杀
pkill -9 -f "bin/ddns-go" 2>/dev/null
pkill -9 -f "watchdog" 2>/dev/null
echo "$(date): 进程已清理" >> "${LOG}"

# 2. 删 tmp 下日志和 pid
rm -f /data/local/tmp/ddns-go.log
rm -f /data/local/tmp/ddns-watchdog.log
rm -f /data/local/tmp/ddns-go.pid
echo "$(date): tmp 临时文件已清理" >> "${LOG}"

# 3. 整体删持久目录（config.yaml、old_logs、所有开关文件）
if [ -d "${PERSIST_DIR}" ]; then
    rm -rf "${PERSIST_DIR}" 2>>"${LOG}"
    sleep 1
    # 重试一次，防止第一次被占用
    if [ -d "${PERSIST_DIR}" ]; then
        rm -rf "${PERSIST_DIR}" 2>>"${LOG}"
    fi
fi
echo "$(date): 持久目录 ${PERSIST_DIR} 清理结果: $([ -d ${PERSIST_DIR} ] && echo '仍存在' || echo '已删除')" >> "${LOG}"
echo "$(date): === uninstall.sh 执行完成 ===" >> "${LOG}"

# 最后删自己的日志
rm -f "${LOG}"
exit 0
