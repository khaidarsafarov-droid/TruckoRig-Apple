import Foundation
import UIKit

struct TelegramPollOutcome: Equatable {
    var processed = 0
    var failed = false
    var stop = false
    var delaySeconds: Int64 = 0
    var status = 0
}

/// One long-poll pass: parse updates, pair the chat, and write the journal.
@MainActor
final class TelegramEngine {
    let database: AppDatabase
    let settings: AppSettings
    let prefs: TelegramPrefs
    let session: TelegramSession
    var onJournalChanged: (() -> Void)?
    var onStateChanged: (() -> Void)?

    init(database: AppDatabase, settings: AppSettings, prefs: TelegramPrefs, session: TelegramSession) {
        self.database = database
        self.settings = settings
        self.prefs = prefs
        self.session = session
    }

    func runOnce(token: String) async -> TelegramPollOutcome {
        let offset = prefs.offset
        let request = TelegramBotAPI.getUpdates(token: token, offset: offset > 0 ? offset : nil, timeoutSeconds: TelegramBotAPI.longPollSeconds)
        let response: TelegramHTTPResponse
        do {
            response = try await session.send(request)
        } catch {
            let message = TelegramRedactor.redact(error.localizedDescription)
            return TelegramPollOutcome(failed: true, stop: TelegramSyncRules.shouldStop(errorMessage: message), delaySeconds: TelegramSyncRules.errorDelaySeconds)
        }
        if let error = TelegramBotAPI.requireOK(method: "getUpdates", status: response.status, body: response.body) {
            return TelegramPollOutcome(
                failed: true,
                stop: TelegramSyncRules.shouldStop(errorMessage: error) || response.status == 401,
                delaySeconds: TelegramSyncRules.nextDelaySeconds(status: response.status),
                status: response.status
            )
        }
        let batch = TelegramBotAPI.parseUpdates(response.body, requestedOffset: offset > 0 ? offset : nil)
        var next = offset
        var processed = 0
        var stopped = false
        for update in batch.updates {
            if update.updateId + 1 <= next { continue }
            processed += 1
            let failed = await handle(update, token: token)
            if failed {
                let count = prefs.poison(update.updateId) + 1
                prefs.setPoison(update.updateId, count)
                if TelegramSyncRules.shouldDeadLetter(previousFailures: count - 1) {
                    next = update.updateId + 1
                    prefs.offset = next
                    prefs.setPoison(update.updateId, 0)
                    if !update.chatId.isEmpty {
                        await reply(token, update.chatId, TelegramCopy.text("sync_update_skipped_error", language), removeKeyboard: false)
                    }
                } else {
                    stopped = true
                    break
                }
            } else {
                next = update.updateId + 1
                prefs.offset = next
                prefs.setPoison(update.updateId, 0)
            }
        }
        if !stopped {
            for skipped in batch.unparsedUpdateIds.sorted() where skipped + 1 > next {
                next = skipped + 1
                prefs.offset = next
            }
        }
        return TelegramPollOutcome(
            processed: processed,
            delaySeconds: TelegramSyncRules.delayAfterPoll(processed: processed, updatesNonEmpty: !batch.updates.isEmpty)
        )
    }

    /// Short poll used by pull-to-refresh and the background task.
    func catchUp(token: String) async -> TelegramPollOutcome {
        let offset = prefs.offset
        let request = TelegramBotAPI.getUpdates(token: token, offset: offset > 0 ? offset : nil, timeoutSeconds: 0)
        do {
            let response = try await session.send(request)
            if TelegramBotAPI.requireOK(method: "getUpdates", status: response.status, body: response.body) != nil {
                return TelegramPollOutcome(failed: true, stop: response.status == 401, status: response.status)
            }
            let batch = TelegramBotAPI.parseUpdates(response.body, requestedOffset: offset > 0 ? offset : nil)
            var next = offset
            for update in batch.updates where update.updateId + 1 > next {
                _ = await handle(update, token: token)
                next = update.updateId + 1
                prefs.offset = next
            }
            return TelegramPollOutcome(processed: batch.updates.count)
        } catch {
            return TelegramPollOutcome(failed: true)
        }
    }

