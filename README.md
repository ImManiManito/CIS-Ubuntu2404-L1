# CIS Ubuntu Linux 24.04 LTS v2.0.0 — Level 1 Server (Ansible)

Playbook de cumplimiento basado en `CIS_Ubuntu_Linux_24.04_LTS_v2.0.0_L1_Server.audit` (Tenable).

- **Aplica** los controles de bajo riesgo operativo (permisos, drop-ins, sysctl, banners, SSH no disruptivo, sudo, journald/rsyslog, AIDE, etc.).
- **Aplica también los controles críticos** listados en `cis_critical_controls` (SSH, PAM, montajes, cuentas, IPv6, etc.) con protecciones contra bloqueo: validación previa, respaldo y **restauración automática de SSH/PAM** si Ansible no logra volver a entrar.
- Lo que sigue siendo de revisión manual (firewall activo, GRUB, parches, cuentas UID 0, etc.) se reporta por host con evidencia de solo lectura y la acción sugerida.

## Nivel de cumplimiento

Resultado de una auditoría de 259 controles: **241 aprobados (93.05 %)**, **8 con advertencias (3.09 %)** y **10 fallidos (3.86 %)**.

![Resumen del nivel de cumplimiento de la auditoría](images/cumplimiento.png)

## Requisitos

- Controlador: `ansible-core >= 2.15`. Solo usa módulos `ansible.builtin` (no requiere colecciones).
- Destino: Ubuntu 24.04 LTS, Python 3 del sistema, acceso `sudo`.
- El rol valida que el SO sea Ubuntu 24.04 y se detiene en cualquier otro.

## Estructura

```
CIS-Ubuntu2404-L1/
├── ansible.cfg
├── site.yml
├── inventory/hosts.ini
├── group_vars/all.yml              # ajustes de la organización
├── reports/                        # reportes por host (se generan aquí)
└── roles/cis_ubuntu2404/
    ├── defaults/main.yml           # valores alineados al .audit (no editar; sobrescribir en group_vars)
    ├── vars/main.yml               # catálogo de controles de revisión manual (comandos de solo lectura)
    ├── tasks/section1..7.yml       # remediación por sección CIS
    ├── tasks/manual_review.yml     # auditoría de controles críticos (no cambia nada)
    ├── tasks/report.yml            # reporte .md/.csv
    ├── handlers/main.yml           # recargas validadas (sshd -t, rsyslogd -N1, sysctl --system)
    ├── templates/ y files/
```

## Uso

```bash
# 1. Simulación con diferencias + reporte de revisión manual (no cambia nada)
ansible-playbook site.yml -l srv-app01 --check --diff

# 2. Aplicar
ansible-playbook site.yml -l srv-app01

# 3. Solo un control o una sección
ansible-playbook site.yml -l srv-app01 --tags cis_5.1.7
ansible-playbook site.yml -l srv-app01 --tags section3

# 4. Solo el reporte de revisión manual (solo lectura)
ansible-playbook site.yml -l srv-app01 --tags manual_review

# 5. Omitir controles puntuales en un host/grupo
ansible-playbook site.yml -l srv-app01 -e '{"cis_skip_controls": ["5.1.16", "1.5.3"]}'
```

Reportes: `reports/<host>_CIS_revision_manual.md` y `.csv` en el controlador, y copia en `/var/log/cis/` del host.

> Recomendación: primero ejecútalo en un host de prueba con una sesión SSH/consola abierta. Los cambios de SSH se validan con `sshd -t` antes de recargar y, si fallan, el drop-in se retira automáticamente.

## Qué se aplica automáticamente

