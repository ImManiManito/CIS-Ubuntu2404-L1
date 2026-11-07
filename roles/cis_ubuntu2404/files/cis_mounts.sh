#!/usr/bin/env bash
# CIS 1.1.2.x - Opciones de montaje nodev/nosuid/noexec (gestionado por Ansible)
# Uso: cis_mounts.sh <check|fix> <bind:0|1> <live:0|1> /ruta:opt1,opt2 [...]
#  - Si la ruta está en /etc/fstab: agrega las opciones faltantes (y quita dev/suid/exec).
#  - Si es un montaje separado sin entrada en fstab (p.ej. /dev/shm): crea la entrada.
#  - Si NO es un montaje separado y bind=1: agrega "<ruta> <ruta> none bind,<opts>".
#  - live=1: aplica en caliente (remount/mount) salvo que haya submontajes debajo.
#  - Respalda fstab y valida con "findmnt --verify"; si falla, restaura el respaldo.
set -u
mode="${1:-check}"; bind="${2:-1}"; live="${3:-1}"; shift 3 || true
fstab=/etc/fstab
bak="/etc/fstab.cis-$(date +%Y%m%d%H%M%S)"
changed=0; fstab_changed=0; reboot=0
backup_once() { [ "$mode" = "fix" ] && [ ! -f "$bak" ] && cp -a "$fstab" "$bak"; }

for spec in "$@"; do
  path="${spec%%:*}"; IFS=',' read -ra req <<< "${spec#*:}"
  if [ ! -d "$path" ]; then
    if [ "$path" = "/var/log/audit" ]; then
      echo "CHANGE ${path}: no existe, se crea (0750)"; changed=1
      [ "$mode" = "fix" ] && install -d -m 0750 -o root -g root "$path"
    else
      echo "INFO ${path}: no existe, se omite"; continue
    fi
  fi
  line="$(awk -v p="$path" '$1 !~ /^#/ && $2 == p {print NR; exit}' "$fstab")"
  if [ -n "$line" ]; then
    cur="$(awk -v n="$line" 'NR==n {print $4}' "$fstab")"
    new="$cur"
    for o in "${req[@]}"; do
      neg="${o#no}"   # nodev->dev, nosuid->suid, noexec->exec
      new="$(tr ',' '\n' <<< "$new" | grep -vx -- "$neg" | paste -sd, -)"
      grep -qx -- "$o" <<< "$(tr ',' '\n' <<< "$new")" || new="${new},${o}"
    done
    if [ "$new" != "$cur" ]; then
      echo "CHANGE ${path}: fstab opciones '${cur}' -> '${new}'"; changed=1; fstab_changed=1
      if [ "$mode" = "fix" ]; then
        backup_once
        awk -v n="$line" -v o="$new" 'BEGIN{OFS="\t"} NR==n {$4=o} {print}' "$fstab" > "${fstab}.cis-tmp" && cat "${fstab}.cis-tmp" > "$fstab" && rm -f "${fstab}.cis-tmp"
      fi
    fi
    action="remount"
  elif findmnt -kn -M "$path" >/dev/null 2>&1; then
    src="$(findmnt -kn -M "$path" -o SOURCE | tail -1)"; fst="$(findmnt -kn -M "$path" -o FSTYPE | tail -1)"
    entry="${src} ${path} ${fst} defaults,rw,$(IFS=,; echo "${req[*]}"),relatime 0 0"
    echo "CHANGE ${path}: montaje separado sin fstab, se agrega '${entry}'"; changed=1; fstab_changed=1
    if [ "$mode" = "fix" ]; then backup_once; printf '%s\n' "# CIS 1.1.2.x - Gestionado por Ansible" "$entry" >> "$fstab"; fi
    action="remount"
  elif [ "$bind" = "1" ]; then
    entry="${path} ${path} none bind,$(IFS=,; echo "${req[*]}") 0 0"
    echo "CHANGE ${path}: no es partición separada, se agrega bind '${entry}'"; changed=1; fstab_changed=1
    if [ "$mode" = "fix" ]; then backup_once; printf '%s\n' "# CIS 1.1.2.x - Gestionado por Ansible (bind)" "$entry" >> "$fstab"; fi
    action="mount"
  else
    echo "INFO ${path}: no es partición separada (cis_mounts_bind_if_not_separate=false)"; continue
  fi
  # Estado en caliente
  if findmnt -kn -M "$path" >/dev/null 2>&1; then
    opts="$(findmnt -kn -M "$path" -o OPTIONS | tail -1)"
    miss=(); for o in "${req[@]}"; do grep -qw -- "$o" <<< "$opts" || miss+=("$o"); done
    [ "${#miss[@]}" -eq 0 ] && continue
  fi
  if [ "$mode" = "fix" ] && [ "$live" = "1" ]; then
    if findmnt -rn -o TARGET | grep -q -- "^${path}/"; then
      echo "REBOOT ${path}: tiene submontajes, se aplicará en el siguiente reinicio"; reboot=1
    else
      if [ "$action" = "remount" ]; then mount -o remount "$path" 2>&1 || mount -o "remount,$(IFS=,; echo "${req[*]}")" "$path"
      else mount "$path" 2>&1; fi
      echo "LIVE ${path}: $(findmnt -kn -M "$path" -o OPTIONS | tail -1)"
    fi
  elif [ "$mode" = "fix" ]; then
    echo "REBOOT ${path}: se aplicará en el siguiente reinicio"; reboot=1
  fi
  changed=1
done

if [ "$mode" = "fix" ] && [ "$fstab_changed" -eq 1 ]; then
  if ! findmnt --verify --tab-file "$fstab" >/tmp/cis-fstab-verify.log 2>&1; then
    if grep -qiE '[1-9][0-9]* (parse )?errors' /tmp/cis-fstab-verify.log; then
      cat /tmp/cis-fstab-verify.log
      [ -f "$bak" ] && cat "$bak" > "$fstab"
      echo "ERROR fstab inválido; se restauró ${bak}"
      exit 1
    fi
  fi
  systemctl daemon-reload >/dev/null 2>&1 || true
  echo "BACKUP ${bak}"
fi
[ "$reboot" -eq 1 ] && echo "RESULT=reboot"
[ "$changed" -eq 1 ] && echo "RESULT=changed" || echo "RESULT=ok"
exit 0
