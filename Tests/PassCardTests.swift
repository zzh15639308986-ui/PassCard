import UIKit
import XCTest
@testable import PassCard

/// These tests pin the contract with the recognition backend. The JSON literals
/// are byte-for-byte shaped like what `pipeline._finish` returns, so a rename on
/// the Python side breaks a test here instead of shipping a blank card.
final class PassCardTests: XCTestCase {

    // MARK: - Backend payload decoding

    func testDecodesRealBackendTrainPayload() throws {
        let json = """
        {
          "type": "train",
          "type_label": "火车票",
          "fields": {
            "train_no": "G102",
            "depart_at": "2026-11-28T14:30:00",
            "from_station": "上海虹桥",
            "to_station": "北京南",
            "seat": "07车09F号",
            "seat_class": "二等座"
          },
          "errors": [],
          "warnings": ["dropped unknown field 'platform'"],
          "fallback_used": false,
          "image_sha256": "9f2c1a",
          "model_calls": 2,
          "tokens": {"completion_tokens": 240, "prompt_tokens": 1600, "total_tokens": 1840},
          "elapsed_ms": 8421,
          "cache_hit": false,
          "ok": true
        }
        """
        let result = try decode(json)

        XCTAssertEqual(result.type, .train)
        XCTAssertEqual(result.typeLabel, "火车票")
        XCTAssertTrue(result.ok)
        XCTAssertEqual(result.modelCalls, 2)
        XCTAssertEqual(result.elapsedMs, 8421)
        XCTAssertEqual(result.imageSha256, "9f2c1a")
        XCTAssertFalse(result.cacheHit)
        XCTAssertFalse(result.fallbackUsed)
        XCTAssertEqual(result.totalTokens, 1840)
        XCTAssertEqual(result.fields.text("train_no"), "G102")
        XCTAssertEqual(result.warnings, ["dropped unknown field 'platform'"])
        XCTAssertNotNil(result.fields.date("depart_at"))
    }

    func testDecodesValidationFailurePayload() throws {
        let json = """
        {
          "type": "train",
          "type_label": "火车票",
          "fields": {"train_no": "G102"},
          "errors": ["缺少必填字段: depart_at"],
          "warnings": [],
          "fallback_used": true,
          "image_sha256": "aa",
          "model_calls": 3,
          "tokens": {},
          "elapsed_ms": 1200,
          "cache_hit": false,
          "ok": false
        }
        """
        let result = try decode(json)

        XCTAssertFalse(result.ok)
        XCTAssertTrue(result.fallbackUsed)
        XCTAssertEqual(result.errors.count, 1)
        XCTAssertTrue(result.tokens.isEmpty)
        XCTAssertEqual(result.totalTokens, 0)
    }

    func testDecodesUnknownTypePayload() throws {
        let json = """
        {
          "type": "unknown",
          "type_label": "未识别",
          "fields": {},
          "errors": [],
          "warnings": ["classifier output unresolvable, used fallback prompt"],
          "fallback_used": true,
          "image_sha256": "bb",
          "model_calls": 2,
          "tokens": {"total_tokens": 900},
          "elapsed_ms": 5000,
          "cache_hit": false,
          "ok": true
        }
        """
        let result = try decode(json)

        XCTAssertEqual(result.type, .unknown)
        XCTAssertTrue(result.fields.isEmpty)
    }

    func testEveryBackendTypeIdentifierDecodes() throws {
        let identifiers = ["pickup_food", "pickup_parcel", "train", "flight", "movie",
                           "show", "ride", "voucher", "subscription", "unknown"]
        for identifier in identifiers {
            let decoded = PassType(rawValue: identifier)
            XCTAssertNotNil(decoded, "PassType is missing raw value \(identifier)")
            XCTAssertEqual(decoded?.rawValue, identifier)
            XCTAssertFalse(decoded?.label.isEmpty ?? true, "\(identifier) has no label")
            XCTAssertFalse(decoded?.symbolName.isEmpty ?? true, "\(identifier) has no symbol")
        }
        XCTAssertEqual(PassType.allCases.count, identifiers.count)
    }

