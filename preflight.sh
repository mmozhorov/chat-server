#!/usr/bin/env bash
# Pre-flight check: убедиться, что развёртывание чата НЕ сломает уже запущенные
# сервисы (VPN, TG-бот и т.д.). Скрипт только читает — ничего не меняет.
#
# Использование:  sudo bash preflight.sh

set -u

red()    { printf '\033[31m%s\033[0m\n' "$*"; }
green()  { printf '\033[32m%s\033[0m\n' "$*"; }
yellow() { printf '\033[33m%s\033[0m\n' "$*"; }
bold()   { printf '\033[1m%s\033[0m\n' "$*"; }

if [[ $EUID -ne 0 ]]; then
  red "Запусти под root (sudo bash preflight.sh) — без него часть проверок не сработает."
  exit 1
fi

problems=0

bold "=== 1. Docker ==="
if command -v docker >/dev/null 2>&1; then
  green "  docker: $(docker --version)"
  if docker compose version >/dev/null 2>&1; then
    green "  docker compose: $(docker compose version | head -1)"
  else
    red "  docker compose v2 НЕ установлен"
    problems=$((problems+1))
  fi
else
  red "  docker НЕ установлен"
  problems=$((problems+1))
fi

bold ""
bold "=== 2. Что уже крутится в Docker (НЕ ТРОГАЕМ) ==="
if command -v docker >/dev/null 2>&1; then
  docker ps --format 'table {{.Names}}\t{{.Image}}\t{{.Ports}}' || true
else
  yellow "  docker не установлен — пропускаю"
fi

bold ""
bold "=== 3. Занятые порты 80 / 443 ==="
for port in 80 443; do
  user=$(ss -ltnp 2>/dev/null | awk -v p=":$port$" '$4 ~ p {print $0}')
  if [[ -n "$user" ]]; then
    red "  Порт $port ЗАНЯТ:"
    echo "    $user"
    problems=$((problems+1))
  else
    green "  Порт $port свободен"
  fi
done

bold ""
bold "=== 4. Системные сервисы, похожие на VPN / прокси ==="
matches=$(systemctl list-units --type=service --state=running --no-pager --no-legend 2>/dev/null \
  | awk '{print $1}' \
  | grep -iE 'wireguard|wg-quick|openvpn|xray|sing-box|hysteria|v2ray|shadowsocks|trojan|nginx|caddy|apache|haproxy|3x-ui|x-ui|amnezia' || true)
if [[ -n "$matches" ]]; then
  yellow "  Найдены сервисы — проверь, не используют ли они 80/443:"
  echo "$matches" | sed 's/^/    /'
else
  green "  Подозрительных systemd-сервисов не нашёл"
fi

bold ""
bold "=== 5. Процессы, слушающие что-либо снаружи ==="
ss -ltnp 2>/dev/null | awk 'NR==1 || $4 !~ /127\.0\.0\.1|::1/' | column -t || true

bold ""
bold "=== 6. UFW / iptables ==="
if command -v ufw >/dev/null 2>&1; then
  ufw_status=$(ufw status 2>/dev/null | head -1)
  yellow "  UFW: $ufw_status"
  if [[ "$ufw_status" == *"inactive"* ]]; then
    yellow "  UFW выключен — НЕ включай его на работающем сервере без явного allow ssh!"
  fi
fi
yellow "  iptables INPUT (первые правила):"
iptables -S INPUT 2>/dev/null | head -10 | sed 's/^/    /'

bold ""
bold "=== ИТОГО ==="
if [[ $problems -eq 0 ]]; then
  green "Конфликтов не нашёл. Можно запускать docker compose up -d."
else
  red "Найдено проблем: $problems. Разберись с ними ПЕРЕД запуском."
  exit 2
fi
