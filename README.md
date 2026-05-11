# Личный чат-сервер (Mattermost)

Самохостинговый чат для общения с близкими: сквозной HTTPS, мобильный клиент из
App Store / Google Play, без посредников. Запускается одной командой
`docker compose up -d`.

## Что внутри

- **Mattermost Team Edition** — open-source чат (каналы, личные сообщения, файлы,
  голос/видео через звонки, треды). Официальный iOS-клиент в App Store:
  [Mattermost](https://apps.apple.com/app/mattermost/id1257222717).
- **PostgreSQL 15** — БД для Mattermost.
- **Caddy 2** — реверс-прокси с автоматическим Let's Encrypt HTTPS.

## Требования к VPS

- Линукс с Docker и Docker Compose v2 (Ubuntu 22.04/24.04, Debian 12 — норм).
- 2 vCPU, 2 ГБ RAM, 20 ГБ диска — комфортный минимум для небольшой компании.
- Публичный IPv4, открытые порты **80/tcp** и **443/tcp** (для HTTPS и
  выпуска сертификата).
- Желательно: провайдер не в РФ/РБ, иначе домен/IP могут блокироваться.
  Подойдут Hetzner (DE/FI), Scaleway (FR), DigitalOcean, Vultr, Time4VPS и т.п.

## Развёртывание на сервере, где УЖЕ что-то крутится (VPN, бот и т.п.)

**Если на сервере уже работают другие сервисы — сначала прогони
`preflight.sh`**, он покажет, не будут ли конфликты:

```bash
git clone <URL этого репо> chat-server && cd chat-server
sudo bash preflight.sh
```

Скрипт ничего не меняет, только читает. Он покажет:
- что уже слушает 80/443 (Caddy для Mattermost их хочет);
- какие сервисы VPN/прокси активны;
- статус ufw/iptables.

**Если 80/443 уже заняты** (например, на сервере nginx или VPN-панель типа
3x-ui/x-ui/marzban) — есть варианты:

1. **Поставить Mattermost за тот же реверс-прокси, что уже стоит.**
   Самый правильный путь. Выкини сервис `caddy` из `docker-compose.yml`,
   проброс порта Mattermost наружу (например, `127.0.0.1:8065:8065`)
   и добавь location в свой существующий nginx/caddy.
2. **Сменить порты в `.env`** на нестандартные, например `HTTPS_PORT=8443`.
   Минус: iOS-клиент Mattermost подключится по `https://host:8443`, и
   Let's Encrypt не выпустит сертификат по HTTP-01 (нужен публичный 80) —
   придётся DNS-01 или свой домен за CDN.
3. **Поднять чат на втором IP**, если у VPS их несколько.

**Не делай этого на работающем сервере:**
- `ufw --force enable` — может выкинуть тебя по SSH, если нет allow для 22.
- `iptables -F` — то же самое.
- `docker system prune -a` — снесёт образы чужих контейнеров.

Базы данных Postgres, тома Docker и сети у нашего стека свои
(`chat-server_default`, `./volumes/...`), с чужими не пересекаются.

## Как развернуть с нуля (чистый VPS)

### 1. Подготовь VPS

```bash
# Под root или через sudo
apt update && apt install -y docker.io docker-compose-v2
systemctl enable --now docker

# Файрвол ставь ТОЛЬКО если его ещё нет. Если на сервере уже работает
# VPN/бот без ufw — не включай ufw, чтобы не сломать им сеть.
# Для чистого сервера:
apt install -y ufw
ufw allow OpenSSH
ufw allow 80/tcp
ufw allow 443/tcp
ufw --force enable
```

### 2. Склонируй репозиторий

```bash
git clone <URL этого репо> chat-server
cd chat-server
```

### 3. Настрой `.env`

```bash
cp .env.example .env
# Сгенерируй сильный пароль для БД
sed -i "s|REPLACE_WITH_STRONG_PASSWORD|$(openssl rand -base64 32 | tr -d '=+/')|" .env
# Открой и впиши SITE_HOSTNAME и LETSENCRYPT_EMAIL
nano .env
```

**Про `SITE_HOSTNAME` без своего домена:** используй бесплатный wildcard-DNS.
Допустим, IP твоего VPS `203.0.113.42`, тогда подойдёт любой из этих
хостнеймов (выбери один и впиши в `.env`):

- `203-0-113-42.sslip.io`
- `203.0.113.42.nip.io`

Они резолвятся в IP автоматически, ничего регистрировать не надо. Let's Encrypt
их понимает и выпускает валидный сертификат — мобильное приложение Mattermost
подключится без ругани.

Если хочешь красивее — заведи бесплатный поддомен на
[duckdns.org](https://www.duckdns.org/) (5 минут) и впиши его.

### 4. Запусти

```bash
docker compose up -d
docker compose logs -f caddy   # дождись строки "certificate obtained successfully"
```

Открой `https://<SITE_HOSTNAME>` в браузере. Mattermost попросит создать
**первого пользователя — это и будет администратор сервера**.

### 5. Создай команду и добавь близких

1. В веб-интерфейсе создай команду (Team), например «family».
2. **System Console → Authentication → Signup** — оставь регистрацию
   выключенной (в `docker-compose.yml` уже `ENABLEOPENSERVER=false`).
3. Приглашай людей через **Main Menu → Invite People → Copy Invite Link**
   или по email. Ссылку-приглашение отправляй им любым каналом — она
   одноразовая (можно ограничить).

### 6. Подключение с iPhone

1. App Store → установить **Mattermost**.
2. На экране входа в поле **Server URL** ввести `https://<SITE_HOSTNAME>`.
3. Залогиниться. Всё.

То же самое для Android, macOS, Windows, Linux — клиенты на
[mattermost.com/download](https://mattermost.com/download/).

## Обслуживание

```bash
# Логи
docker compose logs -f mattermost

# Обновление
docker compose pull && docker compose up -d

# Бэкап (останови чат на время бэкапа для целостности)
docker compose stop
tar czf backup-$(date +%F).tar.gz volumes/
docker compose start
```

## Безопасность

- Регистрация снаружи отключена — новые юзеры только по инвайту.
- Сам Mattermost умеет E2E-чаты? **Нет, на сервере сообщения хранятся
  расшифрованными.** Но: TLS наружу, доступ к серверу только у тебя — это
  сильно лучше публичных мессенджеров. Если нужен E2EE — Matrix/Element
  или Signal.
- Не забудь регулярные обновления (`apt upgrade`, `docker compose pull`).
- SSH — только по ключу, root login disabled, fail2ban не помешает.

## Обход блокировок

- `443/tcp` — это обычный HTTPS, его блокировать массово не получится.
- Если конкретный IP попадёт в блок-листы, поможет смена IP у провайдера
  или включение перед сервером Cloudflare (бесплатный план): домен в
  Cloudflare → proxy ON → в `SITE_HOSTNAME` пишешь свой домен, Caddy получает
  сертификат через HTTP-01 challenge (нужно временно выключить Cloudflare
  proxy на момент выпуска, потом включить обратно), или использовать DNS-01.
- Если используешь `*.sslip.io` / `*.nip.io`, прятать за Cloudflare не
  получится — там придётся свой домен.
