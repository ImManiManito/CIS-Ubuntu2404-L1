#!/usr/bin/env bash
# CIS 7.1.11 - Archivos y directorios world-writable (gestionado por Ansible)
# Uso: cis_world_writable.sh <check|fix> [ruta_excluida ...]
# Basado en el script de remediación del benchmark:
#  - Archivos world-writable: chmod o-w
#  - Directorios world-writable sin sticky bit: chmod a+t
mode="${1:-check}"; shift || true
l_smask='01000'; changed=0; n=0
a_path=(-path "*/containers/storage/*" -o -path "*/containerd/*" -o -path "*/kubelet/*" -o -path "/sys/*" -o -path "/snap/*" -o -path "/boot/efi/*")
for x in "$@"; do a_path+=(-o -path "$x"); done
l_exclude="nfs|proc|cifs|smb|vfat|iso9660|efivarfs|selinuxfs|ncpfs"
l_exclude2="\/run|\/tmp|\/var\/tmp"
while IFS= read -r l_mount; do
  while IFS= read -r -d $'\0' l_file; do
    l_mode="$(stat -Lc '%#a' "$l_file" 2>/dev/null)"
    if [ -f "$l_file" ]; then
      changed=1; n=$((n+1)); [ "$n" -le 200 ] && echo "CHANGE archivo ${l_file} (${l_mode}) -> o-w"
      [ "$mode" = "fix" ] && chmod o-w "$l_file"
    elif [ -d "$l_file" ] && [ ! $(( l_mode & l_smask )) -gt 0 ]; then
      changed=1; n=$((n+1)); [ "$n" -le 200 ] && echo "CHANGE directorio ${l_file} (${l_mode}) -> +t"
      [ "$mode" = "fix" ] && chmod a+t "$l_file"
    fi
  done < <(find "$l_mount" -mount -xdev \( "${a_path[@]}" \) -prune -o \( -type f -o -type d \) -perm -0002 -print0 2>/dev/null)
done < <(findmnt -Dkerno fstype,target | awk '($1 !~ /^\s*('"$l_exclude"')/ && $2 !~ /^('"$l_exclude2"')(\/|$)/){print $2}')
[ "$n" -gt 200 ] && echo "INFO ... $((n-200)) elementos más"
[ "$changed" -eq 1 ] && echo "RESULT=changed" || echo "RESULT=ok"
exit 0
