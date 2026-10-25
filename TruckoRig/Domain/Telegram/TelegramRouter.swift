import Foundation

public struct TelegramRouterContext: Equatable, Sendable {
    public var boundChatId: Int64?
    public var hintedChatIds: Set<String>
    public var importActive: Bool
    public var restoreActive: Bool
    public var pendingReceipt: Bool
    public var teachPhase: String?
    public var language: TelegramLanguage
    public var loads: Int
    public var paychecks: Int
    public var diesel: Int
    public var totalLoads: Int
    public var weekLoads: Int
    public var weekGross: Double
    public var weekMiles: Double
    public var measurementSystem: MeasurementSystem

    public init(
        boundChatId: Int64? = nil,
        hintedChatIds: Set<String> = [],
        importActive: Bool = false,
        restoreActive: Bool = false,
        pendingReceipt: Bool = false,
        teachPhase: String? = nil,
        language: TelegramLanguage = .en,
        loads: Int = 0,
        paychecks: Int = 0,
        diesel: Int = 0,
        totalLoads: Int = 0,
        weekLoads: Int = 0,
        weekGross: Double = 0,
        weekMiles: Double = 0,
        measurementSystem: MeasurementSystem = .miles
    ) {
        self.boundChatId = boundChatId
        self.hintedChatIds = hintedChatIds
        self.importActive = importActive
        self.restoreActive = restoreActive
        self.pendingReceipt = pendingReceipt
        self.teachPhase = teachPhase
        self.language = language
        self.loads = loads
        self.paychecks = paychecks
        self.diesel = diesel
        self.totalLoads = totalLoads
        self.weekLoads = weekLoads
        self.weekGross = weekGross
        self.weekMiles = weekMiles
        self.measurementSystem = measurementSystem
    }
}

public struct TelegramFetch: Equatable, Sendable {
    public var chatId: String
    public var fileId: String
    public var fileName: String?
    public var mime: String?
    public var size: Int64?
    public var date: Int64?
    public var bulk: Bool
}

public enum TelegramStep: Equatable, Sendable {
    case answer(callbackId: String, text: String)
    case send(chatId: String, text: String)
    case plain(chatId: String, text: String)
    case markup(chatId: String, text: String, markup: String)
    case typing(chatId: String)
    case pair(Int64)
    case consumeCode(String)
    case markHint(String)
    case stash(updateId: Int64, chatId: String, text: String, date: Int64?)
    case replay(chatId: String)
    case setImport(chatId: String, active: Bool)
    case setRestore(chatId: String, active: Bool)
    case clearPending(chatId: String)
    case ingest(chatId: String, text: String, date: Int64?)
    case importText(chatId: String, text: String)
    case restoreText(chatId: String, text: String, date: Int64?)
    case fetch(TelegramFetch)
    case undo(chatId: String)
    case setRate(chatId: String, amount: Double)
    case dedup(chatId: String)
    case teachStart(chatId: String)
    case teachContinue(chatId: String, text: String)
    case receipt(chatId: String, data: String)
}