| Sección | Controles | Cómo |
|---|---|---|
| 1.1.1 | 1.1.1.1–1.1.1.5, 1.1.1.9 | `/etc/modprobe.d/cis-<mod>.conf` (install /bin/false + blacklist). Si el módulo está cargado, se omite y se reporta. |
| 1.2.1 | 1.2.1.3–1.2.1.9 | Permisos de llaves GPG, `trusted.gpg.d`, `auth.conf.d`, `keyrings`, `sources.list.d`. |
| 1.3.1 | 1.3.1.1, 1.3.1.2 (servicio), 1.3.1.4 | Paquetes AppArmor, servicio habilitado, `kernel.apparmor_restrict_unprivileged_unconfined=1`. |
| 1.4 | 1.4.2 | `/boot/grub/grub.cfg` root:root 0600. |
| 1.5 | 1.5.1, 1.5.3–1.5.11, 1.5.13 | `/etc/sysctl.d/60-cis-kernel.conf`, quita prelink, deshabilita apport, `coredump.conf.d/60-coredump.conf`. Comenta valores en conflicto en `/etc/sysctl.conf`, `/etc/sysctl.d/` y `/etc/ufw/sysctl.conf`. |
| 1.6 | 1.6.1–1.6.10 | Banner en `/etc/motd`, `/etc/issue`, `/etc/issue.net`, permisos; scripts de MOTD dinámico con referencias a Ubuntu se mueven a `/etc/update-motd.d.cis-disabled/` (reversible). |
| 1.7 | 1.7.1–1.7.6 | Solo si `gdm3` está instalado (dconf + XDMCP). |
| 2.1 | 2.1.1, 2.1.3, 2.1.5–2.1.22 | Servicios **instalados e inactivos** se detienen y enmascaran (no se desinstalan). Los **activos** se reportan. `cis_services_approved` excluye servicios aprobados. |
| 2.2 | 2.2.1–2.2.6 | Desinstala clientes nis, rsh, talk, telnet, ldap-utils, ftp. |
| 2.3 | 2.3.2.x / 2.3.3.x | chrony como `_chrony` y habilitado (o timesyncd habilitado). Servidores NTP solo si se define `cis_ntp_servers`. |
| 2.4 | 2.4.1.1–2.4.1.9, 2.4.2.1 | cron habilitado, permisos, `cron.allow`/`at.allow` **preservando usuarios que ya tienen crontab/at**. |
| 3.1 | 3.1.3 | `bluetooth.service` enmascarado. |
| 3.2 | 3.2.1–3.2.6 | Módulos atm, can, dccp, rds, sctp, tipc (se omiten si están cargados). |
| 3.3 | 3.3.1.2–3.3.1.11, 3.3.1.14–3.3.1.18, 3.3.2.1–3.3.2.6 | `/etc/sysctl.d/60-cis-network.conf`. El forwarding solo se fija si **ya** está en 0 (protege Docker/K8s). |
| 4.1 | 4.1.1 | Instala ufw **sin habilitarlo** (se omite si existe iptables-persistent/netfilter-persistent/firewalld). |
| 5.1 | 1.6.5, 5.1.1–5.1.3, 5.1.5, 5.1.7, 5.1.10, 5.1.11, 5.1.13, 5.1.14, 5.1.16–5.1.19, 5.1.21, 5.1.22 | `/etc/ssh/sshd_config.d/01-cis-hardening.conf` validado con `sshd -t`; permisos de config y llaves de host. |
| 5.2 | 5.2.1–5.2.3, 5.2.6 | `/etc/sudoers.d/01-cis-hardening` validado con `visudo`. |
| 5.3 | 5.3.1.1–5.3.1.4, 5.3.3.1.1, 5.3.3.1.2, 5.3.3.2.1–5.3.3.2.8, 5.3.3.3.1, 5.3.3.3.2 | Solo archivos de configuración: `faillock.conf`, `pwquality.conf.d/60-cis.conf`, `pwhistory.conf`. **No se edita `/etc/pam.d`.** |
| 5.4 | 5.4.1.1, 5.4.1.3, 5.4.1.4, 5.4.1.5, 5.4.2.6, 5.4.3.2, 5.4.3.3 | `login.defs` y `useradd -D` (solo nuevos usuarios), aviso de expiración a usuarios existentes, umask de root, `TMOUT=900`, `umask 027`. |
| 6.1 | 6.1.1.1.1–6.1.1.1.3, 6.1.1.1.5–6.1.1.1.7, 6.1.2.1–6.1.2.4, 6.1.2.7, 6.1.3.1 | Drop-in de journald, rsyslog (`$FileCreateMode 0640`, reglas CIS + logrotate), permisos en `/var/log`. 6.1.2.5 solo si se define `cis_rsyslog_remote_host`. |
| 6.3 | 6.3.1, 6.3.2 | Instala AIDE, inicializa la base y habilita `dailyaidecheck.timer`. |
| 7.1 | 7.1.1–7.1.10 | Permisos de passwd, group, shadow, gshadow (y respaldos), shells, opasswd. |

## Controles críticos (se aplican si están en `cis_critical_controls`)

