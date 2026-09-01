# TruckoRig для iOS

Нативный iOS-порт Android-приложения [TruckoRig / MyFinance](https://github.com/khaidarsafarov-droid/MyFinance) —
журнала дальнобойщика: рейсы, зарплата, дизель, ТО, фото и сканы документов.

Local-first: интерфейс всегда читает локальную базу, сеть никогда не блокирует UI. Облачная
синхронизация опциональна.

| | |
|---|---|
| Язык | Swift 5.9+ |
| UI | SwiftUI, iOS 17+ |
| База | SwiftData (`@Model`, `@Query`, `ModelContext`) |
| Сеть | `URLSession` + async/await |
| Auth | Sign in with Apple, email/пароль, локальный режим |
| Карты | MapKit |
| OCR | Vision (`VNRecognizeTextRequest`, ru + en) |
| Токены | Keychain |
| Локализация | String Catalog (`.xcstrings`), RU + EN |

## Как открыть

```bash
open TruckoRig.xcodeproj
```

Проект собирается схемой `TruckoRig` (iOS 17+). Перед запуском на устройстве укажите свою
`DEVELOPMENT_TEAM` и включите capabilities: Sign in with Apple, Push Notifications,
Background Modes (Background fetch + Remote notifications), App Groups (`group.com.truckorig`).

Шрифт DM Sans не хранится в репозитории — см. [`TruckoRig/Resources/DM-Sans/README.md`](TruckoRig/Resources/DM-Sans/README.md).
Без него приложение работает и выглядит так же, только системным шрифтом.

## Тесты доменного слоя

Вся бизнес-логика (парсер Relay, недельная математика, калькуляторы цели и RPM) лежит в
`TruckoRig/Domain` и не зависит ни от SwiftUI, ни от SwiftData. Поэтому её можно собрать и
прогнать без Xcode — хоть на Linux-раннере:

```bash
swift test
```

72 теста: парсинг реальных сообщений Relay, определение года по истории чата, недельные границы
на стыке лет, статусы темпа, дедуп Trip ID, CSV round-trip.

## Структура

```
TruckoRig/
├── App/          TruckoRigApp, AppState (composition root), RootView, AppDelegate
├── Core/
│   ├── Models/         @Model-сущности + производные поля
│   ├── Persistence/    контейнеры на аккаунт, репозитории, снапшоты, бэкап, мост к виджету
│   ├── Networking/     APIClient, Endpoints, SyncEngine, JWTStore
│   ├── Auth/           AuthManager, AppleAuthHandler, EmailAuthViewModel
│   ├── Theme/          палитра Mindwell Forest, DM Sans, soft UI
│   └── Utils/          даты, форматтеры, гео, OCR, локация, логи
├── Domain/       чистая логика: парсеры, калькуляторы, модели (без UI и БД)
├── Features/     по экрану на папку, у каждого — @Observable ViewModel
├── Shared/       переиспользуемые компоненты
└── Resources/    Assets, Localizable.xcstrings, Info.plist, entitlements

TruckoRigWidget/  виджет недельной цели
Tools/            генератор и валидатор Xcode-проекта
Tests/            тесты доменного слоя (SwiftPM)
```

## Ключевые инварианты

Это то, что нельзя сломать при доработках — каждый пункт закрыт кодом и/или тестом.

1. **Local-first.** Любая мутация: сначала запись в SwiftData вместе со строкой `SyncOutbox` в
   одной транзакции, и только потом — попытка отправки. Всё пишется через
   `LoadRepository` / `FinanceRepository` / `MediaRepository`, напрямую из View в базу никто не пишет.
2. **Дедуп по Trip ID.** `LoadRepository.create` отклоняет уже существующий `tripId` ошибкой
   `duplicateTripId`, UI показывает алерт. Relay пересылает один и тот же рейс десятки раз.
3. **`parsedAt` неизменяем.** Ставится один раз при создании; при редактировании меняется только
   `updatedAt`. В `SnapshotApplier` при слиянии с сервером `parsedAt` тоже не переписывается.
4. **Изоляция аккаунтов.** `AccountScopedContainer` создаёт отдельный файл базы
   `TruckoRig_<userId>.store`; `PersistenceController.switchTo` полностью заменяет `ModelContainer`
   при смене пользователя. Настройки в `UserDefaults` и медиа-папки тоже разделены по аккаунту.
5. **Валидация парсера.** Рейс принимается, только если есть Trip ID, Total Rate > 0 и хотя бы
   один адрес PU или DEL. Иначе возвращается типизированная ошибка, и пользователь видит, чего
   именно не хватило.
6. **Недельная цель.** Активные дни = длительность от первого PU до окончания (override водителя
   или последний DEL), округление вверх, минимум 1 день. Для закрытых недель `dailyTargetNeeded`
   равен нулю, а не «весь остаток за один день».
7. **Только webhook.** На iOS нет Telegram long-poll и foreground service — пуш приходит как
   тихий сигнал `type=sync`, приложение само идёт за данными.
8. **Медиа мимо бэкенда.** Байты грузятся по presigned URL прямо в хранилище. JWT, OCR-текст и
   подписанные URL не логируются (`AppLog.redact`).
9. **Sign in with Apple** реализован рядом с email-входом, как требует App Store.

## Синхронизация

Настраивается в Settings: тумблер и адрес своего бэкенда. Пока он не задан, `SyncEngine` пишет
локальное зеркало `cloud_account_mirror_<account>.json` — данные всё равно можно выгрузить.

Эндпоинты (`/v1`): `GET|PUT /sync/snapshot`, `GET|PUT /sync/cursor`, `POST /devices/register`,
`PUT /devices/push-token`, `POST /media/upload-url`, `POST /media/complete`, плюс
`/auth/apple`, `/auth/sign-in`, `/auth/sign-up`, `/auth/refresh`.

Конфликты разрешаются last-write-wins по `updatedAt` — то же правило, что в Android-клиенте, так
что один аккаунт может работать с обоих телефонов.

## Осознанные отличия от Android-версии

Это не упущения, а решения; если нужно иначе — поменять несложно.

- **Даты вместо миллисекунд.** Там, где в Room лежали `Long` (`firstPuMillis`, `lastDelMillis`),
  здесь `Date?` (`firstPickupAt`, `lastDeliveryAt`). Значение то же, тип идиоматичный для Swift.
- **Часовой пояс остановки учитывается.** Relay печатает `07/06 08:00 EDT`. Мы разбираем и
  аббревиатуру пояса тоже, поэтому длительность PU→DEL корректна при пересечении поясов. При этом
  день рейса берётся ровно тот, что напечатан (`localDay`), а не пересчитанный в пояс телефона, —
  иначе рейс «прыгал» бы между неделями при переезде водителя.
- **Неделя не ISO.** Как и в Android: неделя начинается с воскресенья (настраивается),
  неделя №1 — та, в которую попадает 1 января. Номера недель совпадают с Android для того же рейса.
- **Без Tesseract.** Vision распознаёт русский и английский на устройстве; вторая OCR-библиотека
  добавила бы десятки мегабайт ради того же результата.
- **Без Google Drive.** Бэкап — JSON-файл в том же формате, что и облачный снапшот, через
  системный share sheet и файловый импорт (iCloud Drive, Files, почта — на выбор водителя).

## Xcode-проект генерируется

`TruckoRig.xcodeproj/project.pbxproj` собирается скриптом из дерева файлов, чтобы добавление
Swift-файла не превращалось в ручную правку pbxproj и конфликты при мерже:

```bash
python3 Tools/generate_xcodeproj.py   # после добавления/переименования файлов
python3 Tools/validate_pbxproj.py     # проверка ссылок и структуры, без Xcode
```

Виджет собирает семь общих файлов приложения (снапшот цели, тема, форматтеры) — список в
`WIDGET_SHARED_SOURCES` в генераторе.

## Локализация

Все строки — в `TruckoRig/Resources/Localizable.xcstrings` (295 ключей, RU + EN). Ключи в коде
литеральные, так что новый текст без перевода видно сразу. Доменный слой локализации не знает:
ошибки — типизированные значения, а их текст живёт в `Shared/Components/DomainMessages.swift`.