    /// `unknown` results skip the backend's field normalisation, so the model
    /// can nest a value. That must not throw away the whole payload.
    func testNestedFieldValueDecodesAsNull() throws {
        let json = """
        {
          "type": "unknown",
          "type_label": "未识别",
          "fields": {"detail": {"a": 1}, "list": [1, 2], "code": "1234"},
          "errors": [], "warnings": [], "fallback_used": true,
          "image_sha256": "cc", "model_calls": 2, "tokens": {},
          "elapsed_ms": 1, "cache_hit": false, "ok": true
        }
        """
        let result = try decode(json)

        XCTAssertEqual(result.fields.count, 3)
        XCTAssertEqual(result.fields["detail"], .null)
        XCTAssertEqual(result.fields["list"], .null)
        XCTAssertEqual(result.fields.text("code"), "1234")
    }

    func testRejectsPayloadWithMissingKeys() {
        let json = #"{"type": "train", "fields": {}}"#
        XCTAssertThrowsError(try decode(json))
    }

    // MARK: - Date parsing

    func testParsesNaiveIsoformatFromPython() {
        // datetime.isoformat() omits the offset for naive values.
        let date = PassDateParser.parse("2026-11-28T14:30:00")
        XCTAssertNotNil(date)
        let calendar = Calendar.current
        XCTAssertEqual(calendar.component(.year, from: date!), 2026)
        XCTAssertEqual(calendar.component(.month, from: date!), 11)
        XCTAssertEqual(calendar.component(.day, from: date!), 28)
        XCTAssertEqual(calendar.component(.hour, from: date!), 14)
        XCTAssertEqual(calendar.component(.minute, from: date!), 30)
    }

    func testParsesOffsetAndFractionalIsoformat() {
        XCTAssertNotNil(PassDateParser.parse("2026-11-28T14:30:00+08:00"))
        XCTAssertNotNil(PassDateParser.parse("2026-11-28T14:30:00Z"))
        XCTAssertNotNil(PassDateParser.parse("2026-11-28T14:30:00.123456+08:00"))
        XCTAssertNotNil(PassDateParser.parse("2026-11-28T14:30"))
        XCTAssertNotNil(PassDateParser.parse("2026-11-28"))
    }

    func testUnparseableDateReturnsNilInsteadOfThrowing() {
        XCTAssertNil(PassDateParser.parse("待定"))
        XCTAssertNil(PassDateParser.parse(""))
        XCTAssertNil(PassDateParser.parse("   "))
        XCTAssertNil(PassDateParser.parse("2026年11月28日 14:30"))
    }

    // MARK: - Presentation

    func testTrainPresentation() throws {
        let pass = try makePass("train", """
        {"train_no":"G102","depart_at":"2099-11-28T14:30:00","from_station":"上海虹桥",
         "to_station":"北京南","carriage":"07","seat":"09F","seat_class":"二等座","gate":"12"}
        """)
        let presentation = pass.presentation

        XCTAssertEqual(presentation.title, "上海虹桥 → 北京南")
        XCTAssertEqual(presentation.primary, "G102")
        XCTAssertTrue(presentation.secondary.contains("07车"), presentation.secondary)
        XCTAssertTrue(presentation.secondary.contains("09F"), presentation.secondary)
        XCTAssertNotNil(presentation.countdownEnd)
        XCTAssertEqual(presentation.countdownLabel, "发车")
    }

