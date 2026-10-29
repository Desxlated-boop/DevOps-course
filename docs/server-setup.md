# Конфигурация виртуальной машины devops-vm

Практическая работа 5. Проверено 25 октября 2026 года. Ubuntu Server 26.04.1 LTS. Репозиторий: https://github.com/Desxlated-boop/DevOps-course. Скрипт аудита и документация размещены в репозитории курса. Пароли и закрытые ключи в этот документ не включены.

## 1. Параметры машины

- Имя в VirtualBox: `DevOps_vm`; имя гостевого узла: `devops-vm`.
- UUID: `fbd0be85-9476-4a6a-9863-e4e43a522c8d`.
- Память: 2048 МБ. Процессоры: 2. Диск: 25 ГиБ, динамический VDI.
- ОС: Ubuntu Server 26.04.1 LTS, архитектура x86_64, без графической оболочки.
- Расположение VM: `C:\Users\Bogda\VirtualBox VMs\DevOps_vm`.

## 2. Сетевые интерфейсы

- Адаптер 1: NAT, `enp0s3`, MAC `08:00:27:01:e1:80`, IPv4 `10.0.2.15/24`. Доступ в Интернет и проброс SSH.
- Адаптер 2: Host-only, `VirtualBox Host-Only Ethernet Adapter`, `enp0s8`, MAC `08:00:27:3f:f2:cf`, IPv4 `192.168.56.101/24` по DHCP. Адрес хоста `192.168.56.1`, DHCP-сервер `192.168.56.100`.
- DHCP может выдать другой адрес после очистки аренды; перед использованием hosts сверить `ip -brief address`.
- Существующий `/etc/netplan/00-installer-config.yaml` оставлен. Для второго интерфейса создан `/etc/netplan/60-hostonly.yaml`, права 600:

```yaml
network:
  version: 2
  ethernets:
    enp0s8:
      dhcp4: true
      dhcp-identifier: mac
      dhcp4-overrides:
        use-routes: false
        use-dns: false
      optional: true
```

Применение: `sudo netplan generate && sudo netplan apply`. Идентификатор MAC сохраняет прежнюю DHCP-аренду; маршруты и DNS от Host-only не заменяют настройки NAT.

## 3. Правило проброса портов

Адаптер NAT, правило `ssh`, TCP: `127.0.0.1:2222` на хосте → порт `2222` гостя. Поле адреса гостя пустое. Исходное правило 2222 → 22 после смены порта sshd заменено.

Для выключенной VM из PowerShell, если требуется восстановить правило:

```powershell
& 'C:\Program Files\Oracle\VirtualBox\VBoxManage.exe' modifyvm DevOps_vm --natpf1 delete ssh
& 'C:\Program Files\Oracle\VirtualBox\VBoxManage.exe' modifyvm DevOps_vm --natpf1 'ssh,tcp,127.0.0.1,2222,,2222'
```

Для работающей VM вместо `modifyvm ... --natpf1` применяется `controlvm ... natpf1`.

## 4. Учётные записи

- `student`, UID 1000: исходная учётная запись, локальный вход и sudo для восстановления.
- `devops`, UID 1001: группы `devops sudo users`, удалённый вход по Ed25519-ключу.
- Ключ хоста Windows: `C:\Users\Bogda\.ssh\devops_vm`; открытый ключ `devops_vm.pub`. Закрытый ключ не копировать в репозиторий.
- На сервере: `/home/devops/.ssh` с правами 700 и `/home/devops/.ssh/authorized_keys` с правами 600, владелец `devops`.
- Комментарий исходного открытого ключа: `devops-vm-key`. Временные ключи автоматизированных проверок после выполнения удалены.

Конфигурация клиента Windows `C:\Users\Bogda\.ssh\config` для воспроизведения обоих вариантов подключения:

```sshconfig
Host devops
    HostName 127.0.0.1
Host devops.local
    HostName devops.local
Host devops devops.local
    Port 2222
    User devops
    IdentityFile ~/.ssh/devops_vm
    IdentitiesOnly yes
```

