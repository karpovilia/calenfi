#!/usr/bin/env python3
"""Минтер OAuth-токена с доступом к Google Calendar (read-write).

Открывает браузер для согласия и сохраняет токен в <config>/.tokens/gcal_<EMAIL>.json
в формате google.oauth2 Credentials.to_json(). При следующем старте Calenfi
переносит его в системный keyring (см. lib/data/secure/secret_store.dart).

Запуск:  python tools/google_calendar_auth.py <email> [email ...]
Переменные окружения:
  GOOGLE_CLIENT_SECRETS — путь к client_secret.json OAuth-клиента (обязательно)
  CALENFI_TOKENS        — куда класть токены (по умолчанию <config>/.tokens)
"""
import os
import re
import sys

from google_auth_oauthlib.flow import InstalledAppFlow

SCOPES = [
    'https://www.googleapis.com/auth/calendar',
    'https://www.googleapis.com/auth/meetings.space.created',  # standalone Meet
]
CLIENT_SECRETS = os.environ.get('GOOGLE_CLIENT_SECRETS', 'client_secret.json')


def config_dir() -> str:
    """Тот же каталог, что у приложения (lib/data/secure/data_dir.dart)."""
    if sys.platform == 'darwin':
        return os.path.expanduser('~/Library/Application Support/calenfi')
    if os.name == 'nt':
        return os.path.join(os.environ.get('APPDATA', '~'), 'calenfi')
    base = os.environ.get('XDG_CONFIG_HOME', os.path.expanduser('~/.config'))
    return os.path.join(base, 'calenfi')


OUT_DIR = os.environ.get('CALENFI_TOKENS', os.path.join(config_dir(), '.tokens'))


def key(email: str) -> str:
    return re.sub(r'[^A-Z0-9]', '_', email.upper())


def main(emails):
    os.makedirs(OUT_DIR, exist_ok=True)
    for email in emails:
        print(f'→ авторизация календаря для {email} (нажми «Разрешить» в браузере)…')
        flow = InstalledAppFlow.from_client_secrets_file(CLIENT_SECRETS, SCOPES)
        creds = flow.run_local_server(
            port=0,
            login_hint=email,
            prompt='consent',
            access_type='offline',
            open_browser=True,
        )
        path = os.path.join(OUT_DIR, f'gcal_{key(email)}.json')
        with open(path, 'w') as f:
            f.write(creds.to_json())
        print(f'✓ сохранён {path}')


if __name__ == '__main__':
    if len(sys.argv) < 2:
        sys.exit('использование: google_calendar_auth.py <email> [email ...]')
    main(sys.argv[1:])
