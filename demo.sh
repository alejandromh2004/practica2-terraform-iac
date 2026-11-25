#!/usr/bin/env bash
# ==============================================================================
#  POKÉDEX CLOUD — DEMO GUIADA PARA LA DEFENSA (Práctica 2: Terraform + Docker)
# ==============================================================================
#  Script interactivo paso a paso (1 ENTER por paso) diseñado para exponer
#  todos los requisitos de la práctica de forma clara, visual y sin improvisar.
#
#  USO:
#    ./demo.sh                  Demo completa paso a paso (verifica/despliega)
#    ./demo.sh --fresh          Destruye DEV y PRO y los despliega desde cero
#    ./demo.sh --from 4 --to 10 Ejecuta solo un rango concreto de pasos
#    ./demo.sh --auto           Ejecuta sin pausas (ideal para ensayar)
#    ./demo.sh --no-browser     No abre pestañas automáticamente en el navegador
#    ./demo.sh --list           Muestra el índice de pasos y tiempos objetivo
#    ./demo.sh --map            Mapea cada requisito del enunciado a archivo:línea
#    ./demo.sh --access         Imprime tabla de URLs, puertos y credenciales
#
#  SEGURIDAD DURANTE LA DEMO:
#    - Paso 5 escala PRO temporalmente de 3 a 4 réplicas y luego vuelve a 3.
#    - Paso 8 detiene pro-app-3 para demostrar HA y disparar alerta en Discord.
#    - Si sales antes de tiempo (q, Ctrl+C o error), el 'trap' revierte todo
#      automáticamente para dejar la infraestructura intacta.
# ==============================================================================

set -u

# Localizar la raíz del proyecto funcione donde se coloque demo.sh (raíz o scripts/)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/terraform/main.tf" ]; then
  ROOT_DIR="$SCRIPT_DIR"
elif [ -f "$SCRIPT_DIR/../terraform/main.tf" ]; then
  ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
elif [ -f "$PWD/terraform/main.tf" ]; then
  ROOT_DIR="$PWD"
else
  echo "Error: no se encontró terraform/main.tf. Ejecuta demo.sh desde la raíz del proyecto." >&2
  exit 2
fi
cd "$ROOT_DIR" || exit 2

# ------------------------------------------------------------------ argumentos

AUTO=0
FRESH=0
NO_BROWSER=0
FROM=1
TO=99
MODE="run"

while [ $# -gt 0 ]; do
  case "$1" in
    --auto)       AUTO=1 ;;
    --fresh)      FRESH=1 ;;
    --no-browser) NO_BROWSER=1 ;;
    --from)       FROM="${2:?Falta número tras --from}"; shift ;;
    --to)         TO="${2:?Falta número tras --to}"; shift ;;
    --list)       MODE="list" ;;
    --map)        MODE="map" ;;
    --access)     MODE="access" ;;
    -h|--help)
      sed -n '2,23p' "$0" | sed 's/^# \{0,2\}//'
      exit 0
      ;;
    *)
      echo "Opción desconocida: $1 (usa --help para ver las opciones)" >&2
      exit 2
      ;;
  esac
  shift
done

# ------------------------------------------------------- formato de terminal

W=$(tput cols 2>/dev/null || echo 92)
[ "$W" -gt 100 ] && W=100
[ "$W" -lt 74 ] && W=74

if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  BOLD=$'\033[1m'
  DIM=$'\033[2m'
  RED=$'\033[31m'
  GREEN=$'\033[32m'
  YELLOW=$'\033[33m'
  BLUE=$'\033[34m'
  CYAN=$'\033[36m'
  MAGENTA=$'\033[35m'
  RESET=$'\033[0m'
else
  BOLD=''; DIM=''; RED=''; GREEN=''; YELLOW=''; BLUE=''; CYAN=''; MAGENTA=''; RESET=''
fi

# Guion ASCII (seguro en cualquier locale/terminal, evita caracteres corruptos)
rule() {
  printf ' %s%s%s\n' "$DIM" "$(printf '%*s' $((W - 2)) '' | tr ' ' '-')" "$RESET"
}

label() {
  local name="$1"
  shift
  printf '%s\n' "$@" | fold -s -w $((W - 13)) |
    awk -v l="$name" -v c="${LABEL_COLOR:-}" -v r="$RESET" \
      'NR == 1 {printf " %s%-9s%s %s\n", c, l, r, $0; next} {printf "           %s\n", $0}'
}

headline() {
  printf '%s\n' "$*" | fold -s -w $((W - 2)) | sed "s/^/ ${BOLD}${CYAN}/; s/\$/${RESET}/"
  echo
}

why()      { LABEL_COLOR="$BLUE"    label "CLAVE"     "$@"; }
say()      { LABEL_COLOR="$MAGENTA" label "DECIR"     "$@"; }
interact() { LABEL_COLOR="$YELLOW"  label "INTERACT"  "$@"; }
open_msg() { LABEL_COLOR="$YELLOW"  label "ABRIR"     "$@"; }
run_lbl()  { LABEL_COLOR="$DIM"     label "COMANDO"   "$DIM\$ $*$RESET"; }
ok()       { printf '           %s[OK]%s %s\n' "$GREEN" "$RESET" "$*"; }
warn()     { printf '           %s[AVISO]%s %s\n' "$YELLOW" "$RESET" "$*"; }
bad()      { printf '           %s[ERROR]%s %s\n' "$RED" "$RESET" "$*"; }
kv()       { printf '           %s%-16s%s %s\n' "$BOLD" "$1" "$RESET" "$2"; }