    func applyBranding(token: String, forceName: Bool) async {
        _ = try? await session.send(TelegramBotAPI.deleteWebhook(token))
        if forceName || prefs.nameStamp != TelegramBranding.nameStamp(token) {
            if let response = try? await session.send(TelegramBotAPI.setMyName(token)),
               TelegramBotAPI.requireOK(method: "setMyName", status: response.status, body: response.body) == nil {
                prefs.nameStamp = TelegramBranding.nameStamp(token)
            }
        }
        _ = try? await session.send(TelegramBotAPI.setMyCommands(token))
        _ = try? await session.send(TelegramBotAPI.setMyCommands(token, languageCode: "fr"))
        _ = try? await session.send(TelegramBotAPI.setChatMenuButton(token))
        if prefs.photoStamp != TelegramBranding.photoStamp(token), let jpeg = TelegramLogoJPEG.encode() {
            if await session.setProfilePhoto(token: token, jpeg: jpeg) {
                prefs.photoStamp = TelegramBranding.photoStamp(token)
            }
        }
    }

    private var language: TelegramLanguage {
        TelegramLanguage.resolve(appLanguage: settings.language.rawValue, deviceIdentifier: Locale.current.identifier)
    }

    private var week: TruckingWeek { settings.truckingWeek }

    @discardableResult
    private func handle(_ update: TelegramUpdate, token: String) async -> Bool {
        let context = routerContext(for: update.chatId)
        let steps = TelegramRouter.steps(for: update, context: context)
        for step in steps {
            let failed = await perform(step, token: token)
            if failed { return true }
        }
        return false
    }

    private func perform(_ step: TelegramStep, token: String) async -> Bool {
        switch step {
        case .answer(let callbackId, let text):
            _ = try? await session.send(TelegramBotAPI.answerCallback(token: token, callbackId: callbackId, text: text))
        case .send(let chatId, let text):
            if await reply(token, chatId, text, removeKeyboard: true) { return true }
        case .plain(let chatId, let text):
            if await reply(token, chatId, text, removeKeyboard: false) { return true }
        case .markup(let chatId, let text, let markup):
            if await reply(token, chatId, text, removeKeyboard: false, markup: markup) { return true }
        case .typing(let chatId):
            _ = try? await session.send(TelegramBotAPI.sendChatAction(token: token, chatId: chatId))
        case .pair(let chatId):
            prefs.chatId = chatId
            onStateChanged?()
        case .consumeCode(let code):
            if TelegramPairingCode.matches(stored: prefs.pairingCode, candidate: code) {
                prefs.pairingCode = ""
            }
        case .markHint(let chatId):
            var hinted = prefs.hinted
            hinted.insert(chatId)
            prefs.hinted = hinted
        case .stash(let updateId, let chatId, let text, let date):
            var rows = prefs.stash().filter { $0.updateId != updateId }
            rows.append(TelegramStash(updateId: updateId, chatId: chatId, text: text, date: date))
            prefs.setStash(rows)
        case .replay(let chatId):
            if await replay(token, chatId) { return true }
        case .setImport(let chatId, let active):
            var ids = prefs.importing
            if active { ids.insert(chatId) } else { ids.remove(chatId) }
            prefs.importing = ids
        case .setRestore(let chatId, let active):
            prefs.setRestore(chatId, active: active)
        case .clearPending(let chatId):
            prefs.setReceipt(chatId, nil)
            prefs.setTeach(chatId, nil)
        case .ingest(let chatId, let text, let date):
            let body = ingestReply(text, date: date, fileName: nil)
            if await deliverIngest(token, chatId, body) { return true }
        case .importText(let chatId, let text):
            if await reply(token, chatId, importReply(text, fileName: nil), removeKeyboard: true) { return true }
        case .restoreText(let chatId, let text, let date):
            prefs.touchRestore(chatId)
            if await reply(token, chatId, restoreReply(text, date: date), removeKeyboard: true) { return true }
        case .fetch(let fetch):
            if await fetchFile(token, fetch) { return true }
        case .undo(let chatId):
            if await reply(token, chatId, undoReply(), removeKeyboard: true) { return true }
        case .setRate(let chatId, let amount):
            if await reply(token, chatId, rateReply(amount), removeKeyboard: true) { return true }
        case .dedup(let chatId):
            if await reply(token, chatId, dedupReply(), removeKeyboard: true) { return true }
        case .teachStart(let chatId):
            prefs.setTeach(chatId, TelegramTeachDraft(phase: TelegramTeach.document, body: "", tripLabel: ""))
        case .teachContinue(let chatId, let text):
            if await teach(token, chatId, text) { return true }
        case .receipt(let chatId, let data):
            if await receipt(token, chatId, data) { return true }
        }
        return false
    }

