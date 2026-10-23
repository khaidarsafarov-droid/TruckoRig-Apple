import XCTest
@testable import TruckoRigDomain

final class TelegramTests: XCTestCase {

    private let token = "123456789:AAHabcdefghijklmnopqrstuvwxyz0123456789"

    func testTokenShapeRejectsJunkAndAcceptsBotFather() {
        XCTAssertTrue(TelegramTokenRules.isPlausible(token))
        XCTAssertTrue(TelegramTokenRules.isPlausible("  \(token)  "))
        XCTAssertFalse(TelegramTokenRules.isPlausible("not-a-token"))
        XCTAssertFalse(TelegramTokenRules.isPlausible("12345:short"))
        XCTAssertFalse(TelegramTokenRules.isPlausible(""))
    }

    func testSHA256MatchesTheKnownVectorAndFingerprintIsEightBytes() {
        XCTAssertEqual(
            TelegramSHA256.hex("abc"),
            "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        )
        XCTAssertEqual(TelegramSHA256.fingerprint(token).count, 16)
        XCTAssertEqual(TelegramFingerprint.diesel("fuel 10", salt: "def"), TelegramSHA256.hex("fuel 10|def"))
        XCTAssertNotEqual(TelegramFingerprint.diesel("fuel 10", salt: nil), TelegramFingerprint.diesel("fuel 10", salt: "def"))
    }

    func testRedactorHidesTheBotToken() {
        let raw = "getUpdates failed: 401 https://api.telegram.org/bot\(token)/getUpdates"
        let redacted = TelegramRedactor.redact(raw)
        XCTAssertFalse(redacted.contains(token))
        XCTAssertTrue(redacted.contains("/bot***"))
    }

    func testHealthTreats401AsAnInvalidToken() {
        let health = TelegramHealth.parse(status: 401, body: #"{"ok":false,"description":"Unauthorized"}"#)
        XCTAssertTrue(health.unauthorized)
        XCTAssertFalse(health.ok)
        let ok = TelegramHealth.parse(status: 200, body: #"{"ok":true,"result":{"username":"TruckoRigBot"}}"#)
        XCTAssertTrue(ok.ok)
        XCTAssertEqual(ok.username, "TruckoRigBot")
    }

    func testGetUpdatesParsesChatIdsCallbacksAndForwardDates() {
        let body = """
        {"ok":true,"result":[
          {"update_id":10,"edited_message":{"message_id":1,"text":"ignore","chat":{"id":1,"type":"private"}}},
          {"update_id":11,"message":{"message_id":2,"text":"/start CODE","date":100,"forward_date":90,"chat":{"id":42,"type":"private"}}},
          {"update_id":12,"callback_query":{"id":"cb","data":"rc:ok","message":{"chat":{"id":42}}}},
          {"update_id":13,"channel_post":{"text":"","chat":{"id":"7","type":"channel"}}}
        ]}
        """
        let batch = TelegramBotAPI.parseUpdates(body, requestedOffset: 10)
        XCTAssertEqual(batch.updates.map(\.updateId), [11, 12, 13])
        XCTAssertEqual(batch.unparsedUpdateIds, [10])
        XCTAssertEqual(batch.updates[0].chatId, "42")
        XCTAssertEqual(batch.updates[0].messageDateSeconds, 90)
        XCTAssertEqual(batch.updates[1].isCallbackQuery, true)
        XCTAssertEqual(batch.updates[1].text, "rc:ok")
        XCTAssertEqual(batch.updates[2].chatType, "channel")
        XCTAssertEqual(batch.nextOffset, 14)
    }

    func testLongPollRequestMatchesTheBotAPI() {
        let request = TelegramBotAPI.getUpdates(token: token, offset: 15, timeoutSeconds: 25)
        XCTAssertTrue(request.url.contains("/bot\(token)/getUpdates?"))
        XCTAssertTrue(request.url.contains("timeout=25"))
        XCTAssertTrue(request.url.contains("offset=15"))
        XCTAssertTrue(request.url.contains("allowed_updates=%5B%22message%22%2C%22callback_query%22%5D"))
        XCTAssertEqual(request.timeout, 70)
        XCTAssertEqual(TelegramBranding.setMyNameBody(), #"{"name":"TruckoRig"}"#)
        XCTAssertTrue(TelegramMenu.commandsJSON().contains(#""command":"import""#))
        XCTAssertTrue(TelegramBranding.isJPEG([0xFF, 0xD8, 0xFF, 0x00]))
        XCTAssertFalse(TelegramBranding.isJPEG([0x89, 0x50, 0x4E]))
    }

    func testPairingFollowsTheStartButton() {
        XCTAssertTrue(TelegramStart.shouldPair(text: "/start", isCallback: false, chatType: "private"))
        XCTAssertTrue(TelegramStart.shouldPair(text: "/start@bot ABC", isCallback: false, chatType: ""))
        XCTAssertEqual(TelegramStart.payload("/start AbC"), "AbC")
        XCTAssertNil(TelegramStart.payload("/start"))
        XCTAssertFalse(TelegramStart.shouldPair(text: "/start", isCallback: true, chatType: "private"))
        XCTAssertFalse(TelegramStart.shouldPair(text: "/start", isCallback: false, chatType: "group"))
        XCTAssertTrue(TelegramPairingCode.matches(stored: "ABCD2345", candidate: " abcd2345 "))
        XCTAssertFalse(TelegramPairingCode.matches(stored: "ABCD2345", candidate: "nope"))
        XCTAssertEqual(TelegramPairingCode.make(bytes: [0, 1, 2]).count, 8)
    }

    func testMenuAliasesAndRestorePhrases() {
        XCTAssertEqual(TelegramMenu.alias("/load"), "/help_load")
        XCTAssertEqual(TelegramMenu.alias("/paycheck@bot"), "/help_pay")
        XCTAssertEqual(TelegramMenu.menuButtonToCommand("📊 Статус"), "/stats")
        XCTAssertEqual(TelegramMenu.menuButtonToCommand("📦 Load"), "/help_load")
        XCTAssertTrue(TelegramMenu.isRestoreRequest("восстановить пожалуйста"))
        XCTAssertTrue(TelegramMenu.isRestoreRequest("/restore"))
        XCTAssertTrue(TelegramMenu.isRestoreRequest("please restore"))
        XCTAssertFalse(TelegramMenu.isRestoreRequest("/help"))
    }

    func testSyncPolicy() {
        XCTAssertEqual(TelegramSyncRules.backoffDelayMs(attemptIndex: 0), 1_000)
        XCTAssertEqual(TelegramSyncRules.backoffDelayMs(attemptIndex: 3), 8_000)
        XCTAssertEqual(TelegramSyncRules.backoffDelayMs(attemptIndex: 8), 30_000)
        XCTAssertFalse(TelegramSyncRules.isRetryable("401 Unauthorized token"))
        XCTAssertTrue(TelegramSyncRules.isRetryable("connection reset"))
        XCTAssertTrue(TelegramSyncRules.shouldResetOffset(conflictDetected: true, unauthorized: false))
        XCTAssertFalse(TelegramSyncRules.shouldResetOffset(conflictDetected: true, unauthorized: true))
        XCTAssertTrue(TelegramSyncRules.shouldStop(errorMessage: "getUpdates failed: 401"))
        XCTAssertEqual(TelegramSyncRules.delayAfterPoll(processed: 4, updatesNonEmpty: true), 0)
        XCTAssertEqual(TelegramSyncRules.nextDelaySeconds(status: 409), 45)
        XCTAssertFalse(TelegramSyncRules.shouldDeadLetter(previousFailures: 1))
        XCTAssertTrue(TelegramSyncRules.shouldDeadLetter(previousFailures: 2))
        XCTAssertFalse(TelegramSyncRules.restoreIsActive(lastActivityMs: 0, nowMs: 10_000, flagged: false))
        XCTAssertFalse(TelegramSyncRules.restoreIsActive(lastActivityMs: 1_000, nowMs: 400_000, flagged: true))
        XCTAssertTrue(TelegramSyncRules.restoreIsActive(lastActivityMs: 1_000, nowMs: 60_000, flagged: true))
    }

    func testLoadReplyUsesUSGrouping() {
        XCTAssertEqual(TelegramFigures.dollars(250_050), "$2,500.50")
        XCTAssertEqual(TelegramFigures.miles(1121.81), "1121.8")
        XCTAssertEqual(TelegramFigures.miles(850), "850")
        let detail = TelegramLoadReply.detail(rate: 2500, miles: 850, origin: "Garner, NC", destination: "Perrysburg, OH")
        XCTAssertEqual(detail, "$2,500.00 · 850 mi\nGarner, NC → Perrysburg, OH")
        XCTAssertEqual(TelegramLoadEdit.rateAmount("/rate 2500"), 2500)
        XCTAssertNil(TelegramLoadEdit.rateAmount("/rate"))
        XCTAssertTrue(TelegramLoadEdit.isUndo("/undo@TruckoRigBot"))
    }

    func testUnpairedChatIsHintedOnceAndStartPairsIt() {
        let update = message(11, chat: "42", text: "Trip ID: T-116KYL6KW")
        let first = TelegramRouter.steps(for: update, context: TelegramRouterContext())
        XCTAssertTrue(first.contains(.markHint("42")))
        XCTAssertTrue(first.contains(.stash(updateId: 11, chatId: "42", text: "Trip ID: T-116KYL6KW", date: nil)))
        var hinted = TelegramRouterContext(hintedChatIds: ["42"])
        let second = TelegramRouter.steps(for: update, context: hinted)
        XCTAssertFalse(second.contains { if case .plain = $0 { return true }; return false })

        let start = message(12, chat: "42", text: "/start")
        let paired = TelegramRouter.steps(for: start, context: TelegramRouterContext())
        XCTAssertTrue(paired.contains(.pair(42)))
        XCTAssertTrue(paired.contains(.send(chatId: "42", text: TelegramCopy.text("sync_welcome", .en))))
        hinted.boundChatId = 42
        let foreign = TelegramRouter.steps(for: message(13, chat: "99", text: "/help"), context: hinted)
        XCTAssertEqual(foreign, [.plain(chatId: "99", text: TelegramCopy.text("sync_chat_not_authorized", .en))])
    }

    func testCommandsUseTheAndroidCopy() {
        var context = TelegramRouterContext(boundChatId: 7, loads: 3, paychecks: 2, diesel: 1, totalLoads: 9, weekLoads: 4, weekGross: 1234.5, weekMiles: 800)
        let status = TelegramRouter.steps(for: message(1, chat: "7", text: "/status"), context: context)
        XCTAssertEqual(status, [.send(chatId: "7", text: TelegramCopy.text("sync_status", .en, "3", "2", "1"))])
        context.language = .ru
        let stats = TelegramRouter.steps(for: message(2, chat: "7", text: "/stats"), context: context)
        let expected = TelegramCopy.text("sync_stats", .ru, "9", "4", "1,234.50", "800")
        XCTAssertEqual(stats, [.send(chatId: "7", text: expected)])
        XCTAssertTrue(expected.contains("Статистика") || expected.contains("статистик") || expected.contains("📊"))

        context.language = .en
        context.importActive = true
        context.restoreActive = true
        let cancel = TelegramRouter.steps(for: message(3, chat: "7", text: "/cancel"), context: context)
        XCTAssertTrue(cancel.contains(.send(chatId: "7", text: TelegramCopy.text("sync_import_and_restore_cancelled", .en))))
        XCTAssertEqual(TelegramRouter.steps(for: message(4, chat: "7", text: "📦 Лоуд"), context: TelegramRouterContext(boundChatId: 7)), [
            .send(chatId: "7", text: TelegramCopy.text("sync_help_load", .en)),
        ])
    }

    func testRelayPasteIsAckedThenIngested() {
        let text = """
        Trip ID: T-116KYL6KW
        Total Rate: 2500.00
        Total Loaded Miles: 850 mi
        Pu-address: SWF2, Garner, NC
        Del-address: TOL3, Perrysburg, OH
        """
        let steps = TelegramRouter.steps(for: message(8, chat: "7", text: text), context: TelegramRouterContext(boundChatId: 7))
        XCTAssertEqual(steps.first, .typing(chatId: "7"))
        XCTAssertTrue(steps.contains(.plain(chatId: "7", text: TelegramCopy.text("sync_processing", .en))))
        XCTAssertTrue(steps.contains(.ingest(chatId: "7", text: text, date: nil)))
        if case .saveLoads(let loads) = TelegramIngest.decide(text) {
            XCTAssertEqual(loads.first?.tripId, "T-116KYL6KW")
            let reply = TelegramIngest.savedLoadReply(loads[0], added: true, language: .en)
            XCTAssertTrue(reply.contains("✅ New load added: T-116KYL6KW"))
            XCTAssertTrue(reply.contains("Garner, NC → Perrysburg, OH"))
        } else {
            XCTFail("expected a saved load")
        }
    }

    func testExportParsersKeepTheLatestTrip() {
        let html = """
        <div class="page_wrap"><div class="history">
        <div class="message default" id="m1"><div class="from_name">Alex</div>
        <div class="pull_right date details" title="05.07.2025 10:00:00 UTC+00:00"></div>
        <div class="text">Trip ID: T-116KYL6KW<br>Total Rate: 1000<br>Pu-address: A, Austin, TX<br>Del-address: B, Dallas, TX</div></div>
        <div class="message default" id="m2"><div class="from_name">Alex</div>
        <div class="text">Trip ID: T-116KYL6KW<br>Total Rate: 2500<br>Pu-address: SWF2, Garner, NC<br>Del-address: TOL3, Perrysburg, OH</div></div>
        </div></div>
        """
        XCTAssertTrue(TelegramExportText.isHTMLExport(html))
        XCTAssertTrue(TelegramFiles.isTelegramExportName("messages2.html"))
        XCTAssertTrue(TelegramFiles.isResultJSONName("result.json"))
        XCTAssertFalse(TelegramFiles.isChatExport(name: "load.json"))
        let loads = TelegramExportText.loads(in: TelegramExportText.htmlMessages(html))
        XCTAssertEqual(loads.count, 1)
        XCTAssertEqual(loads.first?.totalRate ?? -1, 2500, accuracy: 0.01)

        let json = """
        {"name":"Loads","type":"personal_chat","id":1,"messages":[
          {"type":"message","date_unixtime":"1751709600","text":[{"type":"plain","text":"Trip ID: T-AAA111\\nTotal Rate: 10\\nPu-address: A, Austin, TX\\nDel-address: B, Dallas, TX"}]}
        ]}
        """
        XCTAssertTrue(TelegramExportText.isJSONExport(json))
        XCTAssertEqual(TelegramExportText.jsonMessages(json).count, 1)
    }

    func testBrokerLabelAndReceiptButtons() {
        let body = "Load Number: 998877\nCarrier Rate: 2500.00"
        XCTAssertEqual(TelegramBrokerLabel.labelBefore(text: body, token: "998877"), "Load Number")
        XCTAssertEqual(TelegramBrokerLabel.labelBefore(text: body, token: "2500.00"), "Carrier Rate")
        XCTAssertNil(TelegramBrokerLabel.labelBefore(text: "Total: 10", token: "10"))
        let move = TelegramTeach.advance(phase: TelegramTeach.document, body: "", tripLabel: "", reply: body)
        XCTAssertEqual(move.phase, TelegramTeach.trip)
        XCTAssertEqual(move.messageKey, "sync_teach_ask_trip")
        XCTAssertEqual(TelegramReceiptData.parseAmount("rc:amt:4040.30"), 4040.30)
        XCTAssertEqual(
            TelegramReceiptData.matchLabel("Yes, save", yes: "Yes, save", typeOwn: "I'll type it", cancel: "Cancel", load: "Load", diesel: "Diesel", defLabel: "DEF", paycheck: "Paycheck"),
            "rc:ok"
        )
    }

    func testRussianWelcomeMatchesAndroid() {
        let welcome = TelegramCopy.text("sync_welcome", .ru)
        XCTAssertTrue(welcome.contains("Добро пожаловать"))
        XCTAssertTrue(welcome.contains("/help · /status · /import · /cancel"))
        let english = TelegramCopy.text("sync_welcome", .en)
        XCTAssertTrue(english.contains("Welcome to TruckoRig"))
        XCTAssertEqual(TelegramCopy.en.count, TelegramCopy.ru.count)
    }

    func testFrenchCopyMatchesEnglishKeysPlaceholdersAndResolution() {
        XCTAssertEqual(Set(TelegramCopy.fr.keys), Set(TelegramCopy.en.keys))
        XCTAssertEqual(Set(TelegramCopy.ru.keys), Set(TelegramCopy.en.keys))
        XCTAssertEqual(placeholderTokens(TelegramCopy.fr), placeholderTokens(TelegramCopy.en))
        XCTAssertEqual(placeholderTokens(TelegramCopy.ru), placeholderTokens(TelegramCopy.en))

        let welcome = TelegramCopy.text("sync_welcome", .fr)
        XCTAssertTrue(welcome.contains("Bienvenue dans TruckoRig"))
        XCTAssertTrue(welcome.contains("/help · /status · /import · /cancel"))
        XCTAssertFalse(welcome.contains("tu "))

        XCTAssertEqual(TelegramLanguage.resolve(appLanguage: "french", deviceIdentifier: "en_US"), .fr)
        XCTAssertEqual(TelegramLanguage.resolve(appLanguage: "system", deviceIdentifier: "fr_CA"), .fr)
        XCTAssertEqual(TelegramLanguage.resolve(appLanguage: "system", deviceIdentifier: "fr"), .fr)
        XCTAssertEqual(TelegramLanguage.resolve(appLanguage: "english", deviceIdentifier: "fr_CA"), .en)
        XCTAssertEqual(TelegramLanguage.resolve(appLanguage: "russian", deviceIdentifier: "fr"), .ru)
        XCTAssertEqual(TelegramLanguage.resolve(appLanguage: "system", deviceIdentifier: "en_US"), .en)
        XCTAssertEqual(TelegramLanguage.resolve(appLanguage: "system", deviceIdentifier: "ru_RU"), .ru)

        XCTAssertEqual(TelegramIngest.fieldLabel("trip", .fr), "Trip ID")
        XCTAssertEqual(TelegramIngest.fieldLabel("rate", .fr), "taux")
        XCTAssertEqual(TelegramIngest.fieldLabel("pickup", .fr), "adresse de cueillette")
        XCTAssertEqual(TelegramIngest.fieldLabel("delivery", .fr), "adresse de livraison")
        XCTAssertEqual(TelegramIngest.fieldLabel("miles", .fr), "milles")
        XCTAssertEqual(TelegramIngest.fieldLabel("miles", .en), "miles")
        XCTAssertEqual(TelegramIngest.fieldLabel("rate", .ru), "ставка")

        XCTAssertEqual(TelegramMenu.commandsJSON(languageCode: "en"), TelegramMenu.commandsJSON())
        XCTAssertEqual(TelegramMenu.commandsJSON(languageCode: "ru"), TelegramMenu.commandsJSON())
        XCTAssertTrue(TelegramMenu.commandsJSON(languageCode: "fr").contains("Démarrer"))
        XCTAssertFalse(TelegramMenu.commandsJSON().contains("Démarrer"))
        let frenchMenu = TelegramBotAPI.setMyCommands("123:ABC", languageCode: "fr")
        XCTAssertTrue(frenchMenu.body?.contains(#""language_code":"fr""#) == true)
        XCTAssertFalse(TelegramBotAPI.setMyCommands("123:ABC").body?.contains("language_code") == true)
    }

    private func placeholderTokens(_ table: [String: String]) -> [String: [String]] {
        let pattern = #"%(?:\d+\$)?(?:\.\d+)?[sdf@]"#
        let regex = try! NSRegularExpression(pattern: pattern)
        var tokens: [String: [String]] = [:]
        for key in table.keys.sorted() {
            let value = table[key] ?? ""
            let range = NSRange(value.startIndex..., in: value)
            tokens[key] = regex.matches(in: value, range: range).map { match in
                String(value[Range(match.range, in: value)!])
            }
        }
        return tokens
    }

    private func message(_ id: Int64, chat: String, text: String) -> TelegramUpdate {
        TelegramUpdate(updateId: id, chatId: chat, chatType: "private", text: text)
    }
}