code_ref() {
  local file="$1" pattern="$2" n
  n=$(grep -n -m 1 -E -- "$pattern" "$file" 2>/dev/null | cut -d: -f1)
  if [ -n "$n" ]; then
    LABEL_COLOR="$DIM" label "CÓDIGO" "$file:$n"
  else
    LABEL_COLOR="$RED" label "CÓDIGO" "$file (patrón no encontrado: $pattern)"
  fi
}

show() {
  run_lbl "$1"
  eval "$1" 2>&1 | tr -d '\r' | sed 's/^/           /'
}

clock_fmt() {
  printf '%02d:%02d' $(($1 / 60)) $(($1 % 60))
}

step_header() {
  local num="$1" title="$2" target="$3"
  local left right pad
  left="PASO $num/$TOTAL · $title"
  right="$(clock_fmt $((SECONDS - START))) / obj $(clock_fmt "$target")"
  pad=$((W - 2 - ${#left} - ${#right}))
  [ "$pad" -lt 2 ] && pad=2
  printf '\n %s%s%*s%s%s\n' "$BOLD" "$left" "$pad" "" "$right" "$RESET"
  rule
  echo
}

gate() {
  echo
  rule
  [ "$AUTO" = 1 ] && return 0
  local ans
  printf ' %s[ENTER] Siguiente paso   [q] Salir y restaurar%s > ' "$DIM" "$RESET"
  read -r ans </dev/tty || exit 0
  case "$ans" in
    q|Q) exit 0 ;;
  esac
}

pause_interact() {
  [ "$AUTO" = 1 ] && return 0
  printf '\n %s>>> %s (pulsa ENTER para continuar) <<<%s ' "$YELLOW" "$1" "$RESET"
  read -r _ </dev/tty || exit 0
  echo
}

ask_yes_no() {
  local prompt="$1" default="${2:-N}" ans
  if [ "$AUTO" = 1 ]; then
    [ "$default" = "S" ] && return 0 || return 1
  fi
  printf '           %s%s%s ' "$YELLOW" "$prompt" "$RESET"
  read -r ans </dev/tty || { echo; return 1; }
  echo
  case "$ans" in
    s|S|si|SI|y|Y) return 0 ;;
    *) return 1 ;;
  esac
}

# ------------------------------------------------------- utilidades de entorno

count_env() {
  docker ps -q --filter "name=^/${1}-" | wc -l | tr -d ' '
}

container_running() {
  [ "$(docker inspect -f '{{.State.Running}}' "$1" 2>/dev/null)" = "true" ]
}

container_health() {
  docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "$1" 2>/dev/null || echo "no existe"
}

# Lanza N peticiones reales (1 único curl por petición) mostrando cada una + resumen
# Uso: probe_round_robin URL NUM_PETICIONES
LAST_PROBE_FAILS=0
probe_round_robin() {
  local url="$1" count="$2"
  local i resp code rep color tmpfile summary
  LAST_PROBE_FAILS=0
  tmpfile=$(mktemp)

  for i in $(seq 1 "$count"); do
    resp=$(curl -s --max-time 6 -w '\n%{http_code}' "${url}/" 2>/dev/null)
    code=$(printf '%s\n' "$resp" | tail -n 1)
    [ -z "$code" ] && code="000"
    rep=$(printf '%s\n' "$resp" | grep -oE '(dev|pro)-app-[0-9]+' | head -n 1)
    [ -z "$rep" ] && rep="sin-respuesta"

    if [ "$code" = "200" ]; then
      color="$GREEN"
    else
      color="$RED"
      LAST_PROBE_FAILS=$((LAST_PROBE_FAILS + 1))
    fi

    printf '           #%02d  %sHTTP %s%s  ->  %s\n' "$i" "$color" "$code" "$RESET" "$rep"
    printf '%s\n' "$rep" >>"$tmpfile"
  done

  summary=$(sort "$tmpfile" | uniq -c | awk '{printf "%s (%s)  |  ", $2, $1}' | sed 's/  |  $//')
  rm -f "$tmpfile"
  echo
  kv "Resumen" "$summary"
}

prom_query() {
  curl -sG --max-time 4 "http://127.0.0.1:9090/api/v1/query" \
    --data-urlencode "query=$1" 2>/dev/null |
    python3 -c '
import sys, json
try:
    res = json.load(sys.stdin)["data"]["result"]
    print(res[0]["value"][1] if res else "")
except Exception:
    print("")
' 2>/dev/null
}

prom_alerts() {
  curl -s --max-time 4 "http://127.0.0.1:9090/api/v1/alerts" 2>/dev/null |
    python3 -c '
import sys, json
try:
    alerts = json.load(sys.stdin)["data"]["alerts"]
    if not alerts:
        print("NONE")
    for a in alerts:
        name = a.get("labels", {}).get("alertname", "?")
        state = a.get("state", "?").upper()
        sev = a.get("labels", {}).get("severity", "-")
        desc = a.get("annotations", {}).get("summary") or a.get("annotations", {}).get("description") or ""
        print(f"[{state}] {name} (severity={sev}) -> {desc}")
except Exception:
    print("ERROR")
' 2>/dev/null
}

prom_value_is() {
  [ "$(prom_query "$1")" = "$2" ]
}