    private func routerContext(for chatId: String) -> TelegramRouterContext {
        let graph = (try? database.fetchGraph()) ?? AppDatabase.StoredGraph(
            loads: [], paychecks: [], diesel: [], maintenance: [], maintenanceArchive: [],
            photos: [], scans: [], profile: nil, expenses: [], perDiemOverrides: []
        )
        let current = week.currentWeek()
        let weekLoads = graph.loads.filter { $0.weekNumber == current.weekNumber && $0.year == current.year }
        return TelegramRouterContext(
            boundChatId: prefs.chatId,
            hintedChatIds: prefs.hinted,
            importActive: prefs.importing.contains(chatId),
            restoreActive: prefs.restoreIsActive(chatId),
            pendingReceipt: prefs.receipt(chatId) != nil,
            teachPhase: prefs.teach(chatId)?.phase,
            language: language,
            loads: graph.loads.count,
            paychecks: graph.paychecks.count,
            diesel: graph.diesel.count,
            totalLoads: graph.loads.count,
            weekLoads: weekLoads.count,
            weekGross: weekLoads.reduce(0) { $0 + $1.totalRate },
            weekMiles: weekLoads.reduce(0) { $0 + $1.totalMiles }
        )
    }

    /// `true` when Telegram did not accept the message, so the update can be retried.
    @discardableResult
    private func reply(_ token: String, _ chatId: String, _ text: String, removeKeyboard: Bool, markup: String? = nil) async -> Bool {
        guard !chatId.isEmpty, !text.isEmpty else { return false }
        let markup = markup ?? (removeKeyboard ? TelegramMenu.removeKeyboardJSON : nil)
        do {
            let response = try await session.send(TelegramBotAPI.sendMessage(token: token, chatId: chatId, text: text, replyMarkup: markup))
            return TelegramBotAPI.requireOK(method: "sendMessage", status: response.status, body: response.body) != nil
        } catch {
            return true
        }
    }

    private func deliverIngest(_ token: String, _ chatId: String, _ body: String) async -> Bool {
        if let draft = pendingDraft {
            prefs.setReceipt(chatId, draft)
            pendingDraft = nil
            let markup = TelegramReceiptData.amountPicker(
                yes: TelegramCopy.text("sync_paycheck_confirm_yes", language),
                typeOwn: TelegramCopy.text("sync_amount_type_own", language),
                cancel: TelegramCopy.text("common_cancel", language)
            )
            return await reply(token, chatId, body, removeKeyboard: false, markup: markup)
        }
        return await reply(token, chatId, body, removeKeyboard: true)
    }

    private func ingestReply(_ text: String, date: Int64?, fileName: String?) -> String {
        pendingDraft = nil
        let reference = date.map { Date(timeIntervalSince1970: TimeInterval($0)) } ?? Date()
        switch TelegramIngest.decide(text, fileName: fileName, reference: reference) {
        case .saveLoads(let loads):
            return saveLoads(loads, raw: text)
        case .missingFields(let fields):
            let labels = fields.map { TelegramIngest.fieldLabel($0, language) }.joined(separator: ", ")
            return TelegramCopy.text("sync_load_missing_fields", language, labels)
        case .confirm(let kind, let amount, let gallons, let price, let location, let driver, let weekHint):
            prefsRememberConfirm(kind: kind, amount: amount, text: text, date: date, gallons: gallons, price: price, location: location, driver: driver, weekHint: weekHint, fileName: fileName)
            return confirmAsk(kind: kind, amount: amount)
        case .paycheckAmountMissing:
            return TelegramCopy.text("sync_paycheck_amount_missing", language)
        case .unrecognized:
            return TelegramCopy.text("sync_parse_failed", language)
        }
    }

