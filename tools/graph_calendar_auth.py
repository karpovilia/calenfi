#!/usr/bin/env python3
"""Минтер токена Microsoft Graph (Calendars.ReadWrite) через device code flow.

В консоли появится код и ссылка (microsoft.com/devicelogin) — вводишь код,
логинишься. Токен сохраняется в <config>/.tokens/graph_<EMAIL>.json; при
следующем старте Calenfi переносит его в системный keyring.

Нужны переменные окружения:
  GRAPH_CLIENT_ID = <Application (client) ID из Azure AD>
  GRAPH_TENANT    = organizations | common | <tenant id/домен>   (по умолчанию organizations)
  CALENFI_TOKENS  = куда класть токены (по умолчанию <config>/.tokens)

Запуск: python tools/graph_calendar_auth.py <email>
"""
import json
import os
import re
import sys

import msal

SCOPES = [
    'https://graph.microsoft.com/Calendars.ReadWrite',
    'https://graph.microsoft.com/OnlineMeetings.ReadWrite',  # standalone Teams-встречи
]


def config_dir():
    """Тот же каталог, что у приложения (lib/data/secure/data_dir.dart)."""
    if sys.platform == 'darwin':
        return os.path.expanduser('~/Library/Application Support/calenfi')
    if os.name == 'nt':
        return os.path.join(os.environ.get('APPDATA', '~'), 'calenfi')
    base = os.environ.get('XDG_CONFIG_HOME', os.path.expanduser('~/.config'))
    return os.path.join(base, 'calenfi')


OUT_DIR = os.environ.get('CALENFI_TOKENS', os.path.join(config_dir(), '.tokens'))


def key(email):
    return re.sub(r'[^A-Z0-9]', '_', email.upper())


def main(email):
    client_id = os.environ.get('GRAPH_CLIENT_ID')
    tenant = os.environ.get('GRAPH_TENANT') or 'organizations'
    if not client_id:
        sys.exit('нет GRAPH_CLIENT_ID (Azure AD App registration)')

    authority = f'https://login.microsoftonline.com/{tenant}'
    app = msal.PublicClientApplication(client_id, authority=authority)

    flow = app.initiate_device_flow(scopes=SCOPES)
    if 'user_code' not in flow:
        sys.exit('device flow не запустился: ' + json.dumps(flow, ensure_ascii=False))
    print('\n' + flow['message'] + '\n')  # «Go to microsoft.com/devicelogin and enter CODE»

    result = app.acquire_token_by_device_flow(flow)
    if 'access_token' not in result:
        sys.exit('ошибка авторизации: ' + json.dumps(result, ensure_ascii=False))

    os.makedirs(OUT_DIR, exist_ok=True)
    path = os.path.join(OUT_DIR, f'graph_{key(email)}.json')
    with open(path, 'w') as f:
        json.dump({
            'client_id': client_id,
            'tenant': tenant,
            'access_token': result['access_token'],
            'refresh_token': result.get('refresh_token'),
            'scopes': SCOPES,
        }, f)
    print(f'✓ сохранён {path}  (refresh_token: {"есть" if result.get("refresh_token") else "НЕТ — добавь offline_access"})')


if __name__ == '__main__':
    if len(sys.argv) < 2:
        sys.exit('использование: graph_calendar_auth.py <email>')
    main(sys.argv[1])
