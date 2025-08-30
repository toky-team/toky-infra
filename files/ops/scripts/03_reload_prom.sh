set -euo pipefail
source /opt/ops/ops.env.sh

curl -fsS -X POST "${PROM_RELOAD_URL}"
echo "${OPS_LOG_PREFIX} prometheus reloaded"
