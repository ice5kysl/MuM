import XCTest
@testable import MuM

/// 每日使用计数（0.8.4）。
///
/// 这组测的是**状态机与隐私边界**，不是网络：
/// - 每天最多一次（同一天启动多次不重复报）
/// - 关掉开关后一个字节都不发、也不留记录
/// - 日期用 UTC（跨时区 / 夏令时不能一天报两次）
/// - 事件路径里不许出现任何标识性字段
///
/// 所有用例都注入 no-op sender —— **真发请求会污染线上统计**。
final class UsagePingTests: XCTestCase {

    private let suiteName = "MuM.usagePing.tests"
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        UserDefaults().removePersistentDomain(forName: suiteName)
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    }

    override func tearDownWithError() throws {
        UserDefaults().removePersistentDomain(forName: suiteName)
        defaults = nil
    }

    private func makeSettings(ping: Bool) -> MuMSettings {
        var settings = MuMSettings()
        settings.sendsUsagePing = ping
        return settings
    }

    // MARK: - 纯函数

    func testShouldReportOnlyOncePerDay() {
        XCTAssertTrue(UsagePing.shouldReport(today: "2026-10-08", lastReported: nil),
                      "从没报过 → 要报")
        XCTAssertTrue(UsagePing.shouldReport(today: "2026-10-08", lastReported: "2026-10-07"),
                      "昨天报过 → 今天要报")
        XCTAssertFalse(UsagePing.shouldReport(today: "2026-10-08", lastReported: "2026-10-08"),
                       "今天已报 → 不再报")
    }

    /// UTC 而不是本地时区：否则跨时区或夏令时会让「今天」来回跳，同一天报两次
    func testDayStringIsUTC() {
        XCTAssertEqual(UsagePing.dayString(for: Date(timeIntervalSince1970: 0)), "1970-01-01")
        XCTAssertEqual(UsagePing.dayString(for: Date(timeIntervalSince1970: 86_399)), "1970-01-01",
                       "UTC 当天最后一秒")
        XCTAssertEqual(UsagePing.dayString(for: Date(timeIntervalSince1970: 86_400)), "1970-01-02",
                       "UTC 次日第一秒必须换天")
    }

    func testEventPathCarriesVersion() {
        XCTAssertEqual(UsagePing.eventPath(version: "0.8.4"), "/app-launch/0.8.4",
                       "版本进路径，GoatCounter 里按 /app-launch 前缀筛选就是总 DAU")
    }

    /// 事件路径里**不许出现**任何标识性字段 —— 只有固定前缀 + 版本号
    func testEventPathHasNoIdentifier() {
        let path = UsagePing.eventPath(version: "0.8.4")
        XCTAssertFalse(path.contains(NSUserName()), "路径不能带用户名")
        XCTAssertFalse(path.lowercased().contains("uuid"))
        XCTAssertFalse(path.lowercased().contains("device"))
        XCTAssertFalse(path.lowercased().contains("id="))
    }

    // MARK: - 状态机

    func testDisabledSendsNothingAndRecordsNothing() {
        var sent: [String] = []
        UsagePing.reportIfNeeded(settings: makeSettings(ping: false), defaults: defaults,
                                 now: Date(timeIntervalSince1970: 0)) { sent.append($0) }
        XCTAssertTrue(sent.isEmpty, "关掉开关就一个字节都不发")
        XCTAssertNil(defaults.string(forKey: UsagePing.lastReportKey), "关掉也不该留记录")
    }

    func testEnabledReportsOnceAndRecordsDay() {
        var sent: [String] = []
        UsagePing.reportIfNeeded(settings: makeSettings(ping: true), defaults: defaults,
                                 now: Date(timeIntervalSince1970: 0)) { sent.append($0) }
        XCTAssertEqual(sent, [UpdateChecker.currentVersion], "报到的是当前版本号")
        XCTAssertEqual(defaults.string(forKey: UsagePing.lastReportKey), "1970-01-01")
    }

    func testSecondLaunchSameDayDoesNotReportAgain() {
        var sent: [String] = []
        let sender: (String) -> Void = { sent.append($0) }
        let day = Date(timeIntervalSince1970: 0)

        UsagePing.reportIfNeeded(settings: makeSettings(ping: true), defaults: defaults, now: day, sender: sender)
        UsagePing.reportIfNeeded(settings: makeSettings(ping: true), defaults: defaults, now: day, sender: sender)

        XCTAssertEqual(sent.count, 1, "同一天启动多次只报一次")
    }

    func testNextDayReportsAgain() {
        var sent: [String] = []
        let sender: (String) -> Void = { sent.append($0) }

        UsagePing.reportIfNeeded(settings: makeSettings(ping: true), defaults: defaults,
                                 now: Date(timeIntervalSince1970: 0), sender: sender)
        UsagePing.reportIfNeeded(settings: makeSettings(ping: true), defaults: defaults,
                                 now: Date(timeIntervalSince1970: 86_400), sender: sender)

        XCTAssertEqual(sent.count, 2, "换了一天就再报一次")
        XCTAssertEqual(defaults.string(forKey: UsagePing.lastReportKey), "1970-01-02")
    }

    /// 「先记账再发」：即使发送失败（这里用什么都不做的 sender 模拟），
    /// 当天也不再重试 —— 断网时不该每次启动都撞一次超时
    func testDayIsRecordedEvenIfSendingFails() {
        UsagePing.reportIfNeeded(settings: makeSettings(ping: true), defaults: defaults,
                                 now: Date(timeIntervalSince1970: 0)) { _ in /* 模拟失败 */ }
        XCTAssertEqual(defaults.string(forKey: UsagePing.lastReportKey), "1970-01-01")
    }

    /// 默认值必须是「开」—— 0.8.3 之前项目对"有没有人在用"完全是盲的，
    /// 这正是这一版要解决的问题
    func testDefaultsToEnabled() {
        XCTAssertTrue(MuMSettings().sendsUsagePing)
    }

    /// 设置往返：关掉之后重新加载仍然是关的（否则用户关了下次启动又偷偷发）
    func testSettingRoundTrips() {
        let key = "MuM.settings"
        let backup = UserDefaults.standard.dictionary(forKey: key)
        defer {
            if let backup { UserDefaults.standard.set(backup, forKey: key) }
            else { UserDefaults.standard.removeObject(forKey: key) }
        }

        var settings = MuMSettings()
        settings.sendsUsagePing = false
        SettingsStore.save(settings)

        XCTAssertFalse(SettingsStore.load().sendsUsagePing, "关掉的状态必须能存下来")
    }
}
