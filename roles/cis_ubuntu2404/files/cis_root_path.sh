#!/usr/bin/env bash
# CIS 5.4.2.5 - Integridad del PATH de root (gestionado por Ansible)
# Uso: cis_root_path.sh <check|fix>
# El benchmark evalúa "sudo su - root -c env": en Ubuntu ese PATH viene de
# /etc/environment (pam_env) y de ENV_SUPATH/ENV_PATH en /etc/login.defs.
#  - Quita entradas vacías, ".", rutas que no son directorio y directorios que no son de root.
#  - A directorios de root con escritura de grupo/otros les quita esa escritura (go-w).
mode="${1:-check}"; changed=0
clean_path() {
  local p="$1" out=() d
  IFS=':' read -ra parts <<< "$p"
  for d in "${parts[@]}"; do
    [ -z "$d" ] && { echo "CHANGE PATH: entrada vacía eliminada" >&2; continue; }
    [ "$d" = "." ] && { echo "CHANGE PATH: '.' eliminado" >&2; continue; }
    [ -d "$d" ] || { echo "CHANGE PATH: '${d}' no es directorio, eliminado" >&2; continue; }
    if [ "$(stat -Lc '%U' "$d")" != "root" ]; then echo "CHANGE PATH: '${d}' no pertenece a root, eliminado" >&2; continue; fi
    m="$(stat -Lc '%#a' "$d")"
    if [ $(( m & 022 )) -gt 0 ]; then
      echo "CHANGE ${d}: modo ${m} -> go-w" >&2
      [ "$mode" = "fix" ] && chmod go-w "$d"
    fi
    printf '%s\n' "${out[@]}" | grep -qxF -- "$d" || out+=("$d")
  done
  (IFS=':'; echo "${out[*]}")
}
# /etc/environment
if [ -f /etc/environment ] && grep -Pq '^\h*PATH=' /etc/environment; then
  cur="$(grep -Po '^\h*PATH=\K.*' /etc/environment | tail -1 | tr -d '"')"
  new="$(clean_path "$cur" 2>/tmp/cis-path.log)"; cat /tmp/cis-path.log
  if [ "$cur" != "$new" ] || [ -s /tmp/cis-path.log ]; then
    changed=1
    [ "$mode" = "fix" ] && [ "$cur" != "$new" ] && sed -ri "s|^\s*PATH=.*|PATH=\"${new}\"|" /etc/environment
  fi
fi
# /etc/login.defs ENV_SUPATH / ENV_PATH
for k in ENV_SUPATH ENV_PATH; do
  cur="$(awk -v k="$k" '$1==k {print $2}' /etc/login.defs | tail -1)"
  [ -z "$cur" ] && continue
  pref=""; val="$cur"; [[ "$val" == PATH=* ]] && { pref="PATH="; val="${val#PATH=}"; }
  new="$(clean_path "$val" 2>/tmp/cis-path.log)"; cat /tmp/cis-path.log
  if [ "$val" != "$new" ]; then
    changed=1
    [ "$mode" = "fix" ] && sed -ri "s|^(\s*${k}\s+).*|\1${pref}${new}|" /etc/login.defs
  fi
done
rm -f /tmp/cis-path.log
[ "$changed" -eq 1 ] && echo "RESULT=changed" || echo "RESULT=ok"
exit 0
