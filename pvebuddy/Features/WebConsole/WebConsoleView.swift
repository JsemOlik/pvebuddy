//
//  WebConsoleView.swift
//  pvebuddy
//
//  Created by Oliver Steiner on 01.12.2025.
//

import SwiftUI
import WebKit

struct WebConsoleView: View {
  let url: URL
  let title: String
  // Optional cookies to pre-insert (e.g., PVEAuthCookie)
  let cookies: [HTTPCookie]?

  @State private var canGoBack: Bool = false
  @State private var canGoForward: Bool = false
  @State private var progress: Double = 0
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    VStack(spacing: 0) {
      HStack(spacing: 12) {
        Button { dismiss() } label: {
          Image(systemName: "xmark").font(.system(size: 16, weight: .semibold))
        }.buttonStyle(.plain)

        Text(title).font(.headline).lineLimit(1).truncationMode(.tail)

        Spacer()

        Button {
          NotificationCenter.default.post(name: .webConsoleGoBack, object: nil)
        } label: { Image(systemName: "chevron.left") }
          .disabled(!canGoBack)

        Button {
          NotificationCenter.default.post(name: .webConsoleGoForward, object: nil)
        } label: { Image(systemName: "chevron.right") }
          .disabled(!canGoForward)

        Button {
          NotificationCenter.default.post(name: .webConsoleReload, object: nil)
        } label: { Image(systemName: "arrow.clockwise") }
      }
      .padding(.horizontal, 12)
      .padding(.vertical, 8)

      ProgressView(value: progress)
        .tint(.blue)
        .progressViewStyle(.linear)
        .opacity(progress > 0 && progress < 1 ? 1 : 0)
        .animation(.easeInOut(duration: 0.2), value: progress)

      WebViewRepresentable(url: url,
                           canGoBack: $canGoBack,
                           canGoForward: $canGoForward,
                           progress: $progress,
                           cookies: cookies)
        .ignoresSafeArea(edges: .bottom)
    }
  }
}

private struct WebViewRepresentable: UIViewRepresentable {
  let url: URL
  @Binding var canGoBack: Bool
  @Binding var canGoForward: Bool
  @Binding var progress: Double
  let cookies: [HTTPCookie]?

  func makeCoordinator() -> Coordinator {
    Coordinator(canGoBack: $canGoBack, canGoForward: $canGoForward, progress: $progress)
  }

  func makeUIView(context: Context) -> WKWebView {
    let config = WKWebViewConfiguration()
    config.defaultWebpagePreferences.allowsContentJavaScript = true
    config.allowsInlineMediaPlayback = true
    config.allowsAirPlayForMediaPlayback = true

    let webView = WKWebView(frame: .zero, configuration: config)
    webView.navigationDelegate = context.coordinator
    webView.uiDelegate = context.coordinator
    webView.addObserver(context.coordinator, forKeyPath: "estimatedProgress", options: .new, context: nil)

    // Insert cookies first, then load
    if let cookies, !cookies.isEmpty {
      let store = webView.configuration.websiteDataStore.httpCookieStore
      let group = DispatchGroup()
      for cookie in cookies {
        group.enter()
        store.setCookie(cookie) {
          group.leave()
        }
      }
      group.notify(queue: .main) {
        webView.load(URLRequest(url: self.url))
      }
    } else {
      webView.load(URLRequest(url: url))
    }

    // Pull to refresh
    let refresh = UIRefreshControl()
    refresh.addTarget(context.coordinator, action: #selector(Coordinator.refresh(_:)), for: .valueChanged)
    webView.scrollView.refreshControl = refresh

    // Toolbar notifications
    NotificationCenter.default.addObserver(forName: .webConsoleReload, object: nil, queue: .main) { _ in
      webView.reload()
    }
    NotificationCenter.default.addObserver(forName: .webConsoleGoBack, object: nil, queue: .main) { _ in
      if webView.canGoBack { webView.goBack() }
    }
    NotificationCenter.default.addObserver(forName: .webConsoleGoForward, object: nil, queue: .main) { _ in
      if webView.canGoForward { webView.goForward() }
    }

    return webView
  }

  func updateUIView(_ uiView: WKWebView, context: Context) {}

  static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
    webView.removeObserver(coordinator, forKeyPath: "estimatedProgress")
    NotificationCenter.default.removeObserver(coordinator)
  }

  final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
    @Binding var canGoBack: Bool
    @Binding var canGoForward: Bool
    @Binding var progress: Double

    init(canGoBack: Binding<Bool>, canGoForward: Binding<Bool>, progress: Binding<Double>) {
      _canGoBack = canGoBack
      _canGoForward = canGoForward
      _progress = progress
    }

    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
      if keyPath == "estimatedProgress", let webView = object as? WKWebView {
        progress = webView.estimatedProgress
      }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
      canGoBack = webView.canGoBack
      canGoForward = webView.canGoForward
      webView.scrollView.refreshControl?.endRefreshing()
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
      canGoBack = webView.canGoBack
      canGoForward = webView.canGoForward
    }

    @objc func refresh(_ sender: UIRefreshControl) {
      (sender.superview as? WKWebView)?.reload()
    }
  }
}

private extension Notification.Name {
  static let webConsoleReload = Notification.Name("webConsoleReload")
  static let webConsoleGoBack = Notification.Name("webConsoleGoBack")
  static let webConsoleGoForward = Notification.Name("webConsoleGoForward")
}
