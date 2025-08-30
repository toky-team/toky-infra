set -euo pipefail
source /opt/ops/ops.env.sh

mkdir -p "${OPS_CACHE_DIR}"

echo "${OPS_LOG_PREFIX} discovering app nodes by tags: ${DISCOVER_TAG_1_KEY}=${DISCOVER_TAG_1_VAL}, ${DISCOVER_TAG_2_KEY}=${DISCOVER_TAG_2_VAL}"

# 인스턴스 정보 조회
JSON=$(aws ec2 describe-instances \
  --region "${AWS_REGION}" \
  --filters \
    "Name=tag:${DISCOVER_TAG_1_KEY},Values=${DISCOVER_TAG_1_VAL}" \
    "Name=tag:${DISCOVER_TAG_2_KEY},Values=${DISCOVER_TAG_2_VAL}" \
    "Name=instance-state-name,Values=running")

# Private IP 목록
echo "${JSON}" | jq -r '.Reservations[].Instances[].PrivateIpAddress' | grep -v '^null$' > "${OPS_CACHE_DIR}/app_private_ips.txt" || true
# Instance ID 목록
echo "${JSON}" | jq -r '.Reservations[].Instances[].InstanceId'        | grep -v '^null$' > "${OPS_CACHE_DIR}/app_instance_ids.txt" || true

echo "${OPS_LOG_PREFIX} private IPs:"
cat "${OPS_CACHE_DIR}/app_private_ips.txt" || true
echo "${OPS_LOG_PREFIX} instance IDs:"
cat "${OPS_CACHE_DIR}/app_instance_ids.txt" || true

count=$(wc -l < "${OPS_CACHE_DIR}/app_private_ips.txt" || echo 0)
if [[ "${count}" -eq 0 ]]; then
  echo "${OPS_LOG_PREFIX} ERROR: no running app nodes found"
  exit 1
fi