Блок `Host devops` был настроен до продолжения работы. Приведённый дополнительный блок `devops.local` позволяет выбрать нестандартный ключ при вызове `ssh devops.local`. Без дополнительного блока использовать `ssh -i ~/.ssh/devops_vm -p 2222 devops@devops.local`.

## 5. Служба SSH

Основной файл `/etc/ssh/sshd_config` не изменялся. Резервная копия: `/etc/ssh/sshd_config.backup`. Дополнение `/etc/ssh/sshd_config.d/99-hardening.conf`:

```text
Port 2222
PermitRootLogin no
PasswordAuthentication no
PubkeyAuthentication yes
PermitEmptyPasswords no
MaxAuthTries 3
LoginGraceTime 30
AllowUsers devops
X11Forwarding no
ClientAliveInterval 300
ClientAliveCountMax 2
```

Фактическое `KbdInteractiveAuthentication no` также проверено через `sshd -T`. Строка `#PasswordAuthentication yes` в основном файле является комментарием. Конфликтующих активных директив в дополнениях не обнаружено.

```bash
sudo sshd -t
sudo sshd -T | grep -E '^(port|permitrootlogin|passwordauthentication|maxauthtries|allowusers)'
sudo systemctl disable --now ssh.socket
sudo systemctl enable --now ssh.service
sudo systemctl restart ssh.service
sudo ss -tlnp | grep sshd
```

Ожидаются слушатели `0.0.0.0:2222` и `[::]:2222`. При настройке держать старую SSH-сессию открытой, новую проверять отдельно. Вход под root и без ключа должен завершаться `Permission denied (publickey)`.

Полное имя гостя:

```bash
sudo hostnamectl set-hostname devops-vm
sudo sed -i 's/^127\.0\.1\.1.*/127.0.1.1 devops-vm.devops.local devops-vm/' /etc/hosts
hostname -f
```

В hosts Windows `C:\Windows\System32\drivers\etc\hosts` добавлена строка `192.168.56.101 devops.local`. Это локальное сопоставление, а не запись DNS. Проверки: `ping devops.local`, затем SSH с указанием ключа и порта.

## 6. Правила межсетевого экрана

UFW активен и включается при загрузке. Политики: `deny incoming`, `allow outgoing`, маршрутизация отключена. Правила IPv4 и IPv6:

- `80/tcp ALLOW IN` — HTTP;
- `443/tcp ALLOW IN` — HTTPS;
- `2222/tcp LIMIT IN` — SSH rate-limited.

Регистрация: `medium`, журнал `/var/log/ufw.log`. Порт 22 не разрешён. Восстановление:

```bash
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow 80/tcp comment 'HTTP'
sudo ufw allow 443/tcp comment 'HTTPS'
sudo ufw limit 2222/tcp comment 'SSH rate-limited'
sudo ufw logging medium
sudo ufw enable
sudo ufw status verbose
```

Разрешить SSH до включения UFW. Для проверки блокировки с Windows: `curl.exe --max-time 3 http://192.168.56.101:8080`. В журнале проверены `SRC=192.168.56.1`, `DST=192.168.56.101`, `PROTO=TCP`, `DPT=8080`.

Аудит: `bash scripts/audit.sh`. Правильная конфигурация: 6 успешных проверок, код 0. Временное изменение MaxAuthTries на 10: 5 успешных проверок, 1 ошибка, код 1. После теста значение 3 восстановлено, служба с ошибочной конфигурацией не перезапускалась.

## 7. Снимки состояния

1. `01-clean-install` — 22.10.2026 13:55 МСК, после установки ОС. UUID `3d3d390f-2e7e-44b0-bda2-cc2c7daa3c16`.
2. `02-keys-configured` — 23.10.2026 11:46 МСК, после настройки пользователя, ключа и клиента. UUID `e7ef3c8d-54a4-4581-8d78-2081ed1d5b98`.
3. `03-ssh-hardened` — 25.10.2026, после усиления SSH, настройки UFW, имени узла и контрольных проверок. Создан на выключенной VM.
4. `04-nginx-https` — после настройки HTTPS, до доставки учебного сайта и установки Docker.