/// Routes one Telegram update the way `TelegramUpdateDispatcher` does.
public enum TelegramRouter {
    public static func steps(for update: TelegramUpdate, context: TelegramRouterContext) -> [TelegramStep] {
        let language = context.language
        let gate = gate(for: update, context: context)
        var steps: [TelegramStep] = []

        switch gate {
        case .foreign:
            if let callback = update.callbackQueryId {
                steps.append(.answer(callbackId: callback, text: TelegramCopy.text("sync_chat_not_authorized", language)))
            }
            if let chat = Int64(update.chatId), context.boundChatId != nil, context.boundChatId != chat {
                steps.append(.plain(chatId: update.chatId, text: TelegramCopy.text("sync_chat_not_authorized", language)))
            }
            return steps
        case .unpaired:
            if !update.isCallbackQuery && TelegramRestorable.isData(update.text) {
                steps.append(.stash(updateId: update.updateId, chatId: update.chatId, text: update.text, date: update.messageDateSeconds))
            }
            let hint = TelegramCopy.text("sync_chat_pair_required", language)
            if update.isCallbackQuery, let callback = update.callbackQueryId {
                steps.append(.answer(callbackId: callback, text: hint))
            } else if !context.hintedChatIds.contains(update.chatId) {
                steps.append(.markHint(update.chatId))
                steps.append(.plain(chatId: update.chatId, text: hint))
            }
            return steps
        case .justPaired:
            steps.append(.pair(Int64(update.chatId) ?? 0))
            if let payload = TelegramStart.payload(update.text) {
                steps.append(.consumeCode(payload))
            }
        case .accepted:
            break
        }

        if shouldAck(update) {
            steps.append(.typing(chatId: update.chatId))
            steps.append(.plain(chatId: update.chatId, text: TelegramCopy.text("sync_processing", language)))
        }

        if update.isCallbackQuery {
            steps.append(contentsOf: callback(update, context: context, justPaired: gate == .justPaired))
            return steps
        }

        var raw = update.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if TelegramMenu.isMenuButton(raw) {
            raw = TelegramMenu.menuButtonToCommand(raw) ?? raw
        }
        raw = TelegramMenu.alias(raw)

        if TelegramLoadEdit.isUndo(raw) {
            steps.append(.undo(chatId: update.chatId))
            return steps
        }
        if TelegramLoadEdit.isRate(raw) {
            if let amount = TelegramLoadEdit.rateAmount(raw) {
                steps.append(.setRate(chatId: update.chatId, amount: amount))
            } else {
                steps.append(.send(chatId: update.chatId, text: TelegramCopy.text("sync_load_rate_bad", language)))
            }
            return steps
        }
        if TelegramLoadEdit.isTeach(raw) {
            steps.append(.teachStart(chatId: update.chatId))
            steps.append(.send(chatId: update.chatId, text: TelegramCopy.text("sync_teach_start", language)))
            return steps
        }
        if TelegramMenu.isSlash(raw, "/start") {
            steps.append(.send(chatId: update.chatId, text: TelegramCopy.text("sync_welcome", language)))
            steps.append(.replay(chatId: update.chatId))
            return steps
        }
        if TelegramMenu.isSlash(raw, "/help") {
            steps.append(.send(chatId: update.chatId, text: TelegramCopy.text("sync_help", language)))
            return steps
        }
        if TelegramMenu.isSlash(raw, "/status") {
            steps.append(.send(chatId: update.chatId, text: status(context)))
            return steps
        }
        if TelegramMenu.isSlash(raw, "/stats") {
            steps.append(.send(chatId: update.chatId, text: stats(context)))
            return steps
        }
        if TelegramMenu.isSlash(raw, "/dedup") {
            steps.append(.send(chatId: update.chatId, text: TelegramCopy.text("sync_dedup_running", language)))
            steps.append(.dedup(chatId: update.chatId))
            return steps
        }
        if TelegramMenu.isSlash(raw, "/cancel") {
            steps.append(.setImport(chatId: update.chatId, active: false))
            steps.append(.setRestore(chatId: update.chatId, active: false))
            steps.append(.clearPending(chatId: update.chatId))
            steps.append(.send(chatId: update.chatId, text: cancelText(context, language: language)))
            return steps
        }
        if TelegramMenu.isSlash(raw, "/import") {
            steps.append(.setRestore(chatId: update.chatId, active: false))
            steps.append(.setImport(chatId: update.chatId, active: true))
            steps.append(.send(chatId: update.chatId, text: TelegramCopy.text("sync_import_prompt", language)))
            return steps
        }
        if TelegramMenu.isSlash(raw, "/help_load") {
            steps.append(.send(chatId: update.chatId, text: TelegramCopy.text("sync_help_load", language)))
            return steps
        }
        if TelegramMenu.isSlash(raw, "/help_pay") {
            steps.append(.send(chatId: update.chatId, text: TelegramCopy.text("sync_help_pay", language)))
            return steps
        }
        if TelegramMenu.isRestoreRequest(raw) {
            steps.append(.setImport(chatId: update.chatId, active: false))
            steps.append(.setRestore(chatId: update.chatId, active: true))
            steps.append(.send(chatId: update.chatId, text: TelegramCopy.text("sync_restore_manual_prompt", language)))
            return steps
        }

        if raw.isEmpty && (update.photoFileId != nil || update.documentFileId != nil) {
            steps.append(contentsOf: document(update, context: context))
            return steps
        }
        if raw.isEmpty {
            steps.append(.send(chatId: update.chatId, text: TelegramCopy.text("sync_no_new_data", language)))
            return steps
        }
        if update.photoFileId != nil || update.documentFileId != nil {
            steps.append(contentsOf: document(update, context: context))
            return steps
        }
        if context.importActive {
            steps.append(.importText(chatId: update.chatId, text: raw))
            return steps
        }
        if context.restoreActive {
            steps.append(.restoreText(chatId: update.chatId, text: raw, date: update.messageDateSeconds))
            return steps
        }
        if context.pendingReceipt {
            let data = TelegramReceiptData.matchLabel(
                raw,
                yes: TelegramCopy.text("sync_paycheck_confirm_yes", language),
                typeOwn: TelegramCopy.text("sync_amount_type_own", language),
                cancel: TelegramCopy.text("common_cancel", language),
                load: TelegramCopy.text("sync_receipt_btn_load", language),
                diesel: TelegramCopy.text("sync_receipt_btn_diesel", language),
                defLabel: TelegramCopy.text("sync_receipt_btn_def", language),
                paycheck: TelegramCopy.text("sync_receipt_btn_paycheck", language)
            )
            if let data {
                steps.append(.receipt(chatId: update.chatId, data: data))
                return steps
            }
        }
        if context.teachPhase != nil && !raw.hasPrefix("/") {
            steps.append(.teachContinue(chatId: update.chatId, text: raw))
            return steps
        }
        steps.append(.ingest(chatId: update.chatId, text: raw, date: update.messageDateSeconds))
        return steps
    }

