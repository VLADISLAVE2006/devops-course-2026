# Конфигурация виртуальной машины devops-vm

## 1. Параметры машины

Ubuntu Server 24.04 LTS, стандартная серверная установка без графического интерфейса; после обновления версия 24.04.5, ядро 6.8.0-149-generic, VirtualBox 7.2.4. Память — 2048 МБ, динамический диск VDI — 25 ГиБ, 2 CPU; `nproc` возвращает 2. Интерфейс паравиртуализации — KVM. На этом Windows-хосте с Hyper-V исходная загрузка останавливалась с ошибкой таймера IO-APIC или RCU stall в `raid6_pq`. Проверенный обход задан только внутри гостевой системы в `/etc/default/grub.d/99-lab-vm.cfg`:

```bash
GRUB_CMDLINE_LINUX_DEFAULT="nomodeset noapic module_blacklist=raid6_pq,btrfs"
GRUB_CMDLINE_LINUX="console=tty0 console=ttyS0,115200n8"
```

После изменения выполняется `sudo update-grub`. Корневая система использует ext4; Btrfs и программный RAID6 на этом стенде не применяются. Исходные параметры сохранены в `/etc/default/grub.before-lab-boot-fix`. Настройки Windows и Hyper-V не менялись. Чистый снимок уже содержит этот обход. Журналы неудачной и успешной загрузки сохранены отдельно от репозитория в evidence/install.

## 2. Сетевые интерфейсы

Адаптер 1 — NAT, адрес `10.0.2.15/24`, доступ в Интернет. Адаптер 2 — Host-only, сеть `192.168.56.0/24`, адрес VM при установке — `192.168.56.103`. Адрес хоста в этом сегменте — `192.168.56.1`. Оба виртуальных адаптера используют VirtIO. Перед восстановлением проверьте фактические адреса командой `ip -brief address`: DHCP может выдать другой адрес.

На Windows в `C:\Windows\System32\drivers\etc\hosts` должны находиться записи с фактическим Host-only адресом:

```text
192.168.56.103 devops.local
```

Изменения hosts выполняются с правами администратора. Проверки на Windows: `ping devops.local`, `ssh -p 2222 devops@devops.local`. В WSL действует собственный `/etc/hosts`; при использовании curl из WSL запись нужно добавить и туда.

## 3. Правило проброса портов

После чистой установки: `127.0.0.1:2222 → VM:22/tcp`. После усиления SSH: `127.0.0.1:2222 → VM:2222/tcp`. На внешних интерфейсах Windows этот управляющий порт не публикуется.

Для безопасного перехода можно временно создать второе правило `127.0.0.1:2223 → VM:2222/tcp`, проверить новый слушатель через порт 2223, затем изменить основное правило и удалить временное. До подтверждения нового подключения действующую сессию не закрывают.

## 4. Учётные записи

`student` — первоначальная учётная запись установщика, член `sudo`. `devops` — рабочая учётная запись администратора, член `sudo`, вход по отдельному ключу Ed25519. Пароли и закрытые ключи в репозитории не хранятся. Учётная запись root не используется для SSH.

С чистого снимка войдите как `student`, получите копию репозитория и создайте рабочего пользователя:

```bash
git clone --branch feature/server-setup https://github.com/VLADISLAVE2006/devops-course-2026.git
cd devops-course-2026
sudo bash scripts/create-devops.sh
groups devops
sudo stat -c '%a %U %n' /home/devops/.ssh /home/devops/.ssh/authorized_keys
```

После проверки входа по ключу откройте отдельную сессию `ssh devops` и получите копию репозитория уже в домашний каталог devops:

```bash
git clone --branch feature/server-setup https://github.com/VLADISLAVE2006/devops-course-2026.git
cd ~/devops-course-2026
```

Дальнейшие сценарии запускаются из этой копии от имени devops через sudo. Сессию, открытую до изменения SSH, сохраняйте до проверки нового соединения.

Скрипт переносит установленный открытый ключ student в authorized_keys пользователя devops и назначает devops тот же локальный установочный пароль через хеш без его вывода. Для каталога `.ssh` требуются права 700, для `authorized_keys` — 600 и владелец devops. Перед усилением SSH отдельно проверьте вход пользователем devops по ключу.

Пример Windows `~/.ssh/config`:

```sshconfig
Host devops
    HostName 127.0.0.1
    Port 2222
    User devops
    IdentityFile ~/.ssh/devops_vm
    IdentitiesOnly yes
```

В WSL HostName следует заменить фактическим Host-only адресом, а ключ хранить в Linux-файловой системе с правами 600. Отпечаток ключа хоста перед первым подключением сверяется с `sudo ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub` в консоли VM.

## 5. Служба SSH

