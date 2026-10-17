import ClearCommandTabCore

struct SettingsFocusTests {
    func testOneFallbackAndBoundedLifetime() {
        var intent = SettingsFocusIntent()
        let opening = intent.begin(now: 10)
        expectTrue(intent.isCurrent(opening, now: 10.1))
        expectTrue(intent.takeFallback(opening, now: 10.1))
        expectFalse(intent.takeFallback(opening, now: 10.2))
        expectFalse(intent.isCurrent(opening, now: 10.8))
        expectFalse(intent.takeFallback(opening, now: 11))
    }

    func testClosingExternalActionAndNewOpeningInvalidateCallbacks() {
        var intent = SettingsFocusIntent()
        let closed = intent.begin(now: 1)
        intent.cancel()
        expectFalse(intent.isCurrent(closed, now: 1.1))
        expectFalse(intent.takeFallback(closed, now: 1.1))
        let oldOpening = intent.begin(now: 2)
        let newOpening = intent.begin(now: 2.1)
        expectFalse(intent.isCurrent(oldOpening, now: 2.2))
        expectFalse(intent.takeFallback(oldOpening, now: 2.2))
        expectTrue(intent.takeFallback(newOpening, now: 2.2))
        intent.cancel() // Keyboard focus confirmed, or the user chose another app.
        expectFalse(intent.isCurrent(newOpening, now: 2.3))
    }
}