Откат изменяет гостевую систему, но не файл hosts и SSH-конфигурацию Windows. После отката на `01-clean-install` проверить гостевой порт правила NAT и использовать сначала порт 22. Не удалять исходные снимки.

## 8. Веб-сервер

- Пакет: `nginx`. Конфигурация ресурса: `/etc/nginx/sites-available/devops-site`; ссылка в `/etc/nginx/sites-enabled/`. Проверка и применение: `sudo nginx -t && sudo systemctl reload nginx`.
- Каталог `/var/www/devops-site`, владелец `devops:devops`, права каталога 755 и файлов 644. Порт 80 перенаправляет запросы на HTTPS, порт 443 обслуживает ресурс `devops.local`.
- Самоподписанный сертификат `/etc/ssl/certs/devops.crt` (root:root, 644); закрытый ключ `/etc/ssl/private/devops.key` (root:root, 600). Сертификат действует 365 дней, содержит SAN `DNS:devops.local`. Сформировать: `sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout /etc/ssl/private/devops.key -out /etc/ssl/certs/devops.crt -subj '/CN=devops.local' -addext 'subjectAltName=DNS:devops.local'`; затем установить указанные права. Для проверки клиента скопировать публичный сертификат в `~/devops.crt` и использовать `curl --cacert ~/devops.crt https://devops.local`.
- Доставка из чистой зафиксированной рабочей копии: `scripts/deploy.sh --dry-run`, затем `scripts/deploy.sh`. На Windows используется WSL 1 с rsync и собственными SSH-ключом и конфигурацией.

Для восстановления ресурса после настройки сети и SSH:

```bash
sudo apt update && sudo apt install -y nginx rsync
sudo install -d -o devops -g devops -m 755 /var/www/devops-site
sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout /etc/ssl/private/devops.key -out /etc/ssl/certs/devops.crt \
  -subj '/CN=devops.local' -addext 'subjectAltName=DNS:devops.local'
sudo chown root:root /etc/ssl/private/devops.key /etc/ssl/certs/devops.crt
sudo chmod 600 /etc/ssl/private/devops.key
sudo chmod 644 /etc/ssl/certs/devops.crt
```

Создать `/etc/nginx/sites-available/devops-site`:

```nginx
server {
    listen 80;
    listen [::]:80;
    server_name devops.local;
    return 301 https://$host$request_uri;
}
server {
    listen 443 ssl;
    listen [::]:443 ssl;
    server_name devops.local;
    ssl_certificate /etc/ssl/certs/devops.crt;
    ssl_certificate_key /etc/ssl/private/devops.key;
    ssl_protocols TLSv1.2 TLSv1.3;
    root /var/www/devops-site;
    index index.html;
    location / { try_files $uri $uri/ =404; }
    error_page 404 /404.html;
    access_log /var/log/nginx/devops-site.access.log;
    error_log /var/log/nginx/devops-site.error.log;
}
```

Создать ссылку `sudo ln -s /etc/nginx/sites-available/devops-site /etc/nginx/sites-enabled/devops-site`, отключить ссылку `default` в `sites-enabled`, проверить `sudo nginx -t` и выполнить `sudo systemctl enable --now nginx && sudo systemctl reload nginx`. Перенести публичный сертификат на хост и доставить содержимое репозитория. В Kaspersky для учебного домена `devops.local` добавлено исключение из проверки защищённых соединений; сертификат отдельно проверяется с `--cacert`.

## 9. Контейнеризация

Docker Engine 29.9.2 и плагин Compose установлены из официального репозитория Docker для Ubuntu. Пользователь devops входит в группу docker; эта группа фактически даёт привилегии root. Проект размещён в `/home/devops/app`, переменные и пароль — только в `/home/devops/app/.env` с правами 600; в Git находится лишь `.env.example`.

