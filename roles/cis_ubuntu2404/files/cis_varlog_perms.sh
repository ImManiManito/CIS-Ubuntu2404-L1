#!/usr/bin/env bash
# CIS 6.1.3.1 - Permisos y propietarios de archivos en /var/log (gestionado por Ansible)
# Basado en el script de remediación del benchmark. Uso: cis_varlog_perms.sh <check|fix>
# Solo corrige propietario si el dueño NO es root/syslog ni una cuenta de servicio
# (las cuentas sin shell válida, p.ej. www-data, mysql, se respetan).
mode="${1:-check}"
changes=0
f_file_test_fix() {
  local out=()
  maxperm="$(printf '%o' $(( 0777 & ~perm_mask )))"
  if [ $(( l_mode & perm_mask )) -gt 0 ]; then
    out+=("modo ${l_mode} -> <= ${maxperm}")
    [ "$mode" = "fix" ] && chmod "$l_rperms" "$l_fname"
  fi
  if [[ ! "$l_user" =~ $l_auser ]]; then
    out+=("dueño ${l_user} -> root")
    [ "$mode" = "fix" ] && chown root "$l_fname"
  fi
  if [[ ! "$l_group" =~ $l_agroup ]]; then
    out+=("grupo ${l_group} -> root")
    [ "$mode" = "fix" ] && chgrp root "$l_fname"
  fi
  if [ "${#out[@]}" -gt 0 ]; then
    changes=1
    echo "CHANGE ${l_fname}: ${out[*]}"
  fi
}
while IFS= read -r -d $'\0' l_file; do
  while IFS=: read -r l_fname l_mode l_user l_group; do
    if grep -Pq -- '\/(apt)\h*$' <<< "$(dirname "$l_fname")"; then
      perm_mask='0133' l_rperms="u-x,go-wx" l_auser="^(root)$" l_agroup="^(root|adm)$"; f_file_test_fix
    else
      case "$(basename "$l_fname")" in
        lastlog | lastlog.* | wtmp | wtmp.* | wtmp-* | btmp | btmp.* | btmp-* | README)
          perm_mask='0113' l_rperms="ug-x,o-wx" l_auser="^(root)$" l_agroup="^(root|utmp)$"; f_file_test_fix ;;
        cloud-init.log* | localmessages* | waagent.log*)
          perm_mask='0133' l_rperms="u-x,go-wx" l_auser="^(root|syslog)$" l_agroup="^(root|adm)$"; f_file_test_fix ;;
        secure | auth.log | syslog | messages)
          perm_mask='0137' l_rperms="u-x,g-wx,o-rwx" l_auser="^(root|syslog)$" l_agroup="^(root|adm)$"; f_file_test_fix ;;
        SSSD | sssd)
          perm_mask='0117' l_rperms="ug-x,o-rwx" l_auser="^(root|SSSD)$" l_agroup="^(root|SSSD)$"; f_file_test_fix ;;
        gdm | gdm3)
          perm_mask='0117' l_rperms="ug-x,o-rwx" l_auser="^(root)$" l_agroup="^(root|gdm|gdm3)$"; f_file_test_fix ;;
        *.journal | *.journal~)
          perm_mask='0137' l_rperms="u-x,g-wx,o-rwx" l_auser="^(root)$" l_agroup="^(root|systemd-journal)$"; f_file_test_fix ;;
        *)
          perm_mask='0137' l_rperms="u-x,g-wx,o-rwx" l_auser="^(root|syslog)$" l_agroup="^(root|adm)$"
          l_shell="$(awk -F: -v u="$l_user" '$1==u {print $7}' /etc/passwd)"
          if [ "$l_user" = "root" ] || ! grep -Pq -- "^\h*${l_shell}\b" /etc/shells 2>/dev/null || [ -z "$l_shell" ]; then
            [[ "$l_user" =~ $l_auser ]] || l_auser="^(root|syslog|${l_user})$"
            [[ "$l_group" =~ $l_agroup ]] || l_agroup="^(root|adm|${l_group})$"
          fi
          f_file_test_fix ;;
      esac
    fi
  done < <(stat -Lc '%n:%#a:%U:%G' "$l_file")
done < <(find -L /var/log -type f \( -perm /0137 -o ! -user root -o ! -group root \) -print0 2>/dev/null)
[ "$changes" -eq 1 ] && echo "RESULT=changed" || echo "RESULT=ok"
exit 0
