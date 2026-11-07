#!/usr/bin/env bash
# CIS Ubuntu 24.04 - Comenta valores sysctl en conflicto (gestionado por Ansible)
# Uso: cis_sysctl_fix.sh <check|fix> <archivo_propio> key=valor_permitido(regex) [...]
#  - Revisa /etc/sysctl.conf, /etc/sysctl.d/*.conf y el archivo IPT_SYSCTL de UFW.
#  - Comenta (# ) las líneas que asignan a la llave un valor distinto al requerido.
#  - Archivos en /usr/lib/sysctl.d y /run/sysctl.d NO se tocan (pertenecen a paquetes):
#    se listan como "WARN" para revisión manual (el drop-in 60-cis-*.conf los sobreescribe).
set -u
mode="${1:-check}"; own="${2:-}"; shift 2 || true
files=(/etc/sysctl.conf)
while IFS= read -r -d '' f; do files+=("$f"); done < <(find /etc/sysctl.d -maxdepth 1 -type f -name '*.conf' -print0 2>/dev/null)
if [ -f /etc/default/ufw ]; then
  ufw_file="$(awk -F= '/^\s*IPT_SYSCTL=/{print $2}' /etc/default/ufw | tr -d '"')"
  [ -n "${ufw_file}" ] && [ -f "$(readlink -e "${ufw_file}")" ] && files+=("$(readlink -e "${ufw_file}")")
fi
changed=0
for kv in "$@"; do
  key="${kv%%=*}"; val="${kv#*=}"
  kre="${key//./[./]}"
  for f in "${files[@]}"; do
    [ -f "$f" ] || continue
    [ "$(readlink -e "$f")" = "$(readlink -e "$own" 2>/dev/null)" ] && continue
    if grep -Pq -- "^\h*${kre}\h*=\h*(?!${val}\h*$)\S+" "$f"; then
      echo "CHANGE ${f}: ${key} distinto de ${val}"
      changed=1
      if [ "$mode" = "fix" ]; then
        sed -ri "s@^(\s*${kre}\s*=)@# CIS-disabled \1@" "$f"
        # Reactivar si el valor comentado era válido
        sed -ri "s@^# CIS-disabled (\s*${kre}\s*=\s*${val}\s*)\$@\1@" "$f"
      fi
    fi
  done
  for f in /usr/lib/sysctl.d/*.conf /run/sysctl.d/*.conf; do
    [ -f "$f" ] || continue
    grep -Pq -- "^\h*-?${kre}\h*=\h*(?!${val}\h*$)\S+" "$f" && echo "WARN ${f}: ${key} distinto de ${val} (archivo de paquete, revisar)"
  done
done
[ "$changed" -eq 1 ] && echo "RESULT=changed" || echo "RESULT=ok"
exit 0
