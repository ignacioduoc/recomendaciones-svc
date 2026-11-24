#!/usr/bin/env bash
# Auditoría automatizada de cumplimiento de recomendaciones-svc (EP3 · IE5 e IE6).
#
# Uso:
#   audit/auditoria.sh secretos       Gitleaks: secretos en los commits revisados o en los archivos actuales
#   audit/auditoria.sh dependencias   Trivy: CVE críticos en las librerías que van dentro del jar
#   audit/auditoria.sh politicas      reglas de rama, acciones fijadas por SHA, permisos, excepciones,
#                                     archivos sensibles y Dependabot
#   audit/auditoria.sh todo           los tres controles, en ese orden, y el reporte final (uso local)
#   audit/auditoria.sh reporte        consolida los resultados de los tres controles (lo usa el pipeline)
#
# Código de salida:
#   0  cumple
#   1  no cumple una política: el pipeline se detiene
#   2  no se pudo auditar (falta una herramienta, la API no respondió, etc.): también detiene el pipeline
#
# Variables opcionales:
#   AUDITORIA_RANGO          rango de commits para Gitleaks, por ejemplo origin/develop..HEAD.
#                            Sin rango se revisan los archivos del commit actual.
#   AUDITORIA_ESTRICTA       true en el pipeline: un control que no se puede verificar cuenta como falla.
#   AUDITORIA_SALIDA         carpeta de reportes, relativa a la raíz del repo (por defecto reportes/auditoria).
#   AUDITORIA_OBJETIVO_SCA   carpeta con el jar a auditar (por defecto target).
#   GITLEAKS_IMAGE, TRIVY_IMAGE  imágenes Docker que se usan si gitleaks o trivy no están instalados.

set -uo pipefail

RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$RAIZ" || exit 2

SALIDA="${AUDITORIA_SALIDA:-reportes/auditoria}"
OBJETIVO_SCA="${AUDITORIA_OBJETIVO_SCA:-target}"
ESTRICTA="${AUDITORIA_ESTRICTA:-false}"
GITLEAKS_IMAGE="${GITLEAKS_IMAGE:-ghcr.io/gitleaks/gitleaks:v8.30.1}"
TRIVY_IMAGE="${TRIVY_IMAGE:-aquasec/trivy:0.70.0}"

# Políticas (cambiarlas aquí deja registro en el historial de Git)
SEVERIDAD_BLOQUEANTE="CRITICAL"
MAX_DIAS_EXCEPCION=180
RAMAS_PROTEGIDAS=(main develop)
REGLAS_OBLIGATORIAS=(pull_request required_status_checks non_fast_forward)
ECOSISTEMAS_DEPENDABOT=(maven docker github-actions)

mkdir -p "$SALIDA"

# ─────────────────────────────── utilidades ───────────────────────────────

log() { printf '%s\n' "$*" >&2; }

# Anotación visible en la ejecución de GitHub Actions (o mensaje normal en local)
anotar() {
  local nivel="$1" titulo="$2" mensaje="$3" ubicacion="${4:-}"
  if [[ -n "${GITHUB_ACTIONS:-}" ]]; then
    echo "::${nivel} ${ubicacion:+${ubicacion},}title=${titulo}::${mensaje}"
  else
    log "[${nivel}] ${titulo}: ${mensaje}"
  fi
}

codigo_de() {
  case "$1" in
    cumple) echo 0 ;;
    no_cumple) echo 1 ;;
    *) echo 2 ;;
  esac
}

guardar_resultado() {
  local control="$1" herramienta="$2" resultado="$3" resumen="$4"
  jq -n \
    --arg control "$control" --arg herramienta "$herramienta" \
    --arg resultado "$resultado" --arg resumen "$resumen" \
    --arg commit "${GITHUB_SHA:-$(git rev-parse HEAD 2>/dev/null || echo desconocido)}" \
    --arg fecha "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '{control: $control, herramienta: $herramienta, resultado: $resultado,
      resumen: $resumen, commit: $commit, fecha: $fecha}' > "$SALIDA/${control}.json"
}

docker_disponible() { command -v docker > /dev/null 2>&1 && docker info > /dev/null 2>&1; }

