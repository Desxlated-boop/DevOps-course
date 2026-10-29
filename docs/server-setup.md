# Конфигурация виртуальной машины devops-vm

Практическая работа 5. Проверено 25 октября 2026 года. Ubuntu Server 26.04.1 LTS. Репозиторий: https://github.com/Desxlated-boop/DevOps-course. Изменения подготовлены локально, без отправки на GitHub. Пароли и закрытые ключи в этот документ не включены.

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

Откат изменяет гостевую систему, но не файл hosts и SSH-конфигурацию Windows. После отката на `01-clean-install` проверить гостевой порт правила NAT и использовать сначала порт 22. Не удалять исходные снимки.

## 8. Краткая последовательность восстановления

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

## 9. Факультативный туннель

Проверено: Python HTTP-сервер был привязан к `127.0.0.1:8080`, внешний запрос блокировался UFW, локальный проброс `ssh -L 127.0.0.1:9090:127.0.0.1:8080 -N devops` возвращал HTTP 200 через `http://127.0.0.1:9090`. Трафик между хостом и VM шёл через SSH 2222. После демонстрации сервер и туннель остановлены.
