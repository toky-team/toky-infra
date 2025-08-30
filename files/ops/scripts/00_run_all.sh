set -euo pipefail

/opt/ops/01_discover.sh
/opt/ops/02_render_prom_targets.sh
/opt/ops/03_reload_prom.sh
/opt/ops/04_rolling_restart_alb.sh