Файл `config/99-hardening.conf` устанавливается как `/etc/ssh/sshd_config.d/99-hardening.conf`. Исходный основной файл сохраняется в `/etc/ssh/sshd_config.backup`. Основные параметры:

```text
Port 2222
PermitRootLogin no
PasswordAuthentication no
KbdInteractiveAuthentication no
PubkeyAuthentication yes
PermitEmptyPasswords no
MaxAuthTries 3
LoginGraceTime 30
AllowUsers devops
X11Forwarding no
ClientAliveInterval 300
ClientAliveCountMax 2
```

Порядок восстановления при сохранённой рабочей SSH-сессии:

```bash
sudo bash scripts/harden-ssh.sh
sudo /usr/sbin/sshd -t
sudo /usr/sbin/sshd -T | grep -E '^(port|permitrootlogin|passwordauthentication|maxauthtries|allowusers) '
sudo ss -tlnp | grep sshd
```

Скрипт комментирует конфликтующие значения парольной и интерактивной аутентификации в более ранних включаемых файлах, сохраняет их резервные копии, отключает `ssh.socket` и включает `ssh.service`. Проверяйте эффективную конфигурацию `sshd -T`, а не только текст одного файла. После настройки проброса убедитесь в новом входе `ssh devops` и в отказе для root и парольного метода. Затем можно закрыть старую сессию.

## 6. Правила межсетевого экрана

Политики: входящий трафик deny, исходящий allow. Разрешены `2222/tcp` с ограничением частоты, `80/tcp` и `443/tcp`; журналирование medium. Правила управляющего порта создаются до включения UFW.

```bash
sudo bash scripts/configure-firewall.sh
sudo ufw status verbose
hostname -f
scripts/audit.sh 5
echo $?
```

Полное имя узла: `devops-vm.devops.local`. Скрипт задаёт hostname и запись `127.0.1.1` в `/etc/hosts` сервера. Новые SSH-соединения не следует открывать сериями: `ufw limit` ограничивает частые подключения одного источника. При ошибках сначала используйте уже открытую сессию и консоль VM.

## 7. Снимки состояния

Снимки создаются по мере выполнения проверок, а не заранее:

| Имя | Момент создания |
|---|---|
| `01-clean-install` | Ubuntu установлена и обновлена, SSH на 22, гостевая система выключена |
| `02-keys-configured` | Создан devops, проверен вход по ключу и SSH-псевдоним |
| `03-ssh-hardened` | Эффективные параметры SSH и вход на новом порту проверены |

При восстановлении снимка измените проброс портов в соответствии с конфигурацией SSH этого снимка. Наличие и имена реальных снимков проверяются в VirtualBox; одна эта таблица их создания не подтверждает.

## 8. Веб-сервер

Пакеты `nginx` и `rsync` устанавливаются из репозитория Ubuntu. Конфигурация ресурса хранится в `config/devops-site` и устанавливается в `/etc/nginx/sites-available/devops-site`; активация выполняется ссылкой `/etc/nginx/sites-enabled/devops-site`. Стандартная ссылка `default` отключается. Каталог `/var/www/devops-site` принадлежит `devops:devops`, каталоги имеют права 755, файлы — 644. Пользователь рабочих процессов `www-data` читает файлы, но не изменяет их.

Самоподписанный сертификат `/etc/ssl/certs/devops.crt` содержит SAN `DNS:devops.local`, действует 365 дней и имеет права 644. Закрытый ключ `/etc/ssl/private/devops.key` принадлежит root и имеет права 600. Команда создания:

```bash
sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout /etc/ssl/private/devops.key \
  -out /etc/ssl/certs/devops.crt \
  -subj '/CN=devops.local' -addext 'subjectAltName=DNS:devops.local'
```

Восстановление итоговой конфигурации из репозитория:

```bash
sudo bash scripts/install-nginx.sh
sudo nginx -t
scripts/audit.sh 6
```

Сервер перенаправляет HTTP на HTTPS с кодом 301. HSTS не включается. После изменения конфигурации выполняются `sudo nginx -t && sudo systemctl reload nginx`. Для доставки сайта на хосте выполняются:

```bash
scp devops:/etc/ssl/certs/devops.crt ~/devops.crt
scripts/deploy.sh --dry-run
scripts/deploy.sh
curl --cacert ~/devops.crt -I https://devops.local/
```

Перед деплоем изменения должны быть зафиксированы в Git. На Windows сценарий выполняется из WSL, где настроены собственные SSH-псевдоним, ключ и запись `/etc/hosts`. Диагностика: `/var/log/nginx/devops-site.access.log`, `/var/log/nginx/devops-site.error.log`, `namei -l /var/www/devops-site/index.html`. После фактической проверки создаётся снимок `04-nginx-https`.