    private func prefsRememberConfirm(kind: String, amount: Double?, text: String, date: Int64?, gallons: Double?, price: Double?, location: String?, driver: String?, weekHint: String?, fileName: String?) {
        // The chat id is applied by the caller through the draft keyed later. Stored inside receipt() by the perform path.
        pendingDraft = TelegramReceiptDraft(
            kind: kind, amount: amount, text: text, awaitingTyped: amount == nil, date: date,
            gallons: gallons, pricePerGallon: price, location: location, driverName: driver,
            weekHint: weekHint, fileName: fileName
        )
    }

    private var pendingDraft: TelegramReceiptDraft?

    private func confirmAsk(kind: String, amount: Double?) -> String {
        guard let amount, amount > 0 else { return TelegramCopy.text("sync_amount_type_prompt", language) }
        let formatted = TelegramFigures.plainGrouped(amount)
        if kind == "diesel" || kind == "def" {
            return TelegramCopy.text("sync_diesel_save_ask", language, formatted)
        }
        return TelegramCopy.text("sync_paycheck_confirm_ask", language, formatted)
    }

    private func saveLoads(_ loads: [ParsedLoad], raw: String) -> String {
        let repository = LoadRepository(database: database, week: week) { [weak self] in self?.onJournalChanged?() }
        var lines: [String] = []
        for load in loads {
            let draft = LoadDraft(parsed: load)
            do {
                let saved = try repository.create(draft)
                prefs.lastLoadId = saved.id.uuidString
                prefs.lastLoadTrip = saved.tripId
                lines.append(TelegramIngest.savedLoadReply(load, added: true, language: language))
            } catch LoadRepositoryError.duplicateTripId {
                lines.append(TelegramIngest.duplicateReply(load.tripId, language))
            } catch {
                lines.append(TelegramIngest.duplicateReply(load.tripId, language))
            }
        }
        _ = raw
        return lines.joined(separator: "\n\n")
    }

    private func importReply(_ text: String, fileName: String?) -> String {
        let started = Date()
        let messages: [TelegramExportMessage]
        if let fileName, TelegramFiles.isHTML(fileName, mime: nil) || TelegramExportText.isHTMLExport(text) {
            messages = TelegramExportText.htmlMessages(text)
        } else if let fileName, TelegramFiles.isJSON(fileName, mime: nil) || TelegramExportText.isJSONExport(text) {
            messages = TelegramExportText.jsonMessages(text)
        } else {
            messages = [TelegramExportMessage(text: text, reference: nil)]
        }
        let loads = TelegramExportText.loads(in: messages)
        let cap = (fileName?.lowercased().hasSuffix(".json") == true) ? TelegramBotAPI.jsonImportMaxLoads : TelegramBotAPI.importMaxLoads
        if loads.count > cap {
            return TelegramCopy.text("sync_import_too_many", language, String(loads.count), String(cap))
        }
        if loads.isEmpty { return TelegramCopy.text("sync_import_nothing_found", language) }
        if Date().timeIntervalSince(started) > 30 {
            return TelegramCopy.text("sync_import_timeout", language, "30")
        }
        let repository = LoadRepository(database: database, week: week) { [weak self] in self?.onJournalChanged?() }
        let outcome = repository.importParsed(loads)
        let elapsed = Int(Date().timeIntervalSince(started) * 1000)
        return [
            TelegramCopy.text("sync_import_done_title", language),
            TelegramCopy.text("sync_import_result_header", language),
            TelegramCopy.text("sync_import_found", language, String(loads.count)),
            TelegramCopy.text("sync_import_added", language, String(outcome.imported.count)),
            TelegramCopy.text("sync_import_skipped", language, String(outcome.duplicates.count)),
            TelegramCopy.text("sync_import_failed", language, String(outcome.rejected.count)),
            TelegramCopy.text("sync_import_duration", language, String(elapsed)),
        ].joined(separator: "\n")
    }

