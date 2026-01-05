//
//  ViewController.swift
//  ChatApp
//
//  Created by apple on 18/12/25.
//

import UIKit
import WebKit
import UserNotifications

class ViewController: UIViewController {
    @IBOutlet weak var webView: WKWebView!
    override func viewDidLoad() {
        super.viewDidLoad()
        setupWebView()
        setupPushNotifications()
        // Do any additional setup after loading the view.
    }
    
    func setupWebView() {
        let contentController = WKUserContentController()
        
        // Add message handler for push notifications
        contentController.add(self, name: "pushNotificationBridge")
        
        let config = WKWebViewConfiguration()
        config.userContentController = contentController
        
        webView = WKWebView(frame: view.bounds, configuration: config)
        webView.navigationDelegate = self
        view.addSubview(webView)
        
        // Load your Rails app
        if let url = URL(string: "http://localhost:3000") { // Replace with your app URL
            webView.load(URLRequest(url: url))
        }
    }
    
    func setupPushNotifications() {
        UNUserNotificationCenter.current().delegate = self
        
        // Request notification permissions
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
            if granted {
                DispatchQueue.main.async {
                    UIApplication.shared.registerForRemoteNotifications()
                }
            }
        }
    }

}

extension ViewController: WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "pushNotificationBridge",
              let body = message.body as? [String: Any],
              let action = body["action"] as? String else { return }
        
        switch action {
        case "requestPermissions":
            requestNotificationPermissions()
            
        case "showNotification":
            showLocalNotification(data: body)
            
        default:
            break
        }
    }
    
    func requestNotificationPermissions() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
            DispatchQueue.main.async {
                if granted {
                    UIApplication.shared.registerForRemoteNotifications()
                }
                
                // Notify web app about permission status
                self.webView.evaluateJavaScript("""
                    if (window.PushNotificationBridge) {
                        window.PushNotificationBridge.onPermissionResult(\(granted));
                    }
                """)
            }
        }
    }
    
    func showLocalNotification(data: [String: Any]) {
        let content = UNMutableNotificationContent()
        content.title = data["title"] as? String ?? "New Message"
        content.body = data["body"] as? String ?? ""
        content.sound = .default
        
        if let badge = data["badge"] as? Int {
            content.badge = NSNumber(value: badge)
        }
        
        // Add conversation data for handling taps
        content.userInfo = [
            "conversationId": data["conversationId"] ?? "",
            "senderId": data["senderId"] ?? "",
            "timestamp": data["timestamp"] ?? ""
        ]
        
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil // Show immediately
        )
        
        UNUserNotificationCenter.current().add(request)
    }
}

// MARK: - Push Notification Handling
extension ViewController {
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let tokenString = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
        
        // Send token to web app
        webView.evaluateJavaScript("""
            if (window.onDeviceTokenReceived) {
                window.onDeviceTokenReceived('\(tokenString)', 'ios');
            }
        """)
    }
    
    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("Failed to register for remote notifications: \(error)")
    }
}

// MARK: - UNUserNotificationCenterDelegate
extension ViewController: UNUserNotificationCenterDelegate {
    // Handle notification when app is in foreground
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        // Show notification even when app is active
        completionHandler([.alert, .badge, .sound])
    }
    
    // Handle notification tap
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        let userInfo = response.notification.request.content.userInfo
        
        if let conversationId = userInfo["conversationId"] as? String {
            // Navigate to conversation in web app
            webView.evaluateJavaScript("""
                window.location.href = '/conversations/\(conversationId)';
            """)
        }
        
        completionHandler()
    }
}

// MARK: - WKNavigationDelegate
extension ViewController: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // Inject app state tracking
        webView.evaluateJavaScript("""
            // Track app state changes
            document.addEventListener('visibilitychange', function() {
                if (window.PushNotificationBridge) {
                    window.PushNotificationBridge.updateAppState({
                        isBackground: document.hidden
                    });
                }
            });
        """)
    }
}

// MARK: - App Lifecycle
extension ViewController {
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        // Notify web app that app is active
        webView.evaluateJavaScript("""
            window.appState = { isBackground: false };
            if (window.chatNotifications) {
                window.chatNotifications.updateAppState();
            }
        """)
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        
        // Notify web app that app is in background
        webView.evaluateJavaScript("""
            window.appState = { isBackground: true };
            if (window.chatNotifications) {
                window.chatNotifications.updateAppState();
            }
        """)
    }
}