База PostgreSQL 16 использует именованный том `app_db_data`, подключена к внутренней сети `backend`, ожидается статус healthy. Порт БД не опубликован. Gunicorn работает от пользователя app и опубликован только на `127.0.0.1:5000`. Статический сайт сохранён, а запросы `/app/` проксируются Nginx на `http://127.0.0.1:5000/` с заголовками Host, X-Real-IP, X-Forwarded-For, X-Forwarded-Proto. Перед применением проверять `sudo nginx -t` и выполнять `sudo systemctl reload nginx`.

Для восстановления доставить `app/` через `rsync -avz --delete --exclude=.env --dry-run app/ devops:app/`, затем повторить без `--dry-run`. На сервере создать `.env` из `.env.example`, задать новый случайный пароль, `chmod 600 .env`; выполнить `cd ~/app && docker compose up -d --build`. Команда `docker compose down` сохраняет данные в томе; `docker compose down -v` удаляет их. Снимок `05-docker-compose` создан после запуска контейнеров.

В блоке HTTPS Nginx добавить перед location /:

```nginx
location /app/ {
    proxy_pass http://127.0.0.1:5000/;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
}
```

Добавление репозитория Docker при восстановлении Ubuntu 26.04:

```bash
sudo apt update && sudo apt install -y ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc
sudo tee /etc/apt/sources.list.d/docker.sources <<'EOF'
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: resolute
Components: stable
Architectures: amd64
Signed-By: /etc/apt/keyrings/docker.asc
EOF
sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo usermod -aG docker devops
```

Начать новую SSH-сессию для применения группы docker. Случайный пароль в `.env` задавать только на сервере, например `openssl rand -hex 16`; сохранять его в POSTGRES_PASSWORD, не публикуя вывод. Публичные исходники содержат Dockerfile, requirements.txt, docker-compose.yml и шаблон .env.example. Для .sh зафиксированы окончания LF в .gitattributes, чтобы Git Windows не превращал их в CRLF.

## 10. Краткая последовательность восстановления

1. Запустить `DevOps_vm`, войти как `student`, проверить оба интерфейса; при необходимости создать файл Netplan из раздела 2.
2. Если пользователя нет: `sudo adduser devops`, `sudo usermod -aG sudo devops`. Пароль задаётся отдельно и не хранится в Git.
3. Пока SSH работает на 22 и проброс 2222 → 22, разместить открытый ключ Windows:

```powershell
Get-Content "$env:USERPROFILE\.ssh\devops_vm.pub" | ssh -p 2222 devops@127.0.0.1 'mkdir -p ~/.ssh; chmod 700 ~/.ssh; cat >> ~/.ssh/authorized_keys; chmod 600 ~/.ssh/authorized_keys'
```

4. Проверить вход с `-i ~/.ssh/devops_vm`. Сохранить сессию. Создать резервную копию sshd_config и дополнение из раздела 5, проверить `sshd -t`, отключить ssh.socket и перезапустить ssh.service.
5. Изменить NAT на 2222 → 2222 и проверить новое соединение с Windows, не закрывая старое.
6. Выполнить команды UFW из раздела 6; проверить ещё одно новое соединение.
7. Настроить hostname и hosts гостя и Windows из раздела 5, сверив адрес Host-only. Проверить `hostname -f` и SSH по имени.
8. Запустить `bash scripts/audit.sh`, получить код 0, убедиться в наличии правила LIMIT и отсутствии слушателя SSH на 22.

## 11. Факультативный туннель

Проверено: Python HTTP-сервер был привязан к `127.0.0.1:8080`, внешний запрос блокировался UFW, локальный проброс `ssh -L 127.0.0.1:9090:127.0.0.1:8080 -N devops` возвращал HTTP 200 через `http://127.0.0.1:9090`. Трафик между хостом и VM шёл через SSH 2222. После демонстрации сервер и туннель остановлены.
