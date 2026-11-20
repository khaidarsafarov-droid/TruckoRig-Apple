# Что сделать перед TestFlight

Платный Apple Developer Program ещё не куплен. Пока секретов нет, workflow
**TestFlight** сам останавливается и остаётся зелёным: он не запускается на pull
request, а ручной запуск и тег `v*` без секретов ничего не подписывают.

Неподписанный IPA для Sideloadly не меняется: конфигурация **Sideload**,
`CODE_SIGNING_ALLOWED=NO`, без iCloud, без App Group и без виджета, премиум
открыт. В **Release** премиум закрыт. Team ID в репозиторий не пишется.

Mac не нужен. Все шаги ниже — с Windows.

## Идентификаторы, которые уже в проекте

| Что | Значение |
|---|---|
| Bundle ID приложения | `com.truckorig` |
| Bundle ID виджета | `com.truckorig.widget` |
| App Group | `group.com.truckorig` |
| iCloud container | `iCloud.com.truckorig` |

Бэкап лежит файлами в iCloud Documents (ubiquity), не в базе CloudKit. В портале
включается iCloud Documents и этот контейнер. Отдельную схему CloudKit создавать
не нужно.

У приложения в Release также есть capability Time Sensitive Notifications.
У виджета — только App Group `group.com.truckorig`.

## 1. Программа разработчика

1. На [developer.apple.com/programs](https://developer.apple.com/programs/) купить Apple Developer Program ($99 в год) с Apple ID, которым будете владеть приложением.
2. Дождаться, пока Membership станет Active. Team ID — 10 символов на [developer.apple.com/account](https://developer.apple.com/account) → Membership. Это секрет `APPLE_TEAM_ID`.

## 2. Идентификаторы на developer.apple.com

Certificates, Identifiers & Profiles → Identifiers.

1. App Groups → плюс → `group.com.truckorig`.
2. iCloud Containers → плюс → `iCloud.com.truckorig`.
3. App ID `com.truckorig` (явный, не wildcard):
   - App Groups → `group.com.truckorig`
   - iCloud → iCloud Documents → контейнер `iCloud.com.truckorig`
   - Time Sensitive Notifications
4. App ID `com.truckorig.widget`:
   - App Groups → тот же `group.com.truckorig`

Профили вручную не нужны: workflow подписывает автоматически ключом App Store Connect.

## 3. Запись в App Store Connect

1. [appstoreconnect.apple.com](https://appstoreconnect.apple.com) → Apps → New App.
2. Платформа iOS, имя TruckoRig, язык, bundle id `com.truckorig`, SKU любой, например `truckorig-ios`.
3. Виджет отдельно не заводится: он едет внутри IPA.

Без этой записи загрузка не к чему привяжется.

## 4. Ключ API

Users and Access → Integrations → App Store Connect API → Generate API Key.

Роль App Manager. Скачивается один раз, файл `AuthKey_XXXXXXXXXX.p8`.

- Key ID → `ASC_KEY_ID`
- Issuer ID на той же странице → `ASC_ISSUER_ID`
- Файл `.p8` целиком, в base64 → `ASC_KEY_P8_BASE64`

На Windows (Git for Windows или OpenSSL):

```bat
certutil -encode AuthKey_XXXXXXXXXX.p8 key.b64
```

Открыть `key.b64`, удалить первую и последнюю строки (`BEGIN` / `END CERTIFICATE`) и все переносы. Оставшаяся одна строка — секрет.

## 5. Сертификат Apple Distribution

На Windows, в каталоге, который не попадёт в git:

```bat
openssl req -new -newkey rsa:2048 -nodes -keyout distribution.key -out distribution.csr -subj "/CN=TruckoRig Distribution/O=TruckoRig"
```

OpenSSL есть в Git for Windows (`C:\Program Files\Git\usr\bin\openssl.exe`).

1. developer.apple.com → Certificates → плюс → **Apple Distribution**.
2. Загрузить `distribution.csr`, скачать `distribution.cer`.
3. Собрать `.p12`:

```bat
openssl x509 -in distribution.cer -inform DER -out distribution.pem
openssl pkcs12 -export -inkey distribution.key -in distribution.pem -out distribution.p12
```

Пароль, который спросили, — секрет `DIST_CERT_PASSWORD`.

Файл `.p12` в base64, так же через `certutil -encode` и без заголовков, — `DIST_CERT_P12_BASE64`.

`distribution.key` никуда не отправлять и в git не класть.

## 6. Секреты GitHub

Репозиторий → Settings → Secrets and variables → Actions → New repository secret.

| Секрет | Откуда |
|---|---|
| `APPLE_TEAM_ID` | 10 символов, Membership |
| `ASC_KEY_ID` | Key ID ключа API |
| `ASC_ISSUER_ID` | Issuer ID на странице ключей |
| `ASC_KEY_P8_BASE64` | `.p8` в base64, одной строкой |
| `DIST_CERT_P12_BASE64` | `.p12` в base64, одной строкой |
| `DIST_CERT_PASSWORD` | Пароль экспорта `.p12` |

Профилей в секретах нет.

## 7. Запуск

Actions → TestFlight → Run workflow.

Либо тег и push:

```bat
git tag v1.5.7
git push origin v1.5.7
```

Workflow собирает конфигурацию **Release** (не Sideload): виджет, App Group и iCloud остаются, премиум не открывается. Экспорт — IPA для App Store Connect, загрузка через `xcrun altool`.

Пока хотя бы одного секрета нет, job пишет, чего не хватает, и завершается успешно.

## Скриншоты iPad в App Store Connect

Приложение универсальное: тот же bundle id `com.truckorig` на iPhone и iPad. В App Store Connect, кроме кадров iPhone, нужны скриншоты iPad 13" **2752×2064** (альбом, PNG без альфы; портрет 2064×2752 тоже принимается). Готовые семь кадров лежат в `store/app-store/ipad-13`: журнал, рейс с чипами, цель, галерея, ТО, премиум и аналитика. Загрузите их в раздел скриншотов iPad 13".
