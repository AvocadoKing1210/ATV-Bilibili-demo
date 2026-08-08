//
//  CookieManager.swift
//  BilibiliLive
//
//  Created by Etan Chen on 2021/3/28.
//

import Foundation

struct StoredCookie: Codable, Equatable {
    let name: String
    let value: String
    let domain: String
    let path: String
    let expiresDate: Date?
    let isSecure: Bool
    let isHTTPOnly: Bool

    init(cookie: HTTPCookie) {
        name = cookie.name
        value = cookie.value
        domain = cookie.domain
        path = cookie.path
        expiresDate = cookie.expiresDate
        isSecure = cookie.isSecure
        isHTTPOnly = cookie.isHTTPOnly
    }

    func makeHTTPCookie() -> HTTPCookie? {
        var properties: [HTTPCookiePropertyKey: Any] = [
            .domain: domain,
            .name: name,
            .path: path,
            .value: value,
        ]
        if let expiresDate {
            properties[.expires] = expiresDate
        }
        if isSecure {
            properties[.secure] = "TRUE"
        }
        properties[HTTPCookiePropertyKey("HttpOnly")] = isHTTPOnly ? "TRUE" : "FALSE"
        return HTTPCookie(properties: properties)
    }
}

class CookieHandler {
    static let shared: CookieHandler = .init()

    let cookieStorage = HTTPCookieStorage.shared

    /// These identify the *device*, not the session. Web 风控 answers -352 to a
    /// session without them, and both cookie-swap paths below used to take them
    /// out with the rest of the jar — so signing in, or switching account, left
    /// every web endpoint failing until the next launch happened to rerun
    /// `WebRequest.ensureFingerprint`. `b_nut` is set alongside the buvids by
    /// bilibili's own `Set-Cookie` rather than by us, and is checked with them.
    private static let deviceCookieNames: Set<String> = ["buvid3", "buvid4", "b_nut"]

    func getCookie(forURL url: String) -> [HTTPCookie] {
        let computedUrl = URL(string: url)
        let cookies = cookieStorage.cookies(for: computedUrl!) ?? []
        return cookies
    }

    func currentStoredCookies() -> [StoredCookie] {
        cookieStorage.cookies?.map(StoredCookie.init) ?? []
    }

    func replaceCookies(with cookies: [StoredCookie]) {
        let device = deviceCookies()
        removeCookie()
        cookies.compactMap { $0.makeHTTPCookie() }.forEach { cookieStorage.setCookie($0) }
        restoreDeviceCookies(device)
    }

    private func deviceCookies() -> [HTTPCookie] {
        (cookieStorage.cookies ?? []).filter { Self.deviceCookieNames.contains($0.name) }
    }

    /// Puts back only the fingerprint the incoming set did not carry itself, so
    /// a snapshot that already holds a buvid stays the authority on it.
    private func restoreDeviceCookies(_ cookies: [HTTPCookie]) {
        let present = Set((cookieStorage.cookies ?? []).map(\.name))
        for cookie in cookies where !present.contains(cookie.name) {
            cookieStorage.setCookie(cookie)
        }
    }

    func backupCookies() {
        AccountManager.shared.syncActiveAccountCookies()
    }

    func removeCookie() {
        for cookie in cookieStorage.cookies ?? [] {
            cookieStorage.deleteCookie(cookie)
        }
    }

    func saveCookie(list: [HTTPCookie], syncWithAccount: Bool = true) {
        let device = deviceCookies()
        removeCookie()
        list.forEach({ cookieStorage.setCookie($0) })
        restoreDeviceCookies(device)
        if syncWithAccount {
            backupCookies()
        }
    }

    func csrf() -> String? {
        let cookies = getCookie(forURL: "https://bilibili.com")
        return cookies.first(where: { $0.name == "bili_jct" })?.value
    }

    func buvid3() -> String {
        let cookies = getCookie(forURL: "https://bilibili.com")
        return cookies.first(where: { $0.name == "buvid3" })?.value ?? ""
    }
}
