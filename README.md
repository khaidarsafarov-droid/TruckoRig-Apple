# TruckoRig для iOS

Нативный iOS-порт Android-приложения [TruckoRig / MyFinance](https://github.com/khaidarsafarov-droid/MyFinance) —
журнала дальнобойщика: рейсы, зарплата, дизель, ТО, фото и сканы документов.

Данные живут на телефоне. Облачного сервера, Supabase и REST-синхронизации в этом клиенте нет.

| | |
|---|---|
| Язык | Swift 5.9+ |
| UI | SwiftUI, iOS 17+ |
| База | GRDB + SQLCipher, ключ в Keychain |
| Данные | Только на телефоне, без логина |
| Карты | MapKit |
| OCR | Vision (`VNRecognizeTextRequest`, ru + en) |
| Локализация | String Catalog (`.xcstrings`), RU + EN, и ES для Premium |

## Как открыть

```bash
open TruckoRig.xcodeproj
```

Проект собирается схемой `TruckoRig` (iOS 17+). Перед запуском на устройстве укажите свою
`DEVELOPMENT_TEAM` и включите App Groups (`group.com.truckorig`).

Шрифты лежат в репозитории: DM Sans для латиницы и Roboto как запасной для кириллицы
(у DM Sans нет кириллицы, и на Android русский текст рисуется Roboto). Лицензии — OFL и Apache,
см. [`TruckoRig/Resources/DM-Sans/README.md`](TruckoRig/Resources/DM-Sans/README.md).

## Тесты доменного слоя

Вся бизнес-логика (парсер Relay, недельная математика, калькуляторы цели и RPM) лежит в
`TruckoRig/Domain` и не зависит ни от SwiftUI, ни от базы. Поэтому её можно собрать и
прогнать без Xcode — хоть на Linux-раннере:

```bash
swift test
```

198 доменных теста: парсинг реальных сообщений Relay, определение года по истории чата, недельные
границы на стыке лет, статусы темпа, дедуп Trip ID, CSV round-trip, напоминание за три дня до конца
бесплатного месяца, снапшот виджета, deep link `truckorig://`, Google Drive (формат `.tlb`,
повторная загрузка, выбор файла, условия автокопии) и Telegram Bot API (токен, long poll,
привязка чата, команды, импорт экспорта, чеки).

Шифрование, Keychain и одноразовый перенос из SwiftData проверяются целью `TruckoRigTests` на
симуляторе iPhone. Это делает workflow `.github/workflows/macos.yml` (macOS 26, Xcode 26.6):
сборка приложения и виджета без подписи и `xcodebuild test`. Linux-workflow по-прежнему гоняет
только доменные тесты.

## Структура

```
TruckoRig/
├── App/          TruckoRigApp, AppState (composition root), RootView
├── Core/
│   ├── Models/         сущности журнала + производные поля
│   ├── Persistence/    SQLCipher (GRDB), репозитории, JSON-бэкап, мост к виджету
│   ├── Theme/          палитра Midnight & Gold, DM Sans + Roboto, soft UI
│   └── Utils/          даты, форматтеры, гео, OCR, локация, логи
├── Domain/       чистая логика: парсеры, калькуляторы, модели (без UI и БД)
├── Features/     по экрану на папку, у каждого — @Observable ViewModel
├── Shared/       переиспользуемые компоненты
└── Resources/    Assets, Localizable.xcstrings, Info.plist, entitlements

TruckoRigWidget/  виджет недельной цели
Tools/            генератор и валидатор Xcode-проекта
Tests/            тесты доменного слоя (SwiftPM, Linux)
TruckoRigTests/   тесты шифрования и миграции (XCTest, симулятор)
```

## Ключевые инварианты

Это то, что нельзя сломать при доработках — каждый пункт закрыт кодом и/или тестом.

1. **Local-first.** Любая мутация сразу пишется в зашифрованную базу. Всё идёт через
   `LoadRepository` / `FinanceRepository` / `MediaRepository`, напрямую из View в базу никто не пишет.
2. **Дедуп по Trip ID.** `LoadRepository.create` отклоняет уже существующий `tripId` ошибкой
   `duplicateTripId`, UI показывает алерт. Relay пересылает один и тот же рейс десятки раз.
3. **`parsedAt` неизменяем.** Ставится один раз при создании; при редактировании меняется только
   `updatedAt`. При восстановлении из бэкапа `parsedAt` тоже не переписывается.
4. **Один локальный магазин.** База — `TruckoRig_local.sqlite` (SQLCipher, 256-битный пароль в
   Keychain, `AfterFirstUnlockThisDeviceOnly`). Логина нет: журнал открывается сразу. Если на
   телефоне остался файл от старого Sign in with Apple, он один раз переезжает в
   `TruckoRig_local.store`, а тот один раз копируется в зашифрованную базу и переименовывается
   в `.premigration`. Пароль с телефона не уезжает; перенос журнала — JSON-бэкап.
5. **Валидация парсера.** Рейс принимается, только если есть Trip ID, Total Rate > 0 и хотя бы
   один адрес PU или DEL. Иначе возвращается типизированная ошибка, и пользователь видит, чего
   именно не хватило.
6. **Недельная цель.** Активные дни = длительность от первого PU до окончания (override водителя
   или последний DEL), округление вверх, минимум 1 день. Для закрытых недель `dailyTargetNeeded`
   равен нулю, а не «весь остаток за один день».
7. **Виджет.** Обновляется сразу после сохранения/удаления рейса и после смены недельной цели
   через App Group `group.com.truckorig`. Расширение не открывает SQLCipher и не получает ключ:
   приложение заранее считает неделю теми же `GoalMoneyMath` / `WeeklyGoalCalculator` и кладёт
   в группу только готовые числа. Кнопки Камера, Сканер и Дизель открывают приложение по
   `truckorig://`.

## Бэкап

В Settings: экспорт и импорт JSON. Формат тот же, что раньше уходил в облачный снапшот, поэтому
старые файлы `.truckorig.json` по-прежнему открываются. Конфликты — last-write-wins по `updatedAt`.

Ниже в тех же Настройках — копия на Google Drive, файл `truckerload_backup_local_dev.tlb`
в скрытой папке приложения (`drive.appdata`), как на Android. Чтобы включить вход:

1. В Google Cloud Console (тот же проект, что у Android, либо любой с включённым Drive API) создайте OAuth-клиент типа **iOS**. Bundle ID: `com.truckorig`.
2. Скопируйте client id (`….apps.googleusercontent.com`) в `TruckoRig/Resources/Info.plist`, ключ `GIDClientID`, вместо `REPLACE_WITH_IOS_OAUTH_CLIENT_ID.apps.googleusercontent.com`.
3. URL scheme — перевёрнутый client id: `com.googleusercontent.apps.<префикс>`. Замените им заглушку `com.googleusercontent.apps.REPLACE_WITH_IOS_OAUTH_CLIENT_ID` в `CFBundleURLTypes`. Схему `truckorig` не удаляйте.
4. Отдельный API key, `GoogleService-Info.plist` и SHA-1 для iOS не нужны. Android client id из исходников Android на iOS не подходит. Пока заглушка на месте, кнопка входа не вызывает Google.

Автокопия: через 45 секунд после правки журнала и примерно раз в 12 часов при наличии сети (`BGTaskScheduler`, задача `com.truckorig.drive-sync`). Система сама выбирает минуту запуска.

## Telegram

В Настройках → Telegram бот: токен от @BotFather, проверка `getMe`, привязка чата ссылкой
`https://t.me/<бот>?start=<код>`. Кнопка «Открыть BotFather» сначала пробует `tg://resolve?domain=BotFather`,
затем `https://t.me/BotFather`. Токен на экране не показывается и в бэкап не попадает.

Бот принимает тот же текст, что Android: рейс Relay, зарплату, дизель и DEF (с кнопками суммы),
`/start` `/help` `/status` `/stats` `/dedup` `/import` `/cancel` `/restore` `/undo` `/rate` `/teach`,
HTML/JSON-экспорт Telegram. Потяните журнал вниз — ответ «Синхронизация Telegram запущена», если токен сохранён.

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
- **Google Drive — только `drive.appdata`.** Файл `truckerload_backup_local_dev.tlb` тот же, что
  пишет Android для локального журнала: JSON без шифрования (шифруется база на телефоне), без
  байтов фото, сканов и чеков. Вход — Google Sign-In, запись — Drive REST v3. Пока в `Info.plist`
  стоит заглушка `GIDClientID`, раздел в Настройках выключен. Рядом остаётся прежний обмен
  JSON-файлом через share sheet. Ktor и Supabase не используются. Экспорт для бухгалтера и
  список прочих расходов — CSV, а не книга Excel.
- **Telegram — бот на телефоне.** Токен от @BotFather вводится в Настройках или на последнем
  шаге первого запуска и лежит в Keychain (`com.truckorig.telegram-bot-token`). Приложение само
  ходит в `https://api.telegram.org` через `URLSession`: `getMe`, имя TruckoRig, команды, меню,
  фото, long poll `getUpdates` (25 с, `message` и `callback_query`). Серверного inbox, webhook и
  Ktor нет. Пока приложение на экране, опрос идёт в цикле; в фоне — `BGProcessingTask`
  `com.truckorig.telegram-sync` (сеть, не чаще раза в 15 минут) и догон при следующем открытии.
  Постоянного уведомления, как у Android foreground service, нет. Раздел в Настройках закрыт
  Premium, как вход в экран бота на Android; сам опрос стартует, если токен уже сохранён.
  PDF и DOCX бот не читает (та же строка, что на Android). Подписи `/teach` запоминаются, но
  шаблоны брокера в разбор Relay не подставляются. Подтверждение «rate part» не перенесено.
- **Чеки.** Дизель, зарплата и ТО читают фото через Vision (ru + en) и те же разборщики текста,
  что Android. Стоянка, весы и мойка хранят фото чека без распознавания — как в Android.
- **Камера в симуляторе.** Если камеры нет, кнопка «Фото» открывает библиотеку снимков.
- **Отзыв.** Экран «Что улучшить» собирает то же письмо (`mailto:Truckorig@gmail.com`) и не
  отправляет его сам. В подписи строка системы — `iOS`, а не `Android`.
- **Дизель.** Поля одометра и штата, уже бывшие в iOS, сохранены: Android-модель заправки их не
  требует, но существующие строки из них не выбрасываются.

## Xcode-проект генерируется

`TruckoRig.xcodeproj/project.pbxproj` собирается скриптом из дерева файлов, чтобы добавление
Swift-файла не превращалось в ручную правку pbxproj и конфликты при мерже:

```bash
python3 Tools/generate_xcodeproj.py   # после добавления/переименования файлов
python3 Tools/validate_pbxproj.py     # проверка ссылок и структуры, без Xcode
python3 Tools/check_strings.py        # ключи в коде против каталога строк
```

Виджет собирает общий с приложением набор файлов (снапшот цели, deep link, тема, форматтеры) —
список в `WIDGET_SHARED_SOURCES` в генераторе. SQLCipher в расширение не попадает.

## Локализация

Все строки — в `TruckoRig/Resources/Localizable.xcstrings` (RU + EN; у Premium есть ещё ES).
Ключи в коде литеральные, а `Tools/check_strings.py` в CI сверяет каталог с кодом: пропущенный
перевод, осиротевший ключ или несовпадение числа `%@`/`%lld` между языками валят проверку.
Доменный слой локализации не знает: ошибки — типизированные значения, а их текст живёт в
`Shared/Components/DomainMessages.swift`.

Локальная подписка для отладки — `TruckoRig/Resources/Premium.storekit` (продукт
`premium_monthly_subscription`, вводный месяц бесплатно, затем $2.99). Схема `TruckoRig`
подхватывает этот файл. Кадры 06 и 07 для App Store лежат в `store/app-store/` и
собираются `python3 Tools/render_app_store_screenshots.py`.
