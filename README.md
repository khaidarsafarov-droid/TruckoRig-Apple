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
| Карты | Google Maps SDK for iOS 11.2.0 |
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

Доменные тесты: парсинг реальных сообщений Relay, определение года по истории чата, недельные
границы на стыке лет, статусы темпа, дедуп Trip ID, CSV round-trip, напоминание за три дня до конца
бесплатного месяца, снапшот виджета, deep link `truckorig://`, файл бэкапа в формате Android v2
(Gson, BOM, отказ от более новой схемы), Telegram Bot API (токен, long poll,
привязка чата, команды, импорт экспорта, чеки) и карта (штаты отправления, рейтинг RPM,
периоды, полигоны GeoJSON).

Шифрование, Keychain и одноразовый перенос из SwiftData проверяются целью `TruckoRigTests` на
симуляторе iPhone. Это делает workflow `.github/workflows/macos.yml`: бесплатный раннер
`macos-latest`, последний стабильный Xcode на этом образе, сборка приложения и виджета без
подписи (`CODE_SIGNING_ALLOWED=NO`) и `xcodebuild test` только для `TruckoRigTests`. Запуск —
каждый push и pull request в `main`. Linux-workflow по-прежнему гоняет только доменные тесты.

## TestFlight

Для выкладки нужен платный [Apple Developer Program](https://developer.apple.com/programs/)
($99 в год). Mac не нужен: сертификат выпускается с Windows через OpenSSL, а архив собирает
workflow `.github/workflows/testflight.yml`.

Этот workflow **не запускается** на push и pull request. Вкладка Actions → TestFlight → Run
workflow. Пока секретов нет, job останавливается до подписи и ничего не заливает.

Секреты репозитория (Settings → Secrets and variables → Actions):

| Секрет | Откуда |
|---|---|
| `APPLE_TEAM_ID` | 10 символов Team ID, [developer.apple.com/account](https://developer.apple.com/account) → Membership |
| `APP_STORE_CONNECT_KEY_ID` | App Store Connect → Users and Access → Integrations → App Store Connect API → Key ID |
| `APP_STORE_CONNECT_ISSUER_ID` | Issuer ID на той же странице |
| `APP_STORE_CONNECT_KEY_P8` | Содержимое скачанного `AuthKey_XXXX.p8`, целиком, включая строки `BEGIN` и `END`. Ключ скачивается один раз |
| `IOS_DISTRIBUTION_P12_BASE64` | Distribution-сертификат в `.p12`, затем `base64 -w 0 cert.p12` (на Windows: `certutil -encode` и убрать заголовки, либо OpenSSL) |
| `IOS_DISTRIBUTION_P12_PASSWORD` | Пароль, заданный при экспорте `.p12` |

Сертификат с Windows:

```bash
openssl req -new -newkey rsa:2048 -nodes -keyout distribution.key -out distribution.csr -subj "/CN=TruckoRig Distribution/O=TruckoRig"
```

CSR загружается в Certificates → Apple Distribution. Скачанный `.cer` собирается в `.p12`:

```bash
openssl x509 -in distribution.cer -inform DER -out distribution.pem
openssl pkcs12 -export -inkey distribution.key -in distribution.pem -out distribution.p12
```

В портале заранее создайте App ID `com.truckorig` и `com.truckorig.widget` с App Groups
(`group.com.truckorig`) и iCloud Documents (`iCloud.com.truckorig`) у приложения. Workflow
подписывает автоматически (`-allowProvisioningUpdates`) этим API-ключом и заливает `.ipa`
через `xcrun altool`. Приложение в App Store Connect с bundle id `com.truckorig` должно уже
существовать, иначе загрузка не к чему привязаться.

## Структура

```
TruckoRig/
├── App/          TruckoRigApp, AppState (composition root), RootView
├── Core/
│   ├── Models/         сущности журнала + производные поля
│   ├── Persistence/    SQLCipher (GRDB), репозитории, JSON-бэкап, мост к виджету
│   ├── Theme/          палитра Midnight & Gold, DM Sans + Roboto, soft UI
│   └── Utils/          даты, форматтеры, OCR, локация фото, логи
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

В Settings: «Создать файл бэкапа» и «Восстановить из файла». Файл — тот же JSON, что Android
пишет вручную: `TruckoRig_Backup_yyyyMMdd_HHmmss.json`, схема 2 (грузы, зарплаты, дизель, ТО и
настройки). Обмен через Files (`fileExporter` / `fileImporter`). Восстановление заменяет журнал.
Если на телефоне есть правки новее `exportedAt` файла, приложение спрашивает ещё раз. Файл новее
поддерживаемой схемы не принимается. UTF-8 BOM в начале файла снимается. Старый
`.truckorig.json` (снапшот аккаунта) этим импортом не читается.

Фото и сканы, привязанные к грузам, которых нет в файле, удаляются. Остальные медиафайлы остаются.
Токен Telegram в файл не попадает.

iCloud Drive хранит тот же JSON: `TruckoRig_Backup_<account>.json` в контейнере
`iCloud.com.truckorig`. Фото и сканы лежат рядом, отдельными файлами в `Media/<account>/`,
со своим `manifest.json`. В JSON они не входят, схема остаётся Android v2. Файл, удалённый
на телефоне, из iCloud сам не стирается и при восстановлении скачивается снова; убрать копию
можно только в приложении «Файлы». Тяжёлая выгрузка идёт фоновой задачей и ждёт зарядку, а
при включённом «Только по Wi-Fi» — ещё и Wi-Fi. Токен и секреты не выгружаются. CloudKit нет.

## Telegram

В Настройках → Telegram бот: токен от @BotFather, проверка `getMe`, привязка чата ссылкой
`https://t.me/<бот>?start=<код>`. Кнопка «Открыть BotFather» сначала пробует `tg://resolve?domain=BotFather`,
затем `https://t.me/BotFather`. Токен на экране не показывается и в бэкап не попадает.

Бот принимает тот же текст, что Android: рейс Relay, зарплату, дизель и DEF (с кнопками суммы),
`/start` `/help` `/status` `/stats` `/dedup` `/import` `/cancel` `/restore` `/undo` `/rate` `/teach`,
HTML/JSON-экспорт Telegram. Потяните журнал вниз — ответ «Синхронизация Telegram запущена», если токен сохранён.

## Карты

Экран «Карта» повторяет Android: средний RPM по штату отправления за неделю, месяц или год,
полигоны штатов, легенда, чипы, сброс и полноэкранный режим. Ключ Maps SDK for iOS в репозиторий
не коммитится. Без ключа проект собирается, а вместо карты показывается «Maps key not configured»
(«Ключ карт не настроен»).

1. В [Google Cloud Console](https://console.cloud.google.com/) откройте APIs & Services → Library и включите **Maps SDK for iOS**.
2. APIs & Services → Credentials → Create credentials → API key.
3. Ограничьте ключ: Application restrictions → **iOS apps**, bundle id `com.truckorig`. API restrictions — Maps SDK for iOS.
4. Скопируйте `Config/Secrets.example.xcconfig` в `Config/Secrets.xcconfig`. Этот файл в `.gitignore`.
5. Впишите ключ одной строкой: `GOOGLE_MAPS_API_KEY = ваш_ключ`
6. Пересоберите приложение. `Config/Maps.xcconfig` подставляет значение в `Info.plist` (`GMSApiKey`). Пустая строка — это нормальный режим CI.

Не коммитьте `Config/Secrets.xcconfig` и не вставляйте ключ в `project.pbxproj`.

Геолокация для карты не запрашивается — как на Android. Строка `NSLocationWhenInUseUsageDescription`
уже есть и относится к месту съёмки фото, не к карте.

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
- **Файл бэкапа — JSON Android v2.** Имя `TruckoRig_Backup_yyyyMMdd_HHmmss.json`. Внутри грузы,
  зарплаты, дизель, ТО и настройки, без байтов фото, сканов и чеков и без токена бота. В iCloud
  байты фото и сканов лежат отдельными файлами рядом с JSON, не внутри него. `accountId`
  локального журнала — `local_dev`, как у Android без входа. Файл чужого аккаунта не применяется.
  Google Drive с iOS снят: нет Google Sign-In, `GIDClientID`, схемы OAuth и фоновой задачи
  `com.truckorig.drive-sync`. Кодек, сопоставление журнала и правила конфликта переименованы в
  `Backup*` и ими пользуется iCloud Drive. Ktor и Supabase не используются. Экспорт для
  бухгалтера — книга Excel (.xlsx) с теми же листами, колонками и итогами, что Android SpreadsheetML.
  Список прочих расходов остаётся CSV, как в Android.
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
- **Карта.** Та же географическая эффективность, что на Android: штат отправления, периоды
  7 / 30 / 365 дней, тап по полигону, чипы шести штатов с наибольшим гроссом, сброс (в сессии
  показывает все штаты, в хранилище пустая строка, при следующем запуске снова Kentucky),
  камера `39.5, -98.35`, зум карточки 4 и полного экрана 3.5, без поворота и наклона.
  Маршрутов рейса, пинов фото, АЗС, кластеров и «моего местоположения» нет — их нет и на
  Android-карте. Имена штатов английские (`USStates` и Puerto Rico): Android в этой подписи
  держит русский каталог даже для английской локали. Кнопки «+» и «−» свои: у Maps SDK for iOS
  нет системных zoom controls. `equipmentType` и deadhead читаются из extras бэкапа, если
  они записаны; в агрегате штата типы техники смешиваются, как на Android. `MapStateMetrics`
  (штат назначения) перенесён и покрыт тестами, отдельного экрана у него нет. Кнопка карты на
  карточке рейса убрана. Экран закрыт Premium. Пока ключ не задан, списки под картой остаются,
  а холст заменяется текстом.

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

Манифест приватности (`PrivacyInfo.xcprivacy`) лежит в приложении и в виджете: трекинга нет,
данные разработчику не отправляются. `UserDefaults` объявлен причиной `CA92.1` (только свои
настройки). Размер файла внутри контейнера приложения — `C617.1`. `ITSAppUsesNonExemptEncryption`
уже `false`, поэтому при загрузке в App Store Connect вопросник про экспорт шифрования не открывается.

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