    /// The model sometimes already spells the unit out; "07车车" on a card is a
    /// visible defect.
    func testUnitSuffixIsNotDoubled() throws {
        let spelled = try makePass("train", #"{"train_no":"G1","carriage":"07车"}"#).presentation
        XCTAssertTrue(spelled.secondary.contains("07车"))
        XCTAssertFalse(spelled.secondary.contains("07车车"))

        let screenSpelled = try makePass("movie", #"{"title":"X","screen":"3号厅"}"#).presentation
        XCTAssertTrue(screenSpelled.secondary.contains("3号厅"))
        XCTAssertFalse(screenSpelled.secondary.contains("3号厅厅"))
    }

    func testPastEventProducesNoCountdown() throws {
        let pass = try makePass("train", #"{"train_no":"G102","depart_at":"2001-01-01T08:00:00"}"#)
        XCTAssertNil(pass.presentation.countdownEnd)
        XCTAssertNil(pass.presentation.countdownLabel)
        let state = PassActivityAttributes.ContentState(pass)
        XCTAssertNil(state.countdownEnd)
        XCTAssertNil(state.countdownStart)
    }

    func testFutureEventProducesCountdown() throws {
        let pass = try makePass("flight", #"{"flight_no":"MU5137","depart_at":"2099-06-01T09:00:00"}"#)
        XCTAssertNotNil(pass.presentation.countdownEnd)
        let state = PassActivityAttributes.ContentState(pass)
        XCTAssertNotNil(state.countdownStart)
        XCTAssertNotNil(state.countdownEnd)
        XCTAssertLessThanOrEqual(state.countdownStart!, state.countdownEnd!)
    }

    func testPickupFoodPresentation() throws {
        let pass = try makePass("pickup_food", """
        {"code":"A2048","store":"喜茶","order_no":"8821","pickup_by":"2099-01-01T12:00:00"}
        """)
        let presentation = pass.presentation

        XCTAssertEqual(presentation.title, "喜茶")
        XCTAssertEqual(presentation.primary, "A2048")
        XCTAssertTrue(presentation.secondary.contains("8821"))
        XCTAssertEqual(presentation.countdownLabel, "取餐")
    }

    func testPickupParcelFallsBackToCarrierAsTitle() throws {
        let pass = try makePass("pickup_parcel", #"{"code":"7-2-1006","carrier":"菜鸟驿站"}"#)
        XCTAssertEqual(pass.presentation.title, "菜鸟驿站")
        XCTAssertEqual(pass.presentation.primary, "7-2-1006")
    }

    func testFlightPresentation() throws {
        let pass = try makePass("flight", """
        {"flight_no":"MU5137","depart_at":"2099-06-01T09:00:00","from_airport":"上海浦东",
         "to_airport":"北京首都","terminal_from":"2","gate":"C40","seat":"32A"}
        """)
        let presentation = pass.presentation

        XCTAssertEqual(presentation.title, "上海浦东 → 北京首都")
        XCTAssertEqual(presentation.primary, "MU5137")
        XCTAssertTrue(presentation.secondary.contains("T2"))
        XCTAssertTrue(presentation.secondary.contains("C40登机口"))
        XCTAssertEqual(presentation.countdownLabel, "登机")
    }

    func testMoviePresentation() throws {
        let pass = try makePass("movie", """
        {"title":"流浪地球3","start_at":"2099-02-10T19:30:00","cinema":"万达影城",
         "screen":"5","seat":"8排12座","language":"国语"}
        """)
        let presentation = pass.presentation

        XCTAssertEqual(presentation.title, "流浪地球3")
        XCTAssertEqual(presentation.primary, "万达影城")
        XCTAssertTrue(presentation.secondary.contains("5厅"))
        XCTAssertTrue(presentation.secondary.contains("8排12座"))
    }

    func testShowPresentationPrefersVenue() throws {
        let pass = try makePass("show", #"{"title":"话剧","venue":"大剧院","seat":"A区3排"}"#)
        XCTAssertEqual(pass.presentation.primary, "大剧院")
        XCTAssertTrue(pass.presentation.secondary.contains("A区3排"))
    }

    func testRidePresentation() throws {
        let pass = try makePass("ride", """
        {"plate_no":"沪A12345","platform":"滴滴","vehicle_color":"白色","vehicle":"轩逸",
         "destination":"人民广场"}
        """)
        let presentation = pass.presentation

        XCTAssertEqual(presentation.title, "人民广场")
        XCTAssertEqual(presentation.primary, "沪A12345")
        XCTAssertTrue(presentation.secondary.contains("滴滴"))
    }

    func testVoucherPresentation() throws {
        let pass = try makePass("voucher", #"{"code":"SAVE30","merchant":"星巴克","value":"30元"}"#)
        XCTAssertEqual(pass.presentation.title, "星巴克")
        XCTAssertEqual(pass.presentation.primary, "SAVE30")
        XCTAssertTrue(pass.presentation.secondary.contains("30元"))
    }

    func testSubscriptionPresentation() throws {
        let pass = try makePass("subscription", """
        {"service":"iCloud+","price":21,"currency":"¥","cycle":"monthly",
         "next_charge_at":"2099-01-05T00:00:00","status":"active"}
        """)
        let presentation = pass.presentation

        XCTAssertEqual(presentation.title, "iCloud+")
        XCTAssertTrue(presentation.primary.contains("21"), presentation.primary)
        XCTAssertTrue(presentation.secondary.contains("每月"), presentation.secondary)
        XCTAssertTrue(presentation.secondary.contains("生效中"), presentation.secondary)
        XCTAssertEqual(presentation.countdownLabel, "扣款")
    }

    func testUnknownPresentationHasADisplayablePrimary() throws {
        let withNote = try makePass("unknown", #"{"notes":"会员卡 8899"}"#)
        XCTAssertEqual(withNote.presentation.primary, "会员卡 8899")
        XCTAssertEqual(withNote.presentation.title, "未识别的凭证")

        let empty = try makePass("unknown", "{}")
        XCTAssertEqual(empty.presentation.primary, "—")
        XCTAssertNil(empty.presentation.countdownEnd)
    }

    func testSecondaryIsCappedAtThreeParts() throws {
        let pass = try makePass("train", """
        {"train_no":"G102","depart_at":"2099-01-01T08:00:00","carriage":"07","seat":"09F",
         "seat_class":"二等座","gate":"12"}
        """)
        let parts = pass.presentation.secondary.components(separatedBy: " · ")
        XCTAssertLessThanOrEqual(parts.count, 3, pass.presentation.secondary)
    }

    func testContentStateCarriesEverythingTheWidgetNeeds() throws {
        let pass = try makePass("train", #"{"train_no":"G102","depart_at":"2099-01-01T08:00:00"}"#)
        let state = PassActivityAttributes.ContentState(pass)

        XCTAssertEqual(state.title, pass.presentation.title)
        XCTAssertEqual(state.primary, "G102")
        XCTAssertEqual(state.symbolName, PassType.train.symbolName)
        XCTAssertFalse(state.title.isEmpty)
        XCTAssertFalse(state.primary.isEmpty)
    }

    // MARK: - Persistence

    func testPassCodableRoundTrip() throws {
        let original = try makePass("flight", #"{"flight_no":"MU5137","depart_at":"2099-06-01T09:00:00"}"#)

        let data = try PassStore.makeEncoder().encode(original)
        let restored = try PassStore.makeDecoder().decode(Pass.self, from: data)

        XCTAssertEqual(restored, original)
        XCTAssertEqual(restored.fields.text("flight_no"), "MU5137")
    }

    /// The store's encoder writes ISO-8601 dates. If its decoder ever drifts back
    /// to the default strategy the file becomes unreadable on the next launch and
    /// load() discards it as corrupt, so pin both ends together here.
    func testStoredFileDecodesWithTheStoresOwnDecoder() throws {
        let passes = [
            try makePass("train", #"{"train_no":"G1"}"#),
            try makePass("pickup_food", #"{"code":"A100"}"#),
        ]
        let data = try PassStore.makeEncoder().encode(passes)
        XCTAssertTrue(String(decoding: data, as: UTF8.self).contains("createdAt"))

        let restored = try PassStore.makeDecoder().decode([Pass].self, from: data)
        XCTAssertEqual(restored, passes)
        XCTAssertEqual(restored.map(\.type), [.train, .pickupFood])
    }

    func testCompletedAtSurvivesARoundTrip() throws {
        var pass = try makePass("voucher", #"{"code":"V1"}"#)
        pass.markCompleted(at: Self.storedDate)
        let data = try PassStore.makeEncoder().encode(pass)
        let restored = try PassStore.makeDecoder().decode(Pass.self, from: data)
        XCTAssertEqual(restored.completedAt, Self.storedDate)
        XCTAssertTrue(restored.isCompleted)
        XCTAssertFalse(restored.isPinned)
    }

    func testPassDecodesFromStoredFieldsWithNumbers() throws {
        let pass = try makePass("subscription", #"{"service":"X","price":21.5}"#)
        XCTAssertEqual(pass.fields.number("price"), 21.5)
        XCTAssertEqual(pass.fields.text("price"), "21.50")
    }

    func testMarkCompletedClearsPinAndReopenRestores() {
        var pass = Pass(type: .voucher, fields: [:], isPinned: true)
        XCTAssertFalse(pass.isCompleted)

        pass.markCompleted()
        XCTAssertTrue(pass.isCompleted)
        XCTAssertFalse(pass.isPinned, "a finished pass must come off the Lock Screen")

        pass.reopen()
        XCTAssertFalse(pass.isCompleted)
        XCTAssertNil(pass.completedAt)
    }

    func testCompletionVerbIsPerType() {
        XCTAssertEqual(PassType.pickupFood.completionVerb, "已取餐")
        XCTAssertEqual(PassType.flight.completionVerb, "已落地")
        XCTAssertEqual(PassType.unknown.completionVerb, "已完成")
        XCTAssertNotEqual(PassType.train.completionVerb, PassType.movie.completionVerb)
    }

    // MARK: - Image preparation

    func testPreparerDownscalesOversizedScreenshot() throws {
        let oversized = renderImage(width: 3000, height: 2000)
        let prepared = ImagePreparer.prepare(oversized)

        XCTAssertTrue(prepared.wasDownscaled)
        XCTAssertEqual(prepared.mime, "image/jpeg")
        XCTAssertLessThan(prepared.sentBytes, prepared.originalBytes)

        let decoded = try XCTUnwrap(UIImage(data: prepared.data))
        let longest = max(decoded.size.width, decoded.size.height)
        XCTAssertLessThanOrEqual(longest, ImagePreparer.maxDimension + 1)
    }

    func testPreparerKeepsSmallImageAtOriginalSize() throws {
        let small = renderImage(width: 400, height: 800)
        let prepared = ImagePreparer.prepare(small)

        XCTAssertFalse(prepared.wasDownscaled)
        let decoded = try XCTUnwrap(UIImage(data: prepared.data))
        XCTAssertEqual(Int(decoded.size.width), 400)
        XCTAssertEqual(Int(decoded.size.height), 800)
    }

    func testPreparerToleratesNonImageData() {
        let prepared = ImagePreparer.prepare(Data("not an image".utf8))
        XCTAssertFalse(prepared.wasDownscaled)
        XCTAssertFalse(prepared.data.isEmpty)
    }

    // MARK: - Helpers

    private func decode(_ json: String) throws -> RecognitionResult {
        try JSONDecoder().decode(RecognitionResult.self, from: Data(json.utf8))
    }

    /// Whole-second on purpose: the `.iso8601` strategy truncates sub-second
    /// precision, so a `Date()` default would make every round-trip comparison
    /// fail for a reason that has nothing to do with the code under test.
    private static let storedDate = Date(timeIntervalSince1970: 1_800_000_000)

    private func makePass(_ type: String, _ fieldsJSON: String) throws -> Pass {
        let json = """
        {
          "type": "\(type)",
          "type_label": "x",
          "fields": \(fieldsJSON),
          "errors": [],
          "warnings": [],
          "fallback_used": false,
          "image_sha256": "test",
          "model_calls": 1,
          "tokens": {},
          "elapsed_ms": 1,
          "cache_hit": false,
          "ok": true
        }
        """
        let result = try decode(json)
        return Pass(type: result.type,
                    fields: result.fields,
                    createdAt: Self.storedDate,
                    imageSHA256: result.imageSha256)
    }

    /// High-entropy blocks, not flat colour: a flat PNG can compress below the
    /// re-encoded JPEG and make the byte assertion meaningless. Same format and
    /// quality in and out means fewer pixels has to mean fewer bytes.
    private func renderImage(width: CGFloat, height: CGFloat) -> Data {
        let size = CGSize(width: width, height: height)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let block: CGFloat = 40
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            var rowIndex = 0
            var y: CGFloat = 0
            while y < height {
                var columnIndex = 0
                var x: CGFloat = 0
                while x < width {
                    let hue = CGFloat((rowIndex * 7 + columnIndex * 13) % 100) / 100
                    UIColor(hue: hue, saturation: 0.8, brightness: 0.9, alpha: 1).setFill()
                    context.fill(CGRect(x: x, y: y, width: block, height: block))
                    x += block
                    columnIndex += 1
                }
                y += block
                rowIndex += 1
            }
        }
        return image.jpegData(compressionQuality: 0.9) ?? Data()
    }
}
