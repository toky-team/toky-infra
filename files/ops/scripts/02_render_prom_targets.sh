set -euo pipefail
source /opt/ops/ops.env.sh

mkdir -p "${PROM_TARGET_DIR}"

mapfile -t IPS < "${OPS_CACHE_DIR}/app_private_ips.txt"

# node_exporter.json
NODE_TARGETS=()
for ip in "${IPS[@]}"; do
  NODE_TARGETS+=("\"${ip}:${NODE_EXPORTER_PORT}\"")
done
cat > "${PROM_TARGET_DIR}/node-exporter.json" <<EOF
[
  {
    "targets": [$(IFS=,; echo "${NODE_TARGETS[*]}")],
    "labels": { "role": "app", "svc": "${DISCOVER_TAG_1_VAL}", "type": "${DISCOVER_TAG_2_VAL}" }
  }
]
EOF

# nest-app.json
APP_TARGETS=()
for ip in "${IPS[@]}"; do
  APP_TARGETS+=("\"${ip}:${APP_HTTP_PORT}\"")
done
cat > "${PROM_TARGET_DIR}/nest-app.json" <<EOF
[
  {
    "targets": [$(IFS=,; echo "${APP_TARGETS[*]}")],
    "labels": { "role": "app", "svc": "${DISCOVER_TAG_1_VAL}", "type": "${DISCOVER_TAG_2_VAL}" }
  }
]
EOF

echo "${OPS_LOG_PREFIX} wrote file_sd targets to ${PROM_TARGET_DIR}"