# YAML → JSON con el yq que haya instalado (el del runner de GitHub o el de Python)
yaml_a_json() {
  if yq --help 2>&1 | grep -q 'jq_filter'; then
    yq '.' "$1"
  elif command -v yq > /dev/null 2>&1; then
    yq -o=json '.' "$1"
  else
    python3 -c 'import json, sys, yaml; print(json.dumps(yaml.safe_load(open(sys.argv[1])), default=str))' "$1"
  fi
}

fecha_en_dias() {
  date -u -d "+$1 days" +%Y-%m-%d 2> /dev/null ||
    python3 -c "import datetime, sys; print((datetime.date.today() + datetime.timedelta(days=int(sys.argv[1]))).isoformat())" "$1"
}

# ─────────────────────────────── 1. secretos ───────────────────────────────

auditar_secretos() {
  local reporte="$SALIDA/gitleaks.json" md="$SALIDA/secretos.md"
  local -a gitleaks modo
  local herramienta alcance rc

  if command -v gitleaks > /dev/null 2>&1; then
    gitleaks=(gitleaks)
    herramienta="Gitleaks $(gitleaks version 2> /dev/null || echo)"
  elif docker_disponible; then
    gitleaks=(docker run --rm -u "$(id -u):$(id -g)" -v "$RAIZ:/repo" -w /repo "$GITLEAKS_IMAGE")
    herramienta="Gitleaks ${GITLEAKS_IMAGE##*:}"
  else
    guardar_resultado secretos "Gitleaks" error "No está instalado gitleaks ni Docker"
    anotar error "Auditoría de secretos" "Instala gitleaks o Docker para ejecutar este control"
    return 2
  fi

  if [[ -n "${AUDITORIA_RANGO:-}" ]] && git rev-list --quiet "${AUDITORIA_RANGO}" 2> /dev/null; then
    modo=(git "--log-opts=--no-merges ${AUDITORIA_RANGO}")
    alcance="commits ${AUDITORIA_RANGO} ($(git rev-list --no-merges --count "${AUDITORIA_RANGO}") commits)"
  else
    if [[ -n "${AUDITORIA_RANGO:-}" ]]; then
      anotar warning "Auditoría de secretos" "El rango ${AUDITORIA_RANGO} no existe en el clon; se revisan los archivos actuales"
    fi
    modo=(dir)
    alcance="archivos del commit actual"
  fi

  log "Gitleaks revisa: ${alcance}"
  rm -f "$reporte"
  "${gitleaks[@]}" "${modo[@]}" --no-banner --redact --config .gitleaks.toml \
    --report-format json --report-path "$reporte" .
  rc=$?

  if [[ ! -s "$reporte" ]] || ! jq -e 'type == "array"' "$reporte" > /dev/null 2>&1; then
    guardar_resultado secretos "$herramienta" error "Gitleaks terminó con código ${rc} sin generar reporte"
    anotar error "Auditoría de secretos" "Gitleaks terminó con código ${rc} sin generar reporte"
    return 2
  fi

  local hallazgos
  hallazgos=$(jq 'length' "$reporte")
  {
    echo "### Secretos en el código (Gitleaks)"
    echo ""
    echo "- Alcance: ${alcance}"
    echo "- Hallazgos: **${hallazgos}**"
    if ((hallazgos > 0)); then
      echo ""
      echo "| Regla | Archivo | Línea | Commit |"
      echo "|---|---|---|---|"
      jq -r '.[] | "| `\(.RuleID)` | `\(.File)` | \(.StartLine) | `\((.Commit // "")[0:7])` |"' "$reporte"
      echo ""
      echo "Los valores van ocultos (\`--redact\`). Hay que quitar el secreto del código, rotarlo y guardarlo en GitHub Secrets."
    fi
  } > "$md"

  if ((hallazgos > 0)); then
    jq -r '.[] | [.File, (.StartLine | tostring), .RuleID, .Description] | @tsv' "$reporte" |
      while IFS=$'\t' read -r archivo linea regla descripcion; do
        anotar error "Secreto detectado (${regla})" "${descripcion%.}. Quita el valor del código y rótalo." "file=${archivo},line=${linea}"
      done
    guardar_resultado secretos "$herramienta" no_cumple "${hallazgos} secreto(s) en ${alcance}"
    return 1
  fi
  if ((rc != 0)); then
    guardar_resultado secretos "$herramienta" error "Gitleaks terminó con código ${rc}"
    return 2
  fi
  guardar_resultado secretos "$herramienta" cumple "0 secretos en ${alcance}"
  return 0
}