    public static func status(_ context: TelegramRouterContext) -> String {
        TelegramCopy.text(
            "sync_status",
            context.language,
            String(context.loads),
            String(context.paychecks),
            String(context.diesel)
        )
    }

    public static func stats(_ context: TelegramRouterContext) -> String {
        let shown = MeasurementUnits.displayDistance(context.weekMiles, system: context.measurementSystem)
        let key = context.measurementSystem == .kilometers ? "sync_stats_km" : "sync_stats"
        return TelegramCopy.text(
            key,
            context.language,
            String(context.totalLoads),
            String(context.weekLoads),
            TelegramFigures.plainGrouped(context.weekGross),
            TelegramFigures.grouped(Int64(shown.rounded()))
        )
    }

    public static func gate(for update: TelegramUpdate, context: TelegramRouterContext) -> TelegramChatGate {
        guard let chat = Int64(update.chatId) else { return .foreign }
        if let bound = context.boundChatId {
            return bound == chat ? .accepted : .foreign
        }
        if TelegramStart.shouldPair(text: update.text, isCallback: update.isCallbackQuery, chatType: update.chatType) {
            return .justPaired
        }
        return .unpaired
    }

    private static func callback(_ update: TelegramUpdate, context: TelegramRouterContext, justPaired: Bool) -> [TelegramStep] {
        let language = context.language
        var planned: [TelegramStep] = []
        let action = TelegramReceiptData.isCallback(update.text)
            ? update.text
            : TelegramReceiptData.matchLabel(
                update.text,
                yes: TelegramCopy.text("sync_paycheck_confirm_yes", language),
                typeOwn: TelegramCopy.text("sync_amount_type_own", language),
                cancel: TelegramCopy.text("common_cancel", language),
                load: "",
                diesel: "",
                defLabel: "",
                paycheck: ""
            )
        if let action, context.pendingReceipt || TelegramReceiptData.isCallback(update.text) {
            if let callback = update.callbackQueryId {
                planned.append(.answer(callbackId: callback, text: "OK"))
            }
            planned.append(.receipt(chatId: update.chatId, data: action))
            return planned
        }
        let command = TelegramMenu.menuButtonToCommand(update.text)
            ?? (update.text.hasPrefix("cmd:") ? "/" + String(update.text.dropFirst(4)) : nil)
        if let callback = update.callbackQueryId {
            planned.append(.answer(callbackId: callback, text: "OK"))
        }
        if command == nil && context.pendingReceipt {
            planned.append(.send(chatId: update.chatId, text: TelegramCopy.text("sync_amount_type_prompt", language)))
        }
        if let command {
            var nested = update
            nested.text = command
            nested.isCallbackQuery = false
            nested.callbackQueryId = nil
            var follow = context
            if justPaired { follow.boundChatId = Int64(update.chatId) }
            let rest = TelegramRouter.steps(for: nested, context: follow).filter { step in
                if case .pair = step { return false }
                return true
            }
            planned.append(contentsOf: rest)
            let starts = command == "/start" || command.lowercased().hasPrefix("/start ") || command.lowercased().hasPrefix("/start@")
            if justPaired && !starts { planned.append(.replay(chatId: update.chatId)) }
        }
        return planned
    }