| Control | Qué hace el playbook | Protección |
|---|---|---|
| 1.1.1.10 | Bloquea `usb-storage` y lo descarga. | Si hay un USB montado queda pendiente. **Se pierde virtual media de iLO/iDRAC.** |
| 1.1.1.11 | Bloquea todo módulo de `kernel/fs` no montado ni cargado. | Conserva `cis_fs_modules_keep` y sus dependencias. |
| 1.1.2.x | nodev/nosuid/noexec en /tmp, /dev/shm, /home, /var, /var/tmp, /var/log, /var/log/audit. | Respaldo de fstab + `findmnt --verify`. Si no hay partición separada usa **bind mount** sobre sí mismo. Si hay submontajes (Docker) queda para reinicio. |
| 2.1.2 | postfix `inet_interfaces=loopback-only` (exim4 equivalente). | — |
| 2.1.4 | Detiene/enmascara `cis_unapproved_services` y purga `cis_unapproved_packages`. | Requiere que llenes las listas con base en el reporte. |
| 2.3.2.1 / 2.3.3.1 | NTP/FallbackNTP (timesyncd) o `server` (chrony) con `cis_ntp_servers`. | Por defecto NIST; **cambia a tus NTP internos**. |
| 3.1.1 | `disable_ipv6=1` (all/default) por sysctl. | `cis_ipv6_disable: false` para dejarlo activo. |
| 3.3.1.2/3.3.1.3/3.3.2.1/3.3.2.2 | forwarding=0. | Si Docker/containerd/Podman/kubelet están activos **no** se aplica (`cis_forwarding_skip_if_containers`). |
| 3.3.2.7 / 3.3.2.8 | `accept_ra=0`. | — |
| 5.1.4 | `AllowGroups sshusers`. | Agrega al grupo al usuario de Ansible, `cis_ssh_allowed_users` y miembros de sudo/admin. Reporta quién pierde acceso. |
| 5.1.6 / 5.1.12 / 5.1.15 / 5.1.23 | Ciphers, KexAlgorithms (sntrup761 primero) y MACs fuertes. | Filtrados contra `ssh -Q` del OpenSSH instalado; `sshd -t` antes de recargar. |
| 5.1.20 | `PermitRootLogin no`. | Se niega a aplicarlo si Ansible entra como root. |
| 5.2.7 | `pam_wheel use_uid group=sugroup` en `/etc/pam.d/su` (grupo vacío). | `sudo su -` sigue funcionando (pam_rootok). |
| 5.3.2.x | Perfiles pam-auth-update: faillock, faillock_notify, pwquality, pwhistory. | Respaldo de PAM, validación de módulos y **rollback automático**. |
| 5.3.3.4.x | Quita `nullok`/`remember` de pam_unix; yescrypt y use_authtok. | Igual que 5.3.2.x. |
| 5.4.1.1 / 5.4.1.5 | `chage --maxdays 365` e `--inactive 45` a usuarios existentes. | Excluye `cis_password_aging_exclude` y protege al usuario de Ansible si expiraría. Reporta cuentas que expiran o se bloquean. |
| 5.4.2.5 | Limpia el PATH de root (`/etc/environment`, ENV_SUPATH/ENV_PATH). | Solo quita rutas inexistentes, `.`, vacías o que no son de root. |
| 7.1.11 | `o-w` a archivos y sticky bit a directorios world-writable. | Excluye rutas del benchmark + `cis_ww_extra_exclude_paths` (`/var/lib/docker/*`). |

### Red de seguridad de SSH/PAM

Antes de tocar SSH y PAM el playbook respalda `/etc/ssh`, `/etc/pam.d` y `/usr/share/pam-configs` en `/var/backups/cis-rollback` y programa con systemd una **restauración automática en 30 minutos** (`cis_rollback_minutes`). Al terminar los cambios recarga sshd, abre una **sesión SSH nueva + sudo**; si funciona, cancela la restauración. Si te quedas sin acceso, espera el tiempo indicado y el servidor vuelve solo a la configuración anterior (queda registro en `journalctl -t cis-rollback`).

## Qué queda para revisión manual (no se aplica)

| Control | Motivo |
|---|---|
| 1.2.1.1 Signed-By, 1.2.2.1 parches | Cambios de repositorios y actualizaciones van en ventana. |
| 1.3.1.2 apparmor=0 en GRUB, 1.4.1 contraseña de GRUB | Cambios de arranque y reinicio. |
| 2.3.1.1 un solo demonio de tiempo | Depende del estándar de la organización. |
| 3.1.2 wireless, 3.3.1.12/13 rp_filter | Requiere análisis de uso / topología. |
| 4.1.2, 4.1.3, 4.1.5 UFW activo / default deny | Pérdida total de acceso si no hay reglas previas. |
| 5.2.5 !authenticate | Automatizaciones. |
| 5.4.1.6, 5.4.2.1–5.4.2.4, 5.4.2.7, 5.4.2.8 | Cuentas UID/GID 0, root, shells y bloqueo de cuentas de sistema. |
| 6.1.1.1.4, 6.1.2.5 (sin servidor), 6.1.2.6 | tmpfiles de journald, SIEM, hosts colectores. |
| 7.1.12, 7.1.13, 7.2.1–7.2.10 | Huérfanos, SUID/SGID, integridad de cuentas, homes y dotfiles. |

## Notas de reversa

- Módulos: borrar `/etc/modprobe.d/cis-<mod>.conf`.
- Servicios enmascarados: `systemctl unmask <unidad>`.
- MOTD dinámico: mover de vuelta los scripts de `/etc/update-motd.d.cis-disabled/`.
- sysctl: los valores comentados quedan con el prefijo `# CIS-disabled` en su archivo original.
- SSH/sudo: borrar `01-cis-hardening.conf` / `01-cis-hardening` (el template guarda respaldo del drop-in previo).
- PAM: respaldo en `/var/backups/cis-pam-<fecha>/` (copiar `pam.d/common-*` de vuelta) o `/var/backups/cis-rollback`.
- Montajes: respaldo `/etc/fstab.cis-<fecha>`; para quitar un bind: borrar la línea y `umount <ruta>`.
- Módulos de filesystem: borrar `/etc/modprobe.d/cis-fs-*.conf` y `cis-usb-storage.conf`.
- IPv6: borrar las líneas `disable_ipv6` de `/etc/sysctl.d/60-cis-network.conf` y `sysctl --system`.