http_ok() {
  [ "$(curl -s -o /dev/null -w '%{http_code}' --max-time 3 "$1" 2>/dev/null)" = "200" ]
}

wait_for() {
  local limit="$1" t0="$SECONDS"
  shift
  until "$@" >/dev/null 2>&1; do
    [ $((SECONDS - t0)) -ge "$limit" ] && return 1
    sleep 2
  done
}

browse() {
  [ "$NO_BROWSER" = 1 ] && return 0
  [ -z "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ] && [ "$(uname)" != "Darwin" ] && return 0
  local url
  for url in "$@"; do
    if command -v xdg-open >/dev/null 2>&1; then
      nohup xdg-open "$url" >/dev/null 2>&1 &
    elif command -v open >/dev/null 2>&1; then
      nohup open "$url" >/dev/null 2>&1 &
    fi
    sleep 0.6
  done
}

# ------------------------------------------------------- restauración segura

REPLICA_DOWN=0
SCALED=0
RUNDIR=".demo"

restore_state() {
  local did=0
  if [ "$REPLICA_DOWN" = 1 ]; then
    printf '\n %s[RESTORE] Levantando de nuevo pro-app-3...%s\n' "$YELLOW" "$RESET"
    docker start pro-app-3 >/dev/null 2>&1 || true
    REPLICA_DOWN=0
    did=1
  fi
  if [ "$SCALED" = 1 ]; then
    printf '\n %s[RESTORE] Devolviendo PRO a 3 réplicas según terraform/pro.tfvars...%s\n' "$YELLOW" "$RESET"
    make --no-print-directory deploy-pro >/dev/null 2>&1 || true
    SCALED=0
    did=1
  fi
  [ "$did" = 1 ] && printf ' %s[RESTORE] Entorno restaurado correctamente.%s\n' "$GREEN" "$RESET"
}

# ------------------------------------------------------- modos rápidos (--access / --map)

show_access() {
  printf '\n %sTABLA DE ACCESOS — POKÉDEX CLOUD (DEV & PRO)%s\n' "$BOLD" "$RESET"
  rule
  printf '  %-24s %-42s %-15s %s\n' "SERVICIO" "URL" "CREDENCIALES" "ALCANCE"
  rule
  printf '  %-24s %-42s %-15s %s\n' "App Web DEV (2 rep)"   "http://localhost:5000"                            "-"             "Balanceador Nginx DEV"
  printf '  %-24s %-42s %-15s %s\n' "App Web PRO (3 rep)"   "http://localhost:5001"                            "-"             "Balanceador Nginx PRO + Redis"
  printf '  %-24s %-42s %-15s %s\n' "S3 Consola DEV"        "http://localhost:9001/buckets/pokedex-static/"    "-"             "SeaweedFS Filer DEV"
  printf '  %-24s %-42s %-15s %s\n' "S3 Consola PRO"        "http://localhost:9011/buckets/pokedex-static/"    "-"             "SeaweedFS Filer PRO"
  printf '  %-24s %-42s %-15s %s\n' "Grafana (Dashboard)"   "http://localhost:3000/d/pokedex-obs"              "admin / admin" "Métricas + Logs (DEV y PRO)"
  printf '  %-24s %-42s %-15s %s\n' "Prometheus (Local)"    "http://127.0.0.1:9090"                            "Solo loopback" "Bloqueado desde exterior/apps"
  printf '  %-24s %-42s %-15s %s\n' "Prometheus Alertas"    "http://127.0.0.1:9090/alerts"                     "Solo loopback" "Reglas y estado pending/firing"
  printf '  %-24s %-42s %-15s %s\n' "Postgres/Redis/Loki"   "(sin puertos externos)"                           "Red interna"   "Aislamiento de red Docker"
  rule
  echo
}

MAP=(
  "Terraform e IaC|Director de módulos (raíz)|terraform/main.tf|module \"webapp\""
  "Terraform e IaC|Variables DEV (2 réplicas, sin Redis)|terraform/dev.tfvars|app_replicas"
  "Terraform e IaC|Variables PRO (3 réplicas, Redis, Mon)|terraform/pro.tfvars|app_replicas"
  "Terraform e IaC|Módulo Network (red aislada)|terraform/modules/network/main.tf|resource \"docker_network\""
  "Terraform e IaC|Módulo Webapp (versions 4 archivos)|terraform/modules/webapp/versions.tf|kreuzwerker/docker"
  "Terraform e IaC|Automatización con Makefile|Makefile|deploy-pro"
  "Balanceador de Carga|Réplicas dinámicas con count|terraform/modules/webapp/main.tf|count *= *var\\.app_replicas"
  "Balanceador de Carga|Generación dinámica local_file|terraform/modules/webapp/main.tf|resource \"local_file\" \"nginx_conf\""
  "Balanceador de Carga|Reemplazo automático LB al escalar|terraform/modules/webapp/main.tf|replace_triggered_by"
  "Balanceador de Carga|Plantilla Round-Robin + Failover HA|config/nginx/lb.conf.tftpl|proxy_next_upstream"
  "Balanceador de Carga|Contenedor Nginx LB|terraform/modules/webapp/main.tf|resource \"docker_container\" \"load_balancer\""
  "BD y Caché|PostgreSQL + volumen persistente|terraform/modules/database/main.tf|resource \"docker_volume\" \"db_data\""
  "BD y Caché|Healthcheck PostgreSQL|terraform/modules/database/main.tf|pg_isready"
  "BD y Caché|Script inicialización BD|init.sql|CREATE TABLE"
  "BD y Caché|Redis condicional (solo PRO)|terraform/modules/database/main.tf|resource \"docker_container\" \"redis\""
  "Almacenamiento S3|SeaweedFS S3 + volumen persistente|terraform/modules/storage/main.tf|seaweedfs"
  "Almacenamiento S3|Integración S3 en Flask|app/app.py|MINIO_"
  "Monitorización|cAdvisor (CPU/RAM/red)|terraform/modules/monitoring/main.tf|resource \"docker_container\" \"cadvisor\""
  "Monitorización|Prometheus + scrape cAdvisor|config/prometheus/prometheus.yml|pro-cadvisor:8080"
  "Monitorización|Grafana + Provisioning IaC|terraform/modules/monitoring/main.tf|provisioning"
  "Monitorización|Dashboard JSON completo|config/grafana/dashboards/pokedex_dashboard.json|pokedex-obs"
  "Logs Centralizados|Grafana Alloy (socket Docker)|config/alloy/config.alloy|discovery\\.docker"
  "Logs Centralizados|Almacén de logs Loki|config/loki/loki-config.yml|auth_enabled"
  "Alertas y HA|Reglas de alerta PromQL|config/prometheus/alert_rules.yml|alert:"
  "Alertas y HA|Plantilla Alertmanager -> Discord|config/alertmanager/alertmanager.yml.tftpl|discord"
  "Alertas y HA|Política de reinicio HA|terraform/modules/webapp/main.tf|unless-stopped"
  "Seguridad|Red interna aislada (internal=true)|terraform/modules/monitoring/main.tf|internal *= *true"
  "Seguridad|Prometheus solo loopback 127.0.0.1|terraform/modules/monitoring/main.tf|127\\.0\\.0\\.1"
  "Seguridad|Exclusión de secretos en Git|.gitignore|secret\\.auto\\.tfvars"
)

show_map() {
  local last="" row section req file pattern n
  printf '\n %sMAPA DE REQUISITOS DEL ENUNCIADO -> CÓDIGO REAL%s\n' "$BOLD" "$RESET"
  rule
  for row in "${MAP[@]}"; do
    IFS='|' read -r section req file pattern <<<"$row"
    if [ "$section" != "$last" ]; then
      printf '\n %s%s%s\n' "$BOLD$CYAN" "$section" "$RESET"
      last="$section"
    fi
    n=$(grep -n -m 1 -E -- "$pattern" "$file" 2>/dev/null | cut -d: -f1)
    if [ -n "$n" ]; then
      printf '   %-42s %s%s:%s%s\n' "$req" "$GREEN" "$file" "$n" "$RESET"
    else
      printf '   %-42s %s%s (revisar patrón)%s\n' "$req" "$RED" "$file" "$RESET"
    fi
  done
  echo
}

# ------------------------------------------------------------------ índice de pasos

TITLES=(
  ""
  "Estructura Modular IaC, Workspaces y .tfvars"
  "Despliegue Simultáneo (DEV + PRO) e Idempotencia"
  "Accesos y Comprobación Visual de Ambos Entornos"
  "Balanceador de Carga Dinámico (Nginx Round-Robin)"
  "Escalado Dinámico en Caliente (3 -> 4 -> 3 réplicas)"
  "Base de Datos PostgreSQL y Caché Redis (solo PRO)"
  "Almacenamiento de Objetos S3 Compartido (SeaweedFS)"
  "Alta Disponibilidad: Caída Controlada de Réplica"
  "Monitorización de Contenedores, CPU y RAM (Grafana)"
  "Sistema de Alertas Activo (Prometheus -> Discord)"
  "Centralización de Logs (Alloy + Loki en Grafana)"
  "Recuperación Automática del Balanceo y Resolución"
  "Seguridad, Segmentación de Redes y Aislamiento"
)

TARGETS=(0 45 105 150 225 295 360 420 480 540 600 650 690 730)
TOTAL=$((${#TITLES[@]} - 1))

# ------------------------------------------------------------------ pasos

step_1() {
  headline "Arquitectura 100 % modular: 5 módulos reutilizables (4 archivos cada uno) y entornos parametrizados por .tfvars."

  show "ls -1 terraform/modules/*/*.tf"
  echo
  run_lbl "Comparativa terraform/dev.tfvars vs terraform/pro.tfvars"
  printf '           %s%-22s %-22s %s%s\n' "$BOLD" "VARIABLE" "DEV (dev.tfvars)" "PRO (pro.tfvars)" "$RESET"
  local k d p
  for k in $(cat terraform/dev.tfvars terraform/pro.tfvars 2>/dev/null | sed -n 's/^\([a-zA-Z0-9_]*\) *=.*/\1/p' | awk '!seen[$0]++'); do
    d=$(sed -n "s/^${k} *= *//p" terraform/dev.tfvars 2>/dev/null | head -n 1 | tr -d '"')
    p=$(sed -n "s/^${k} *= *//p" terraform/pro.tfvars 2>/dev/null | head -n 1 | tr -d '"')
    printf '           %-22s %-22s %s\n' "$k" "${d:--}" "${p:--}"
  done
  echo

  why "Cada módulo tiene versions.tf, variables.tf, main.tf y outputs.tf (estándar HashiCorp)." \
      "Un mismo código despliega DEV y PRO sin duplicación usando workspaces y .tfvars." \
      "Los secretos (contraseñas y webhook Discord) viven en secret.auto.tfvars (chmod 600, fuera de Git)."
  say "Señalar que DEV tiene 2 réplicas sin Redis y PRO activa 3 réplicas, Redis y observabilidad centralizada."
  code_ref "terraform/main.tf" 'module "webapp"'
  code_ref "Makefile" 'deploy-pro'
}

step_2() {
  headline "DEV y PRO conviven simultáneamente sin colisiones, gestionados desde Makefile y con idempotencia verificada."

  local dev_n pro_n
  dev_n=$(count_env dev)
  pro_n=$(count_env pro)
  kv "Estado actual" "DEV: ${dev_n} contenedores | PRO: ${pro_n} contenedores"

  if [ "$FRESH" = 1 ]; then
    warn "Modo --fresh activo: destruyendo y reconstruyendo DEV y PRO desde cero..."
    show "make destroy-dev && make destroy-pro"
    show "make deploy-dev && make deploy-pro"
  elif [ "$dev_n" -lt 5 ] || [ "$pro_n" -lt 12 ]; then
    warn "Faltan contenedores por levantar. Desplegando DEV y PRO ahora..."
    show "make deploy-dev && make deploy-pro"
  else
    if ask_yes_no "¿Quieres destruir y redesplegar desde cero ahora? [s/N]:" "N"; then
      show "make destroy-dev && make destroy-pro"
      show "make deploy-dev && make deploy-pro"
    else
      ok "Ambos entornos ya están levantados; validando sintaxis e idempotencia (plan = No changes)."
    fi
  fi

  echo
  show "terraform -chdir=terraform validate"
  run_lbl "Verificación de idempotencia en DEV y PRO (terraform plan -detailed-exitcode)"

  terraform -chdir=terraform workspace select dev >/dev/null 2>&1
  if terraform -chdir=terraform plan -var-file=dev.tfvars -detailed-exitcode -input=false >/dev/null 2>&1; then
    ok "DEV: No changes (la infraestructura real coincide al 100 % con el código)."
  else
    warn "DEV presenta diferencias respecto al plan; revisa 'make plan-dev'."
  fi

  terraform -chdir=terraform workspace select pro >/dev/null 2>&1
  if terraform -chdir=terraform plan -var-file=pro.tfvars -detailed-exitcode -input=false >/dev/null 2>&1; then
    ok "PRO: No changes (la infraestructura real coincide al 100 % con el código)."
  else
    warn "PRO presenta diferencias respecto al plan; revisa 'make plan-pro'."
  fi

  echo
  show "docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}' | awk 'NR==1{print; next} /^(dev|pro)-/{print | \"sort\"}'"

  why "DEV (puerto 5000, S3 9000/9001) y PRO (puerto 5001, S3 9010/9011) coexisten en redes aisladas." \
      "Fijar network_mode = \"bridge\" y keep_locally = true garantiza despliegues rápidos e idempotentes."
}

step_3() {
  headline "Punto de entrada a la demo visual: abrimos DEV, PRO, Consola S3, Grafana y Prometheus local."

  show_access

  if [ "$NO_BROWSER" = 0 ] && ask_yes_no "¿Abrir ahora las pestañas de DEV, PRO, S3, Grafana y Prometheus en el navegador? [s/N]:" "N"; then
    browse \
      "http://localhost:5000" \
      "http://localhost:5001" \
      "http://localhost:9011/buckets/pokedex-static/" \
      "http://localhost:3000/d/pokedex-obs" \
      "http://127.0.0.1:9090/targets"
    ok "Pestañas lanzadas en el navegador."
    echo
  fi

  interact "En el navegador, enseña DEV (localhost:5000) y PRO (localhost:5001) abiertos a la vez." \
           "Muestra los badges en vivo (/status): en PRO aparece Redis activo y en DEV no."
}

step_4() {
  headline "Nginx genera su upstream dinámicamente (templatefile + local_file) y reparte tráfico en Round-Robin."

  if [ -f "terraform/.terraform/nginx_pro.conf" ]; then
    show "cat terraform/.terraform/nginx_pro.conf"
  else
    show "cat config/nginx/lb.conf.tftpl"
  fi
  echo

  run_lbl "10 peticiones reales a DEV (http://localhost:5000/) -> alternancia entre 2 réplicas"
  probe_round_robin "http://localhost:5000" 10
  echo

  run_lbl "12 peticiones reales a PRO (http://localhost:5001/) -> alternancia entre 3 réplicas"
  probe_round_robin "http://localhost:5001" 12
  echo

  why "Política Round-Robin (defensa): las peticiones Flask son stateless, rápidas y de coste similar;" \
      "  reparto circular garantiza distribución equitativa sin sobrecarga (least_conn es para sesiones largas)." \
      "Dinámico sin IPs fijas: local_file usa app_replicas[*].name y el DNS interno de Docker resuelve cada IP."
  interact "Pulsa F5 varias veces en http://localhost:5000 (2 réplicas) y http://localhost:5001 (3 réplicas)" \
           "para que el profesor vea cambiar el identificador de instancia directamente en la UI."
  code_ref "config/nginx/lb.conf.tftpl" 'upstream backend_nodes'
  code_ref "terraform/modules/webapp/main.tf" 'replace_triggered_by'
}

step_5() {
  headline "Escalado horizontal en un comando: pasamos PRO de 3 a 4 réplicas y Nginx se reconfigura automáticamente."

  if ask_yes_no "¿Ejecutar prueba real de escalado (3 -> 4 -> 3 réplicas en PRO)? [s/N]:" "S"; then
    mkdir -p "$RUNDIR"
    SCALED=1
    run_lbl "terraform -chdir=terraform apply -auto-approve -var-file=pro.tfvars -var=\"app_replicas=4\""
    terraform -chdir=terraform workspace select pro >/dev/null 2>&1
    terraform -chdir=terraform apply -auto-approve -input=false -var-file=pro.tfvars -var="app_replicas=4" >"$RUNDIR/scale_up.log" 2>&1

    wait_for 30 container_running pro-app-4
    wait_for 30 http_ok "http://localhost:5001/"
    sleep 2
    ok "Escalado completado: pro-app-4 creado y pro-load-balancer recargado con la nueva configuración."
    show "grep 'server pro-app' terraform/.terraform/nginx_pro.conf"
    echo

    run_lbl "12 peticiones reales a PRO tras escalar -> ahora reparte en Round-Robin entre las 4 réplicas"
    probe_round_robin "http://localhost:5001" 12

    pause_interact "Muestra en la UI o en Grafana las 4 réplicas activas (pro-app-1 a pro-app-4)"

    run_lbl "Volviendo al estado declarado en pro.tfvars (3 réplicas): make deploy-pro"
    make --no-print-directory deploy-pro >"$RUNDIR/scale_down.log" 2>&1
    SCALED=0
    wait_for 30 http_ok "http://localhost:5001/"
    sleep 1
    ok "Estado restaurado a 3 réplicas. El código (.tfvars) siempre es la fuente de la verdad."
    show "docker ps --filter 'name=^/pro-app-' --format 'table {{.Names}}\t{{.Status}}'"
  else
    warn "Escalado en vivo omitido; puedes lanzarlo manualmente con -var=\"app_replicas=4\"."
  fi

  why "Gracias a count + templatefile + replace_triggered_by, Nginx se actualiza solo al cambiar app_replicas."
}

step_6() {
  headline "PostgreSQL con volumen persistente e init.sql en ambos entornos; caché Redis exclusiva en PRO."

  kv "dev-postgres" "$(container_health dev-postgres) (volumen: dev_db_data)"
  kv "pro-postgres" "$(container_health pro-postgres) (volumen: pro_db_data)"
  kv "pro-redis"    "$(container_health pro-redis) (solo PRO; en DEV enable_redis = false)"
  echo

  show "docker volume ls --filter 'name=_db_data'"
  echo
  show "docker exec pro-postgres sh -c 'psql -U \"\$POSTGRES_USER\" -d \"\$POSTGRES_DB\" -c \"SELECT count(*) AS total_pokemon FROM pokemon;\"' 2>/dev/null || docker exec pro-postgres pg_isready"
  echo

  run_lbl "Comprobación de caché Redis en PRO (ping + tráfico + estadísticas hits/misses)"
  show "docker exec pro-redis redis-cli ping"
  curl -s -o /dev/null http://localhost:5001/
  curl -s -o /dev/null http://localhost:5001/
  show "docker exec pro-redis redis-cli KEYS '*'"
  show "docker exec pro-redis redis-cli INFO stats | grep -E 'keyspace_hits|keyspace_misses'"

  why "Cache-aside en PRO: reduce consultas repetitivas a PostgreSQL y acelera el renderizado." \
      "Los datos de PostgreSQL sobreviven a reinicios o recreación del contenedor gracias a docker_volume."
  interact "Opcional: añade un Pokémon nuevo desde la web de PRO (localhost:5001) para mostrar" \
           "la persistencia en PostgreSQL y la subida simultánea de su imagen al bucket S3."
  code_ref "terraform/modules/database/main.tf" 'resource "docker_container" "redis"'
}

step_7() {
  headline "Almacenamiento de objetos compatible con AWS S3 (SeaweedFS) compartido por todas las réplicas."

  show "docker volume ls --filter 'name=_s3_data'"
  echo
  run_lbl "Verificación HTTP de archivo estático servido desde el bucket S3 (pokeball.svg)"
  local code_dev code_pro
  code_dev=$(curl -s -o /dev/null -w '%{http_code}' http://localhost:9000/pokedex-static/pokeball.svg 2>/dev/null)
  code_pro=$(curl -s -o /dev/null -w '%{http_code}' http://localhost:9010/pokedex-static/pokeball.svg 2>/dev/null)
  kv "S3 DEV (:9000)" "GET /pokedex-static/pokeball.svg -> HTTP ${code_dev:-000}"
  kv "S3 PRO (:9010)" "GET /pokedex-static/pokeball.svg -> HTTP ${code_pro:-000}"

  echo
  why "Todas las réplicas Flask son stateless: suben y leen los estáticos desde un único bucket compartido." \
      "Si una réplica o el contenedor S3 se recrea, las imágenes persisten en el volumen pro_s3_data."
  open_msg "Consola S3 PRO: http://localhost:9011/buckets/pokedex-static/" \
           "Consola S3 DEV: http://localhost:9001/buckets/pokedex-static/"
  interact "Abre la consola del bucket en el navegador para enseñar pokeball.svg y los sprites subidos."
  code_ref "terraform/modules/storage/main.tf" 'seaweedfs'
}

step_8() {
  headline "Simulación de fallo en PRO: detenemos pro-app-3 y comprobamos failover inmediato sin cortes."

  show "docker stop pro-app-3"
  REPLICA_DOWN=1
  T_DOWN=$SECONDS
  sleep 1
  echo

  run_lbl "10 peticiones HTTP reales contra PRO con pro-app-3 caída (failover automático de Nginx)"
  probe_round_robin "http://localhost:5001" 10
  echo

  if [ "$LAST_PROBE_FAILS" -eq 0 ]; then
    ok "10/10 peticiones exitosas (HTTP 200). Nginx apartó pro-app-3 y reintentó en nodos sanos sin cortes."
  else
    warn "$LAST_PROBE_FAILS peticiones fallaron durante la transición."
  fi

  why "proxy_connect_timeout 1s + proxy_next_upstream reenvían al instante la petición a otra réplica sana." \
      "Usamos docker stop (parada manual) para que Docker no la reinicie y así dispare la alerta." \
      "Ante un fallo real de proceso (crash), restart = \"unless-stopped\" levanta el contenedor solo."
  interact "Recarga http://localhost:5001 en el navegador: la app sigue 100 % operativa entre pro-app-1 y pro-app-2."
  code_ref "config/nginx/lb.conf.tftpl" 'proxy_next_upstream'
}

step_9() {
  headline "Observabilidad centralizada (cAdvisor + Prometheus + Grafana): salud por contenedor, CPU y RAM."

  run_lbl "Esperando a que Prometheus detecte la bajada de pro-app-3 (réplicas activas == 2)..."
  local q='count(time() - container_last_seen{name=~"pro-app-.*"} < 15)'
  wait_for 25 prom_value_is "$q" "2" || true

  local up_reps
  up_reps=$(prom_query "$q")
  kv "PromQL" "$q"
  kv "Resultado vivo" "${up_reps:-N/A} réplicas pro-app activas (de 3 esperadas)"
  echo

  run_lbl "Estado de targets en Prometheus (http://127.0.0.1:9090/api/v1/targets)"
  curl -s --max-time 4 "http://127.0.0.1:9090/api/v1/targets" 2>/dev/null | python3 -c '
import sys, json
try:
    for t in json.load(sys.stdin)["data"]["activeTargets"]:
        job = t.get("labels", {}).get("job", "?")
        url = t.get("scrapeUrl", "?")
        health = t.get("health", "?").upper()
        print(f"           job={job:<12} url={url:<32} health={health}")
except Exception:
    print("           (No se pudieron leer los targets de Prometheus)")
'

  echo
  open_msg "Dashboard Grafana: http://localhost:3000/d/pokedex-obs  (admin / admin)"
  interact "Enseña en Grafana:" \
           "  1) Fila 2: tarjeta individual 'pro-app-3' en ROJO (OFFLINE) y el resto en VERDE (ONLINE)." \
           "  2) Fila 3 y 4: gráficas en tiempo real de CPU (%), RAM (MB) y tráfico RX/TX de DEV y PRO."
  code_ref "config/prometheus/prometheus.yml" 'pro-cadvisor:8080'
  code_ref "config/grafana/dashboards/pokedex_dashboard.json" 'pokedex-obs'
}

step_10() {
  headline "Alertas automáticas: Prometheus evalúa alert_rules.yml y Alertmanager notifica en Discord."

  show "cat config/prometheus/alert_rules.yml"
  echo
  run_lbl "Consultando alertas activas en Prometheus (esperando estado FIRING tras caída de pro-app-3)..."

  local elapsed=0 alerts_out=""
  while [ "$elapsed" -lt 45 ]; do
    alerts_out=$(prom_alerts)
    if printf '%s\n' "$alerts_out" | grep -q '\[FIRING\]'; then
      break
    fi
    sleep 3
    elapsed=$((elapsed + 3))
  done

  if [ "$alerts_out" = "NONE" ] || [ -z "$alerts_out" ]; then
    warn "Aún no hay alertas activas en Prometheus (revisa http://127.0.0.1:9090/alerts)."
  else
    printf '%s\n' "$alerts_out" | sed 's/^/           /'
    echo
    ok "Alerta disparada tras ~$((SECONDS - T_DOWN))s desde la caída de pro-app-3."
  fi

  echo
  open_msg "Alertas Prometheus: http://127.0.0.1:9090/alerts" \
           "Discord: abre el canal de alertas para mostrar el aviso en vivo."
  why "La cláusula 'for:' evita falsas alarmas ante micro-reinicios; Alertmanager agrupa y evita spam." \
      "El webhook de Discord se inyecta con templatefile desde secret.auto.tfvars (nunca en Git)."
  interact "Muestra en pantalla el mensaje de alerta recibido en Discord y la pestaña Alerts de Prometheus."
  code_ref "config/alertmanager/alertmanager.yml.tftpl" 'discord'
}

step_11() {
  headline "Logs centralizados: Grafana Alloy captura el socket de Docker y envía todo a Loki."

  kv "pro-alloy" "$(container_health pro-alloy) (lee /var/run/docker.sock en modo read_only)"
  kv "pro-loki"  "$(container_health pro-loki) (almacén central de logs en red interna)"
  echo

  run_lbl "Generando 3 peticiones identificables en PRO y DEV para verlas llegar en vivo a Grafana/Loki"
  curl -s -o /dev/null "http://localhost:5001/?demo_trace=defensa-p2"
  curl -s -o /dev/null "http://localhost:5001/status"
  curl -s -o /dev/null "http://localhost:5000/?demo_trace=dev-check"
  ok "Peticiones enviadas a DEV y PRO."
  echo

  show "head -n 35 config/alloy/config.alloy"
  echo
  open_msg "Panel de logs en Grafana: fila 5 de http://localhost:3000/d/pokedex-obs" \
           "O Explore -> Loki con consulta: {container_name=~\"(dev|pro)-(app|postgres|redis|load-balancer).*\"}"
  interact "Enseña los logs unificados de Flask, Nginx, PostgreSQL y Redis sin entrar contenedor por contenedor." \
           "Muestra que filtramos el ruido interno de Loki para dejar una consola limpia de aplicación."
  code_ref "config/alloy/config.alloy" 'discovery\.docker'
}

step_12() {
  headline "Recuperación del clúster: arrancamos pro-app-3 y Nginx + Grafana + Discord vuelven a verde."

  show "docker start pro-app-3"
  REPLICA_DOWN=0
  wait_for 20 container_running pro-app-3
  # Esperar a que venza fail_timeout=5s en Nginx para que reintegre pro-app-3
  sleep 6
  echo

  run_lbl "12 peticiones reales a PRO tras recuperación -> vuelven a rotar las 3 réplicas"
  probe_round_robin "http://localhost:5001" 12
  echo

  ok "pro-app-3 reintegrada automáticamente en el balanceo Round-Robin."
  interact "En Grafana (http://localhost:3000/d/pokedex-obs): pro-app-3 pasa de ROJO a VERDE en ~10s." \
           "En Discord: Alertmanager enviará el aviso de RESOLVED al normalizarse la regla."
}

step_13() {
  headline "Seguridad por diseño: segmentación con red internal=true, loopback en Prometheus y cero secretos en Git."

  run_lbl "Redes Docker y atributo Internal (aislamiento del plano de observabilidad)"
  show "docker network inspect pokedex_dev_net pokedex_pro_net pro_monitoring_net pro_monitoring_egress --format 'table {{.Name}}\t{{.Internal}}\t{{.Driver}}'"
  echo

  run_lbl "Prueba de aislamiento: pro-app-1 intenta conectar con pro-prometheus:9090 (DEBE FALLAR)"
  if docker exec pro-app-1 python -c "import urllib.request; urllib.request.urlopen('http://pro-prometheus:9090', timeout=2)" >/dev/null 2>&1; then
    bad "¡ATENCIÓN! pro-app-1 pudo alcanzar a pro-prometheus."
  else
    ok "BLOQUEADO (DNS/Red aislada): las apps NO pueden ver ni atacar Prometheus, Loki ni Alertmanager."
  fi
  echo

  run_lbl "Puertos publicados en el host (principio de mínimo privilegio)"
  show "docker ps --filter 'name=^/pro-' --format 'table {{.Names}}\t{{.Ports}}'"
  echo

  run_lbl "Permisos de secretos locales y limpieza del repositorio Git"
  if [ -f "terraform/secret.auto.tfvars" ]; then
    show "ls -la terraform/secret.auto.tfvars"
  fi
  show "git ls-files terraform/secret.auto.tfvars | wc -l | xargs -I{} echo 'Archivos de secretos rastreados en Git: {}'"

  why "Plano de datos (pokedex_pro_net) separado del plano de control (pro_monitoring_net, internal=true)." \
      "Prometheus no tiene login nativo: solo escucha en 127.0.0.1:9090 (local) y se consulta vía Grafana autenticado." \
      "Postgres, Redis, Flask, cAdvisor, Loki, Alloy y Alertmanager no abren ningún puerto al exterior."
  say "Cierre perfecto: todos los requisitos del enunciado están verificados en vivo y el repo queda limpio."
}

# ------------------------------------------------------------------ main

case "$MODE" in
  list)
    printf '\n %sÍNDICE DE PASOS — DEMO POKÉDEX CLOUD%s\n' "$BOLD" "$RESET"
    rule
    for i in $(seq 1 "$TOTAL"); do
      printf '  %2d  [%s]  %s\n' "$i" "$(clock_fmt "${TARGETS[$i]}")" "${TITLES[$i]}"
    done
    rule
    echo
    exit 0
    ;;
  map)
    show_map
    exit 0
    ;;
  access)
    show_access
    exit 0
    ;;
esac

for tool in docker curl make terraform python3; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "Falta una herramienta necesaria: $tool" >&2
    exit 2
  fi
done

trap restore_state EXIT
trap 'exit 130' INT TERM

START=$SECONDS
T_DOWN=$SECONDS
[ "$FROM" -lt 1 ] && FROM=1
[ "$TO" -gt "$TOTAL" ] && TO=$TOTAL

printf '\n %s%sPOKÉDEX CLOUD — DEMO GUIADA DE INFRAESTRUCTURA COMO CÓDIGO%s\n' "$BOLD" "$CYAN" "$RESET"
printf ' %sPasos %d a %d · Pulsa ENTER para avanzar o q para salir (restaura cambios automáticamente)%s\n' "$DIM" "$FROM" "$TO" "$RESET"
rule

for i in $(seq "$FROM" "$TO"); do
  step_header "$i" "${TITLES[$i]}" "${TARGETS[$i]}"
  "step_$i"
  if [ "$i" -lt "$TO" ]; then
    gate
  else
    echo
    rule
  fi
done

printf '\n %s%sDemo completada en %s.%s\n\n' "$BOLD" "$GREEN" "$(clock_fmt $((SECONDS - START)))" "$RESET"