    private static func document(_ update: TelegramUpdate, context: TelegramRouterContext) -> [TelegramStep] {
        let language = context.language
        if let fileId = update.documentFileId {
            let html = TelegramFiles.isHTML(update.documentFileName, mime: update.documentMimeType)
            let json = TelegramFiles.isJSON(update.documentFileName, mime: update.documentMimeType)
            let export = TelegramFiles.isChatExport(name: update.documentFileName)
            if (html || json) && (export || context.importActive) {
                if let size = update.documentFileSize, size > TelegramBotAPI.importMaxBytes {
                    return [.send(chatId: update.chatId, text: TelegramCopy.text("sync_import_file_too_large", language, "10"))]
                }
                var steps: [TelegramStep] = []
                if !context.importActive { steps.append(.setImport(chatId: update.chatId, active: true)) }
                steps.append(.fetch(TelegramFetch(
                    chatId: update.chatId,
                    fileId: fileId,
                    fileName: update.documentFileName,
                    mime: update.documentMimeType,
                    size: update.documentFileSize,
                    date: update.messageDateSeconds,
                    bulk: true
                )))
                return steps
            }
            if TelegramFiles.isExportText(name: update.documentFileName, mime: update.documentMimeType) {
                return [.fetch(TelegramFetch(
                    chatId: update.chatId,
                    fileId: fileId,
                    fileName: update.documentFileName,
                    mime: update.documentMimeType,
                    size: update.documentFileSize,
                    date: update.messageDateSeconds,
                    bulk: context.importActive
                ))]
            }
        }
        let fileId = update.documentFileId ?? update.photoFileId
        guard let fileId else {
            return [.send(chatId: update.chatId, text: TelegramCopy.text("sync_doc_not_supported", language))]
        }
        let name = (update.documentFileName ?? "").lowercased()
        if name.hasSuffix(".pdf") || name.hasSuffix(".docx") || (update.documentMimeType ?? "").contains("pdf") {
            return [.send(chatId: update.chatId, text: TelegramCopy.text("sync_doc_not_supported", language))]
        }
        return [.fetch(TelegramFetch(
            chatId: update.chatId,
            fileId: fileId,
            fileName: update.documentFileName,
            mime: update.documentMimeType,
            size: update.documentFileSize,
            date: update.messageDateSeconds,
            bulk: false
        ))]
    }

    private static func shouldAck(_ update: TelegramUpdate) -> Bool {
        if update.isCallbackQuery { return false }
        if update.photoFileId != nil || update.documentFileId != nil { return true }
        let text = update.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty || text.hasPrefix("/") { return false }
        if TelegramMenu.isMenuButton(text) { return false }
        if TelegramMenu.isRestoreRequest(text) { return false }
        return true
    }

    private static func cancelText(_ context: TelegramRouterContext, language: TelegramLanguage) -> String {
        if context.importActive && context.restoreActive {
            return TelegramCopy.text("sync_import_and_restore_cancelled", language)
        }
        if context.importActive { return TelegramCopy.text("sync_import_cancelled", language) }
        if context.restoreActive { return TelegramCopy.text("sync_restore_manual_cancelled", language) }
        if context.pendingReceipt || context.teachPhase != nil {
            return TelegramCopy.text("sync_receipt_cancelled", language)
        }
        return TelegramCopy.text("sync_restore_not_active", language)
    }
}

public enum TelegramRestorable {
    private static let prefixes = ["✅", "🆗", "📊", "⏳", "📭", "❓", "📥", "🔄", "👋", "📋", "📦", "💰", "ℹ️", "❌"]

    public static func isData(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return false }
        if TelegramMenu.isRestoreRequest(trimmed) { return false }
        if trimmed.hasPrefix("/") { return false }
        if prefixes.contains(where: { trimmed.hasPrefix($0) }) { return false }
        if MessageClassifier.isLoadLike(trimmed) { return true }
        switch ReceiptKindClassifier.classify(trimmed) {
        case .load, .paycheck, .diesel, .def: return true
        case .unknown: return false
        }
    }
}

public struct TelegramTeachMove: Equatable, Sendable {
    public var phase: String
    public var body: String
    public var tripLabel: String
    public var rateLabel: String
    public var messageKey: String
    public var saved: Bool
}

public enum TelegramTeach {
    public static let document = "document"
    public static let trip = "trip"
    public static let rate = "rate"

    public static func advance(phase: String, body: String, tripLabel: String, reply: String) -> TelegramTeachMove {
        let text = reply.trimmingCharacters(in: .whitespacesAndNewlines)
        switch phase {
        case document:
            return TelegramTeachMove(phase: trip, body: String(text.prefix(12_000)), tripLabel: "", rateLabel: "", messageKey: "sync_teach_ask_trip", saved: false)
        case trip:
            guard let label = TelegramBrokerLabel.labelBefore(text: body, token: text) else {
                return TelegramTeachMove(phase: trip, body: body, tripLabel: tripLabel, rateLabel: "", messageKey: "sync_teach_miss", saved: false)
            }
            return TelegramTeachMove(phase: rate, body: body, tripLabel: label, rateLabel: "", messageKey: "sync_teach_ask_rate", saved: false)
        default:
            guard let label = TelegramBrokerLabel.labelBefore(text: body, token: text) else {
                return TelegramTeachMove(phase: rate, body: body, tripLabel: tripLabel, rateLabel: "", messageKey: "sync_teach_miss", saved: false)
            }
            return TelegramTeachMove(phase: rate, body: body, tripLabel: tripLabel, rateLabel: label, messageKey: "sync_teach_saved", saved: true)
        }
    }
}