    private func restoreReply(_ text: String, date: Int64?) -> String {
        let reference = date.map { Date(timeIntervalSince1970: TimeInterval($0)) } ?? Date()
        guard MessageClassifier.isLoadLike(text) else {
            return TelegramCopy.text("sync_restore_manual_not_load", language)
        }
        let loads = LoadMessageParser.parseAll(text, reference: reference)
        if loads.isEmpty { return TelegramCopy.text("sync_restore_manual_not_load", language) }
        return saveLoads(loads, raw: text).replacingOccurrences(
            of: TelegramCopy.text("load_added", language, loads[0].tripId),
            with: TelegramCopy.text(
                "sync_restore_manual_added",
                language,
                loads[0].tripId,
                TelegramFigures.miles(loads[0].totalMiles),
                TelegramFigures.plainGrouped(loads[0].totalRate)
            )
        )
    }

    private func undoReply() -> String {
        guard let load = lastLoad() else {
            prefs.lastLoadId = nil
            prefs.lastLoadTrip = nil
            return TelegramCopy.text("sync_load_undo_none", language)
        }
        _ = try? database.delete(load)
        prefs.lastLoadId = nil
        prefs.lastLoadTrip = nil
        onJournalChanged?()
        return TelegramCopy.text("sync_load_undo_done", language, load.tripId)
    }

    private func rateReply(_ amount: Double) -> String {
        guard let load = lastLoad() else {
            prefs.lastLoadId = nil
            prefs.lastLoadTrip = nil
            return TelegramCopy.text("sync_load_undo_none", language)
        }
        load.totalRate = amount
        load.updatedAt = Date()
        load.refreshDerivedFields(week: week)
        try? database.save(load)
        onJournalChanged?()
        let detail = TelegramLoadReply.detail(rate: load.totalRate, miles: load.totalMiles, origin: load.pointA ?? "", destination: load.pointB ?? "")
        return TelegramCopy.text("sync_load_rate_updated", language, load.tripId, detail)
    }

    private func lastLoad() -> Load? {
        let loads = (try? database.loads()) ?? []
        if let id = prefs.lastLoadId, let uuid = UUID(uuidString: id), let load = loads.first(where: { $0.id == uuid }) {
            return load
        }
        if let trip = prefs.lastLoadTrip {
            return loads.first { $0.tripId == TripID.normalize(trip) }
        }
        return nil
    }

    private func dedupReply() -> String {
        let started = Date()
        let loads = (try? database.loads()) ?? []
        var keep: [String: Load] = [:]
        var removed: [String] = []
        for load in loads {
            let key = TripID.normalize(load.tripId)
            if let existing = keep[key] {
                let drop = existing.updatedAt >= load.updatedAt ? load : existing
                let stay = drop.id == load.id ? existing : load
                keep[key] = stay
                _ = try? database.delete(drop)
                removed.append(drop.tripId)
            } else {
                keep[key] = load
            }
        }
        var payRemoved = 0
        var seenPay: Set<String> = []
        for paycheck in (try? database.fetchGraph().paychecks) ?? [] {
            let key = "\(paycheck.year)-\(paycheck.weekNumber)"
            if seenPay.contains(key) {
                try? database.delete(paycheck)
                payRemoved += 1
            } else {
                seenPay.insert(key)
            }
        }
        var dieselRemoved = 0
        var seenFuel: Set<String> = []
        for fill in (try? database.fetchGraph().diesel) ?? [] {
            let key = TelegramFingerprint.diesel(fill.rawText ?? "", salt: fill.sourceFileName)
            if seenFuel.contains(key) {
                try? database.delete(fill)
                dieselRemoved += 1
            } else {
                seenFuel.insert(key)
            }
        }
        if !removed.isEmpty || payRemoved > 0 || dieselRemoved > 0 { onJournalChanged?() }
        let elapsed = Int(Date().timeIntervalSince(started) * 1000)
        return TelegramDedupReport.text(
            loadsScanned: loads.count,
            loadsRemoved: removed.count,
            paychecksRemoved: payRemoved,
            dieselRemoved: dieselRemoved,
            removedTrips: removed,
            elapsedMs: elapsed,
            language: language
        )
    }

