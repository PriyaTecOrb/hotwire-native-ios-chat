import WebKit

final class WebMessageHandler: NSObject, WKScriptMessageHandler {

    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {

        guard message.name == "iosHandler" else { return }
        print("📩 Message from JS:", message.body)
    }
}
