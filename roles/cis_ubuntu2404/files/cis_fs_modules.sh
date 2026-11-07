#!/usr/bin/env bash
# CIS 1.1.1.11 - Bloquear módulos de filesystem no usados (gestionado por Ansible)
# Uso: cis_fs_modules.sh <check|fix> [modulo_a_conservar ...]
# Se excluyen automáticamente: módulos montados, cargados, la lista a conservar
# y TODAS sus dependencias (modinfo -F depends), para no romper montajes futuros.
mode="${1:-check}"; shift || true
declare -A keep=()
add_keep() {
  local m="${1//-/_}"
  [ -z "$m" ] && return
  [ -n "${keep[$m]:-}" ] && return
  keep[$m]=1
  local d
  for d in $(modinfo -F depends "$1" 2>/dev/null | tr ',' ' '); do add_keep "$d"; done
}
for k in "$@"; do add_keep "$k"; done
# Montados y cargados (y sus dependencias)
while read -r fs; do [ -n "$fs" ] && add_keep "$fs"; done < <(findmnt -Dkerno fstype 2>/dev/null | sort -u)
while read -r m; do [ -n "$m" ] && add_keep "$m"; done < <(lsmod 2>/dev/null | awk 'NR>1{print $1}')

l_search="$(readlink -e /usr/lib/modules/ || readlink -e /lib/modules/)"
showcfg="$(modprobe --showconfig 2>/dev/null | grep -Pi '^\h*(blacklist|install)\h+')"
declare -A seen=()
changed=0
while IFS= read -r -d '' l_dir; do
  [ "$(basename "$l_dir")" = "nls" ] && continue
  while IFS= read -r -d '' l_file; do
    m="$(basename "$l_file" | cut -d'.' -f1)"; mu="${m//-/_}"
    [ -n "${seen[$mu]:-}" ] && continue; seen[$mu]=1
    [ -n "${keep[$mu]:-}" ] && continue
    if grep -Psiq -- "\binstall\h+${mu}\h+\H+" <<< "$showcfg" && grep -Psiq -- "\bblacklist\h+${mu}\b" <<< "$showcfg"; then
      continue
    fi
    echo "CHANGE bloquear ${m}"
    changed=1
    if [ "$mode" = "fix" ]; then
      printf '%s\n' "# CIS 1.1.1.11 - Gestionado por Ansible" "install ${m} /bin/false" "blacklist ${m}" > "/etc/modprobe.d/cis-fs-${m}.conf"
      chmod 0644 "/etc/modprobe.d/cis-fs-${m}.conf"
    fi
  done < <(find -L "$l_dir" -mindepth 1 -maxdepth 1 -type f -print0 2>/dev/null)
done < <(find "$l_search"/*/kernel/fs/ -mindepth 1 -maxdepth 1 -type d ! -empty -print0 2>/dev/null)
echo "KEEP ${!keep[*]}"
[ "$changed" -eq 1 ] && echo "RESULT=changed" || echo "RESULT=ok"
exit 0