# ───────────────────────────── 2. dependencias ─────────────────────────────

auditar_dependencias() {
  local reporte="$SALIDA/trivy-dependencias.json" md="$SALIDA/dependencias.md"
  local -a trivy
  local herramienta rc

  if ! compgen -G "${OBJETIVO_SCA}/*.jar" > /dev/null; then
    if command -v mvn > /dev/null 2>&1; then
      log "No hay un jar en ${OBJETIVO_SCA}/; se empaqueta con mvn -DskipTests package"
      mvn -B -ntp -q -DskipTests package || {
        guardar_resultado dependencias "Trivy" error "No se pudo empaquetar el jar"
        return 2
      }
    else
      guardar_resultado dependencias "Trivy" error "No hay jar en ${OBJETIVO_SCA}/ y Maven no está instalado"
      anotar error "Auditoría de dependencias" "Ejecuta 'mvn -DskipTests package' antes de este control"
      return 2
    fi
  fi

  if command -v trivy > /dev/null 2>&1; then
    trivy=(trivy)
    herramienta="Trivy $(trivy --version 2> /dev/null | awk 'NR == 1 { print $2 }')"
  elif docker_disponible; then
    mkdir -p "$HOME/.cache/trivy"
    trivy=(docker run --rm -u "$(id -u):$(id -g)" -v "$RAIZ:/src" -w /src
      -v "$HOME/.cache/trivy:/cache" -e TRIVY_CACHE_DIR=/cache "$TRIVY_IMAGE")
    herramienta="Trivy ${TRIVY_IMAGE##*:}"
  else
    guardar_resultado dependencias "Trivy" error "No está instalado trivy ni Docker"
    anotar error "Auditoría de dependencias" "Instala trivy o Docker para ejecutar este control"
    return 2
  fi

  # rootfs (y no fs): así Trivy lee las librerías reales dentro del jar, transitivas incluidas
  "${trivy[@]}" rootfs --quiet --scanners vuln --severity "$SEVERIDAD_BLOQUEANTE" \
    --ignorefile .trivyignore.yaml --format json --output "$reporte" --exit-code 0 "$OBJETIVO_SCA"
  rc=$?
  if ((rc != 0)) || ! jq -e '.' "$reporte" > /dev/null 2>&1; then
    guardar_resultado dependencias "$herramienta" error "Trivy terminó con código ${rc}"
    anotar error "Auditoría de dependencias" "Trivy terminó con código ${rc}"
    return 2
  fi

  local hallazgos
  hallazgos=$(jq '[.Results[]? | .Vulnerabilities[]?] | length' "$reporte")
  {
    echo "### CVE ${SEVERIDAD_BLOQUEANTE} en las librerías del jar (Trivy)"
    echo ""
    echo "- Objetivo: \`$(compgen -G "${OBJETIVO_SCA}/*.jar" | head -n 1)\`"
    echo "- Excepciones aplicadas: \`.trivyignore.yaml\` (las vigentes se revisan en el control de políticas)"
    echo "- Hallazgos: **${hallazgos}**"
    if ((hallazgos > 0)); then
      echo ""
      echo "| Librería | Versión | CVE | Corregido en |"
      echo "|---|---|---|---|"
      jq -r '.Results[]? | .Vulnerabilities[]? |
        "| `\(.PkgName)` | \(.InstalledVersion) | \(.VulnerabilityID) | \(.FixedVersion // "sin parche") |"' "$reporte" | sort -u
    fi
  } > "$md"

  if ((hallazgos > 0)); then
    jq -r '.Results[]? | .Vulnerabilities[]? |
      [.PkgName, .InstalledVersion, .VulnerabilityID, (.FixedVersion // "sin parche")] | @tsv' "$reporte" | sort -u |
      while IFS=$'\t' read -r paquete version cve corregido; do
        anotar error "CVE crítico en dependencia" "${paquete} ${version}: ${cve} (corregido en ${corregido})"
      done
    guardar_resultado dependencias "$herramienta" no_cumple "${hallazgos} CVE ${SEVERIDAD_BLOQUEANTE} sin excepción vigente"
    return 1
  fi
  guardar_resultado dependencias "$herramienta" cumple "0 CVE ${SEVERIDAD_BLOQUEANTE} sin excepción vigente"
  return 0
}

# ─────────────────────────────── 3. políticas ───────────────────────────────

FILAS_POLITICAS=()
DETALLES_POLITICAS=()
NO_CUMPLE=0
ERRORES=0
OMITIDOS=0

fila() {
  local politica="$1" resultado="$2" detalle="$3" icono
  case "$resultado" in
    cumple) icono="✅ Cumple" ;;
    no_cumple) icono="❌ No cumple"; NO_CUMPLE=$((NO_CUMPLE + 1)); anotar error "$politica" "$detalle" ;;
    omitido) icono="⚠️ No verificado"; OMITIDOS=$((OMITIDOS + 1)); anotar warning "$politica" "$detalle" ;;
    *) icono="❌ Error"; ERRORES=$((ERRORES + 1)); anotar error "$politica" "$detalle" ;;
  esac
  FILAS_POLITICAS+=("| ${politica} | ${icono} | ${detalle} |")
}

repo_actual() {
  if [[ -n "${GITHUB_REPOSITORY:-}" ]]; then
    echo "$GITHUB_REPOSITORY"
  else
    git remote get-url origin 2> /dev/null | sed -E 's#^(git@|https://)github\.com[:/]##; s#\.git$##'
  fi
}

# P1. main y develop exigen PR, checks en verde y prohíben force push (ruleset de GitHub)
verificar_ramas() {
  local repo api token rama respuesta faltan regla tipos aprobaciones checks
  local -a cabeceras
  repo="$(repo_actual)"
  api="${GITHUB_API_URL:-https://api.github.com}"
  token="${GITHUB_TOKEN:-${GH_TOKEN:-}}"
  cabeceras=(-H "Accept: application/vnd.github+json" -H "X-GitHub-Api-Version: 2022-11-28")
  [[ -n "$token" ]] && cabeceras+=(-H "Authorization: Bearer ${token}")

  for rama in "${RAMAS_PROTEGIDAS[@]}"; do
    if ! respuesta=$(curl -sS -f --max-time 20 "${cabeceras[@]}" "${api}/repos/${repo}/rules/branches/${rama}" 2>&1); then
      if [[ "$ESTRICTA" == "true" ]]; then
        fila "Rama \`${rama}\` protegida" error "No se pudo consultar la API de reglas: ${respuesta//$'\n'/ }"
      else
        fila "Rama \`${rama}\` protegida" omitido "Sin acceso a la API de GitHub desde aquí"
      fi
      continue
    fi
    if ! jq -e 'type == "array"' > /dev/null 2>&1 <<< "$respuesta"; then
      fila "Rama \`${rama}\` protegida" error "La API respondió algo que no es una lista de reglas"
      continue
    fi
    tipos=$(jq -r '[.[].type] | unique | join(" ")' <<< "$respuesta")
    faltan=()
    for regla in "${REGLAS_OBLIGATORIAS[@]}"; do
      [[ " ${tipos} " == *" ${regla} "* ]] || faltan+=("$regla")
    done
    aprobaciones=$(jq -r '[.[] | select(.type == "pull_request") | .parameters.required_approving_review_count] | max // 0' <<< "$respuesta")
    checks=$(jq -r '[.[] | select(.type == "required_status_checks") | .parameters.required_status_checks[].context] | unique | join(", ")' <<< "$respuesta")
    if ((${#faltan[@]} > 0)); then
      fila "Rama \`${rama}\` protegida" no_cumple "Faltan las reglas: ${faltan[*]}"
    else
      fila "Rama \`${rama}\` protegida" cumple "PR obligatorio (${aprobaciones} aprobación/es), checks requeridos y sin force push"
    fi
    DETALLES_POLITICAS+=("- \`${rama}\`: reglas activas \`${tipos:-ninguna}\`. Checks requeridos: ${checks:-ninguno}.")
  done
}

# P2. Toda acción externa va fijada por SHA completo (una etiqueta se puede reescribir)
verificar_acciones_sha() {
  local linea archivo resto numero contenido referencia
  local -a sin_fijar=()
  while IFS= read -r linea; do
    archivo="${linea%%:*}"
    resto="${linea#*:}"
    numero="${resto%%:*}"
    contenido="${resto#*:}"
    referencia=$(sed -E 's/^[[:space:]-]*uses:[[:space:]]*//; s/[[:space:]]+#.*$//; s/^["'\'']//; s/["'\'']$//' <<< "$contenido")
    [[ "$referencia" == ./* || "$referencia" == docker://* ]] && continue
    if [[ ! "$referencia" =~ @[0-9a-f]{40}$ ]]; then
      sin_fijar+=("\`${referencia}\` (${archivo}:${numero})")
      anotar error "Acción sin fijar por SHA" "${referencia}" "file=${archivo},line=${numero}"
    fi
  done < <(grep -nHE '^[[:space:]-]*uses:' .github/workflows/*.y*ml)

  if ((${#sin_fijar[@]} > 0)); then
    NO_CUMPLE=$((NO_CUMPLE + 1))
    FILAS_POLITICAS+=("| Acciones fijadas por SHA | ❌ No cumple | ${sin_fijar[*]} |")
  else
    fila "Acciones fijadas por SHA" cumple "Todas las acciones externas usan un SHA de 40 caracteres"
  fi
}

# P3. Cada workflow declara permisos mínimos para el GITHUB_TOKEN
verificar_permisos() {
  local archivo permisos
  local -a problemas=()
  for archivo in .github/workflows/*.y*ml; do
    permisos=$(yaml_a_json "$archivo" | jq -r 'if has("permissions") then (.permissions | if type == "string" then . else "mapa" end) else "ausente" end')
    case "$permisos" in
      ausente) problemas+=("\`${archivo##*/}\` no declara \`permissions:\`") ;;
      write-all) problemas+=("\`${archivo##*/}\` usa \`write-all\`") ;;
    esac
  done
  if ((${#problemas[@]} > 0)); then
    fila "Permisos mínimos del GITHUB_TOKEN" no_cumple "${problemas[*]}"
  else
    fila "Permisos mínimos del GITHUB_TOKEN" cumple "Todos los workflows declaran \`permissions:\` sin \`write-all\`"
  fi
}

# P4. Cada excepción de seguridad tiene justificación y vence en un plazo máximo
verificar_excepciones() {
  local hoy limite tabla invalidas total
  if [[ ! -f .trivyignore.yaml ]]; then
    fila "Excepciones justificadas y con vencimiento" cumple "No hay excepciones registradas"
    return
  fi
  hoy=$(date -u +%Y-%m-%d)
  limite=$(fecha_en_dias "$MAX_DIAS_EXCEPCION")
  tabla=$(yaml_a_json .trivyignore.yaml | jq -r --arg hoy "$hoy" --arg limite "$limite" --arg dias "$MAX_DIAS_EXCEPCION" '
    [(.vulnerabilities // []), (.misconfigurations // []), (.secrets // []), (.licenses // [])] | add | .[] |
    ((.expired_at // "") | tostring | .[0:10]) as $vence |
    ((.statement // "") | gsub("\\s+"; " ")) as $motivo |
    (if $motivo == "" then "sin justificación"
     elif $vence == "" then "sin fecha de vencimiento"
     elif $vence < $hoy then "vencida"
     elif $vence > $limite then "vence en más de \($dias) días"
     else "vigente" end) as $estado |
    [.id, $vence, $estado, ($motivo | .[0:90])] | @tsv')
  total=$(grep -c . <<< "$tabla" || true)
  invalidas=$(awk -F'\t' '$3 != "vigente"' <<< "$tabla")
  DETALLES_POLITICAS+=("" "Excepciones en \`.trivyignore.yaml\` (máximo ${MAX_DIAS_EXCEPCION} días):" "" "| ID | Vence | Estado | Justificación |" "|---|---|---|---|")
  while IFS=$'\t' read -r id vence estado motivo; do
    [[ -n "$id" ]] && DETALLES_POLITICAS+=("| ${id} | ${vence} | ${estado} | ${motivo}… |")
  done <<< "$tabla"
  if [[ -n "$invalidas" ]]; then
    fila "Excepciones justificadas y con vencimiento" no_cumple "$(awk -F'\t' '{ printf "%s (%s) ", $1, $3 }' <<< "$invalidas")"
  else
    fila "Excepciones justificadas y con vencimiento" cumple "${total} excepción/es vigentes, todas con justificación y fecha"
  fi
}

# P5. No se versionan archivos de credenciales
verificar_archivos_sensibles() {
  local -a encontrados
  mapfile -t encontrados < <(git ls-files |
    grep -E -i '(^|/)\.env(\.[^/]*)?$|\.(pem|key|p12|pfx|jks|keystore|tfstate)$|(^|/)id_(rsa|dsa|ecdsa|ed25519)$|(^|/)kubeconfig[^/]*$|(^|/)credentials(\.json)?$' |
    grep -v -E '\.env\.(example|ejemplo|sample)$')
  if ((${#encontrados[@]} > 0)); then
    fila "Sin archivos de credenciales versionados" no_cumple "${encontrados[*]}"
  else
    fila "Sin archivos de credenciales versionados" cumple "Ningún \`.env\`, llave, keystore ni kubeconfig en Git"
  fi
}

# P6. Dependabot vigila librerías, imágenes y acciones
verificar_dependabot() {
  local presentes eco
  local -a faltan=()
  if [[ ! -f .github/dependabot.yml ]]; then
    fila "Dependabot configurado" no_cumple "No existe .github/dependabot.yml"
    return
  fi
  presentes=" $(yaml_a_json .github/dependabot.yml | jq -r '[.updates[]["package-ecosystem"]] | unique | join(" ")') "
  for eco in "${ECOSISTEMAS_DEPENDABOT[@]}"; do
    [[ "$presentes" == *" ${eco} "* ]] || faltan+=("$eco")
  done
  if ((${#faltan[@]} > 0)); then
    fila "Dependabot configurado" no_cumple "Faltan los ecosistemas: ${faltan[*]}"
  else
    fila "Dependabot configurado" cumple "Revisa semanalmente:${presentes% }"
  fi
}

auditar_politicas() {
  verificar_ramas
  verificar_acciones_sha
  verificar_permisos
  verificar_excepciones
  verificar_archivos_sensibles
  verificar_dependabot

  {
    echo "### Políticas del repositorio"
    echo ""
    echo "| Política | Resultado | Detalle |"
    echo "|---|---|---|"
    printf '%s\n' "${FILAS_POLITICAS[@]}"
    if ((${#DETALLES_POLITICAS[@]} > 0)); then
      echo ""
      printf '%s\n' "${DETALLES_POLITICAS[@]}"
    fi
  } > "$SALIDA/politicas.md"

  local herramienta="GitHub API (rulesets), yq, jq y git"
  if ((NO_CUMPLE > 0)); then
    guardar_resultado politicas "$herramienta" no_cumple "${NO_CUMPLE} política(s) no cumplida(s)"
    return 1
  fi
  if ((ERRORES > 0)); then
    guardar_resultado politicas "$herramienta" error "${ERRORES} política(s) no se pudieron verificar"
    return 2
  fi
  local verificadas=$((${#FILAS_POLITICAS[@]} - OMITIDOS))
  local resumen="${verificadas} políticas cumplen"
  ((OMITIDOS > 0)) && resumen+=", ${OMITIDOS} sin verificar"
  guardar_resultado politicas "$herramienta" cumple "$resumen"
  return 0
}

# ─────────────────────────────── reporte final ───────────────────────────────

# Recibe el resultado de cada job en las variables RESULTADO_<CONTROL> (una por control)
# (success, failure, cancelled o skipped, como los entrega needs.<job>.result).
generar_reporte() {
  local resumen="$SALIDA/resumen.md" estado=aprobado control variable job herramienta detalle icono
  local -A nombres=(
    [secretos]="Secretos en el código"
    [dependencias]="CVE críticos en dependencias"
    [politicas]="Políticas del repositorio"
  )
  local -A herramientas=(
    [secretos]="Gitleaks"
    [dependencias]="Trivy"
    [politicas]="GitHub API, yq, jq y git"
  )
  local -a filas=()

  for control in secretos dependencias politicas; do
    variable="RESULTADO_${control^^}"
    job="${!variable:-desconocido}"
    herramienta="${herramientas[$control]}"
    detalle="Sin reporte"
    if [[ -f "$SALIDA/${control}.json" ]]; then
      herramienta=$(jq -r '.herramienta' "$SALIDA/${control}.json")
      detalle=$(jq -r '.resumen' "$SALIDA/${control}.json")
    fi
    case "$job" in
      success) icono="✅ Cumple" ;;
      failure) icono="❌ No cumple" ;;
      skipped) icono="⏭️ Omitido"; detalle="No corrió porque un control anterior falló" ;;
      cancelled) icono="⛔ Cancelado" ;;
      *) icono="❔ ${job}" ;;
    esac
    [[ "$job" == "success" ]] || estado=bloqueado
    filas+=("| ${nombres[$control]} | ${herramienta} | ${icono} | ${detalle} |")
  done

  {
    if [[ "$estado" == "aprobado" ]]; then
      echo "## ✅ Auditoría aprobada: el pipeline puede continuar"
    else
      echo "## ❌ Auditoría no aprobada: el pipeline se detiene aquí"
    fi
    echo ""
    echo "| Dato | Valor |"
    echo "|---|---|"
    echo "| Commit | \`${GITHUB_SHA:-$(git rev-parse HEAD)}\` |"
    echo "| Rama | \`${GITHUB_HEAD_REF:-${GITHUB_REF_NAME:-$(git branch --show-current)}}\` |"
    echo "| Evento | ${GITHUB_EVENT_NAME:-local} |"
    if [[ -n "${GITHUB_RUN_ID:-}" ]]; then
      echo "| Ejecución | ${GITHUB_SERVER_URL}/${GITHUB_REPOSITORY}/actions/runs/${GITHUB_RUN_ID} |"
    fi
    echo "| Fecha (UTC) | $(date -u +%Y-%m-%dT%H:%M:%SZ) |"
    echo ""
    echo "| Control | Herramienta | Resultado | Detalle |"
    echo "|---|---|---|---|"
    printf '%s\n' "${filas[@]}"
    for control in secretos dependencias politicas; do
      if [[ -f "$SALIDA/${control}.md" ]]; then
        echo ""
        cat "$SALIDA/${control}.md"
      fi
    done
  } > "$resumen"

  # Registro en JSON para conservar como evidencia de auditoría
  jq -n --arg estado "$estado" --arg commit "${GITHUB_SHA:-$(git rev-parse HEAD)}" \
    --slurpfile controles <(cat "$SALIDA"/{secretos,dependencias,politicas}.json 2> /dev/null) \
    '{estado: $estado, commit: $commit, controles: $controles}' > "$SALIDA/reporte.json"

  [[ -n "${GITHUB_STEP_SUMMARY:-}" ]] && cat "$resumen" >> "$GITHUB_STEP_SUMMARY"
  [[ -n "${GITHUB_OUTPUT:-}" ]] && echo "resultado=${estado}" >> "$GITHUB_OUTPUT"
  log "Reporte: ${resumen} (${estado})"
  [[ -z "${GITHUB_ACTIONS:-}" ]] && cat "$resumen"
  return 0
}

# ───────────────────────────────── principal ─────────────────────────────────

a_resultado_job() {
  case "$1" in
    0) echo success ;;
    *) echo failure ;;
  esac
}

case "${1:-}" in
  secretos) auditar_secretos ;;
  dependencias) auditar_dependencias ;;
  politicas) auditar_politicas ;;
  reporte) generar_reporte ;;
  todo)
    auditar_secretos; c1=$?
    auditar_dependencias; c2=$?
    auditar_politicas; c3=$?
    RESULTADO_SECRETOS=$(a_resultado_job "$c1") \
      RESULTADO_DEPENDENCIAS=$(a_resultado_job "$c2") \
      RESULTADO_POLITICAS=$(a_resultado_job "$c3") \
      generar_reporte
    max=$c1
    ((c2 > max)) && max=$c2
    ((c3 > max)) && max=$c3
    exit "$max"
    ;;
  *)
    awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' "${BASH_SOURCE[0]}"
    exit 2
    ;;
esac