    private func teach(_ token: String, _ chatId: String, _ text: String) async -> Bool {
        guard var draft = prefs.teach(chatId) else { return false }
        if text.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("/") {
            prefs.setTeach(chatId, nil)
            return false
        }
        let move = TelegramTeach.advance(phase: draft.phase, body: draft.body, tripLabel: draft.tripLabel, reply: text)
        if move.saved {
            prefs.setTeach(chatId, nil)
            let message = TelegramCopy.text("sync_teach_saved", language, move.tripLabel, move.rateLabel)
            return await reply(token, chatId, message, removeKeyboard: true)
        }
        draft.phase = move.phase
        draft.body = move.body
        draft.tripLabel = move.tripLabel
        prefs.setTeach(chatId, draft)
        return await reply(token, chatId, TelegramCopy.text(move.messageKey, language), removeKeyboard: true)
    }

    private func receipt(_ token: String, _ chatId: String, _ data: String) async -> Bool {
        if data == TelegramReceiptData.cancel {
            prefs.setReceipt(chatId, nil)
            return await reply(token, chatId, TelegramCopy.text("sync_receipt_cancelled", language), removeKeyboard: true)
        }
        guard var draft = prefs.receipt(chatId) else {
            return await reply(token, chatId, TelegramCopy.text("sync_receipt_expired", language), removeKeyboard: true)
        }
        if data == TelegramReceiptData.typeAmount {
            draft.awaitingTyped = true
            prefs.setReceipt(chatId, draft)
            return await reply(token, chatId, TelegramCopy.text("sync_amount_type_prompt", language), removeKeyboard: true)
        }
        if let amount = TelegramReceiptData.parseAmount(data) {
            draft.amount = amount
            draft.awaitingTyped = false
        } else if data == TelegramReceiptData.load {
            draft.kind = "load"
        } else if data == TelegramReceiptData.diesel {
            draft.kind = "diesel"
        } else if data == TelegramReceiptData.def {
            draft.kind = "def"
        } else if data == TelegramReceiptData.paycheck || data == TelegramReceiptData.confirm {
            if draft.kind == "unknown" { draft.kind = "paycheck" }
        }
        if draft.kind == "load" {
            prefs.setReceipt(chatId, nil)
            let reference = draft.date.map { Date(timeIntervalSince1970: TimeInterval($0)) } ?? Date()
            let loads = LoadMessageParser.parseAll(draft.text, reference: reference)
            let replyText = loads.isEmpty
                ? TelegramCopy.text("sync_receipt_load_parse_failed", language)
                : saveLoads(loads, raw: draft.text)
            return await reply(token, chatId, replyText, removeKeyboard: true)
        }
        guard let amount = draft.amount, amount > 0 else {
            draft.awaitingTyped = true
            prefs.setReceipt(chatId, draft)
            return await reply(token, chatId, TelegramCopy.text("sync_amount_type_prompt", language), removeKeyboard: true)
        }
        prefs.setReceipt(chatId, nil)
        return await reply(token, chatId, writeReceipt(draft, amount: amount), removeKeyboard: true)
    }

