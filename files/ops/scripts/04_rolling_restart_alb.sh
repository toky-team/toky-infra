set -euo pipefail
source /opt/ops/ops.env.sh

if [[ -z "${TARGET_GROUP_ARN}" ]]; then
  echo "${OPS_LOG_PREFIX} ERROR: TARGET_GROUP_ARN not set"; exit 1
fi

mapfile -t IPS < "${OPS_CACHE_DIR}/app_private_ips.txt"
mapfile -t IDS < "${OPS_CACHE_DIR}/app_instance_ids.txt"

# 헬퍼: 특정 IP의 /health 응답 대기
wait_http_ok() {
  local ip="$1"
  local deadline=$(( $(date +%s) + HEALTH_TIMEOUT_SEC ))
  while (( $(date +%s) < deadline )); do
    if curl -fsS "http://${ip}:${APP_HTTP_PORT}${HEALTH_PATH}" >/dev/null 2>&1; then
      echo "${OPS_LOG_PREFIX} health OK on ${ip}"
      return 0
    fi
    sleep 2
  done
  echo "${OPS_LOG_PREFIX} ERROR: health timeout on ${ip}"
  return 1
}

# 헬퍼: ALB에서 타깃 상태가 healthy 될 때까지 대기
wait_tg_healthy() {
  local target_desc="$1"  # ip 또는 instance-id
  local deadline=$(( $(date +%s) + HEALTH_TIMEOUT_SEC ))
  while (( $(date +%s) < deadline )); do
    local health
    health=$(aws elbv2 describe-target-health \
      --region "${AWS_REGION}" \
      --target-group-arn "${TARGET_GROUP_ARN}" \
      --query 'TargetHealthDescriptions[].TargetHealth.State' \
      --output text 2>/dev/null || true)
    # 여러 항목 반환 가능 → 문자열 포함 검사
    if grep -q "healthy" <<< "${health}"; then
      echo "${OPS_LOG_PREFIX} TG reports healthy (${target_desc})"
      return 0
    fi
    sleep 3
  done
  echo "${OPS_LOG_PREFIX} WARN: TG did not report healthy within timeout (${target_desc})"
  return 1
}

# 헬퍼: 타깃 해제/등록
tg_deregister() {
  local id="$1"
  local json
  if [[ "${TARGET_TYPE}" == "instance" ]]; then
    json="Id=${id},Port=${TARGET_PORT}"
  else
    json="Id=${id},Port=${TARGET_PORT}"
  fi
  aws elbv2 deregister-targets \
    --region "${AWS_REGION}" \
    --target-group-arn "${TARGET_GROUP_ARN}" \
    --targets "${json}"
}

tg_register() {
  local id="$1"
  local json
  if [[ "${TARGET_TYPE}" == "instance" ]]; then
    json="Id=${id},Port=${TARGET_PORT}"
  else
    json="Id=${id},Port=${TARGET_PORT}"
  fi
  aws elbv2 register-targets \
    --region "${AWS_REGION}" \
    --target-group-arn "${TARGET_GROUP_ARN}" \
    --targets "${json}"
}

# 메인 루프(순차 롤링)
for idx in "${!IPS[@]}"; do
  ip="${IPS[$idx]}"
  id="${IDS[$idx]:-}"

  # ALB에 넘길 타깃 식별자
  target_key="${ip}"
  if [[ "${TARGET_TYPE}" == "instance" ]]; then
    if [[ -z "${id}" ]]; then
      echo "${OPS_LOG_PREFIX} ERROR: missing instance-id for ${ip}"
      exit 1
    fi
    target_key="${id}"
  fi

  echo "==============================="
  echo "${OPS_LOG_PREFIX} Rolling on node: ip=${ip} target=${target_key}"

  # 1) TG에서 제외 (커넥션 드레이닝은 TG 설정의 Deregistration delay를 따름)
  tg_deregister "${target_key}"
  echo "${OPS_LOG_PREFIX} deregistered from TG: ${target_key}"
  sleep 5

  # 2) 원격 배포/재시작
  ssh -i "${SSH_KEY}" ${SSH_OPTS} "${SSH_USER}@${ip}" "${REMOTE_DEPLOY_CMD}"
  echo "${OPS_LOG_PREFIX} remote deploy done on ${ip}"

  # 3) 앱 자체 헬스 확인 (프라이빗IP:APP_PORT/health)
  wait_http_ok "${ip}"

  # 4) TG 재등록
  tg_register "${target_key}"
  echo "${OPS_LOG_PREFIX} re-registered to TG: ${target_key}"

  # 5) TG healthy 대기(관대하게)
  wait_tg_healthy "${target_key}" || true

  echo "${OPS_LOG_PREFIX} finished node ${ip}"
done