    private func writeReceipt(_ draft: TelegramReceiptDraft, amount: Double) -> String {
        let date = draft.date.map { Date(timeIntervalSince1970: TimeInterval($0)) } ?? Date()
        let ref = week.week(for: date)
        let finance = FinanceRepository(database: database, week: week) { [weak self] in self?.onJournalChanged?() }
        if draft.kind == "paycheck" {
            let existing = ((try? database.fetchGraph().paychecks) ?? []).contains { $0.weekNumber == ref.weekNumber && $0.year == ref.year }
            if existing { return TelegramCopy.text("sync_paycheck_exists", language, String(ref.weekNumber)) }
            _ = try? finance.addPaycheck(amount: amount, date: date, company: nil, notes: nil, driverName: draft.driverName, rawText: draft.text, sourceFileName: draft.fileName)
            return TelegramCopy.text("sync_last_paycheck", language, TelegramFigures.plainGrouped(amount), String(ref.weekNumber))
        }
        let salt = draft.kind == "def" ? "def" : nil
        let fingerprint = TelegramFingerprint.diesel(draft.text, salt: salt)
        let duplicate = ((try? database.fetchGraph().diesel) ?? []).contains {
            TelegramFingerprint.diesel($0.rawText ?? "", salt: $0.sourceFileName == "def" ? "def" : nil) == fingerprint
        }
        if duplicate { return TelegramCopy.text("sync_duplicate_diesel", language) }
        let gallons = draft.gallons ?? 0
        let price = draft.pricePerGallon ?? (gallons > 0 ? amount / gallons : 0)
        _ = try? finance.addDiesel(
            gallons: gallons,
            totalCost: amount,
            pricePerGallon: price,
            location: draft.location,
            state: nil,
            date: date,
            odometer: nil,
            rawText: draft.text,
            sourceFileName: salt
        )
        let key = draft.kind == "def" ? "sync_last_def" : "sync_last_diesel"
        return TelegramCopy.text(key, language, TelegramFigures.plainGrouped(amount), String(ref.weekNumber))
    }

    private func fetchFile(_ token: String, _ fetch: TelegramFetch) async -> Bool {
        if let size = fetch.size, size > TelegramBotAPI.maxDownloadBytes {
            let limit = Int(TelegramBotAPI.maxDownloadBytes / (1024 * 1024))
            return await reply(token, fetch.chatId, TelegramCopy.text("sync_import_file_too_large", language, String(limit)), removeKeyboard: true)
        }
        let data: Data
        do {
            data = try await session.download(token: token, fileId: fetch.fileId)
        } catch {
            let message = TelegramCopy.text("sync_receipt_extract_failed", language, TelegramRedactor.redact(error.localizedDescription))
            return await reply(token, fetch.chatId, message, removeKeyboard: true)
        }
        if fetch.bulk || TelegramFiles.isHTML(fetch.fileName, mime: fetch.mime) || TelegramFiles.isJSON(fetch.fileName, mime: fetch.mime) || TelegramFiles.isExportText(name: fetch.fileName, mime: fetch.mime) {
            let text = String(decoding: data, as: UTF8.self)
            return await reply(token, fetch.chatId, importReply(text, fileName: fetch.fileName), removeKeyboard: true)
        }
        if let image = UIImage(data: data), let recognition = await OCRService.recognizeText(in: image), !recognition.text.isEmpty {
            let body = ingestReply(recognition.text, date: fetch.date, fileName: fetch.fileName)
            return await deliverIngest(token, fetch.chatId, body)
        }
        if let text = String(data: data, encoding: .utf8), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let body = ingestReply(text, date: fetch.date, fileName: fetch.fileName)
            return await deliverIngest(token, fetch.chatId, body)
        }
        return await reply(token, fetch.chatId, TelegramCopy.text("sync_receipt_empty_ocr", language), removeKeyboard: true)
    }

    private func replay(_ token: String, _ chatId: String) async -> Bool {
        let rows = prefs.stash().filter { $0.chatId == chatId && TelegramRestorable.isData($0.text) }
        guard !rows.isEmpty else { return false }
        prefs.setStash(prefs.stash().filter { $0.chatId != chatId })
        for row in rows {
            let text = ingestReply(row.text, date: row.date, fileName: nil)
            if await deliverIngest(token, chatId, text) { return true }
        }
        return await reply(token, chatId, TelegramCopy.text("sync_unpaired_replayed", language, String(rows.count)), removeKeyboard: true)
    }
}
