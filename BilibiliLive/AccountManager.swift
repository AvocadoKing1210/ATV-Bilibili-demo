import Foundation
import SwiftyJSON

final class AccountManager {
    struct Profile: Codable, Equatable {
        let mid: Int
        var username: String
        var avatar: String
    }

    struct Account: Codable, Equatable {
        var token: LoginToken
        var profile: Profile
        var cookies: [StoredCookie]
        var lastActiveAt: Date
    }

    static let shared = AccountManager()
    static let didUpdateNotification = Notification.Name("AccountManagerDidUpdate")

    private let accountsKey = "app.multiple.accounts"
    private let activeKey = "app.multiple.accounts.active"
    private let storage = UserDefaults.standard

    private var storedAccounts: [Account] = []
    private var activeMID: Int?

    private init() {
        loadFromStorage()
    }

    // MARK: - Public

    var accounts: [Account] {
        storedAccounts.sorted(by: { $0.lastActiveAt > $1.lastActiveAt })
    }

    var activeAccount: Account? {
        guard let activeMID else { return nil }
        return storedAccounts.first(where: { $0.profile.mid == activeMID })
    }

    var isLoggedIn: Bool { activeAccount != nil }

    func bootstrap() {
        if activeAccount == nil, let first = storedAccounts.sorted(by: { $0.lastActiveAt > $1.lastActiveAt }).first {
            activeMID = first.profile.mid
            persistActiveMID()
        }
        applyActiveAccountCookies()
    }

    func registerAccount(token: LoginToken, cookies: [HTTPCookie], completion: @escaping (Account) -> Void) {
        let storedCookies = cookies.map(StoredCookie.init)
        let mid = token.mid

        // The QR poll has already swapped the cookie jar over to this account,
        // so it is the live session whether or not we know its name yet. It has
        // to become active *before* the profile round trip: while the active
        // account still points at whoever we switched away from, any
        // `backupCookies()` elsewhere in the app — `ensureFingerprint` makes one
        // just below — writes these cookies onto *that* account's record.
        // Re-signing in to a known account keeps the name it already had, so
        // the row does not flip to a placeholder and back.
        let known = storedAccounts.first(where: { $0.profile.mid == mid })?.profile
        let account = Account(token: token,
                              profile: known ?? Profile(mid: mid, username: "UID \(mid)", avatar: ""),
                              cookies: storedCookies,
                              lastActiveAt: Date())
        upsert(account: account)
        setActiveAccount(mid: mid, applyingCookies: false, notify: true)

        fetchProfile(for: mid, using: token) { [weak self] profile in
            guard let self else { return completion(account) }
            if let profile {
                self.applyProfile(profile, to: mid)
            }
            completion(self.storedAccounts.first(where: { $0.profile.mid == mid }) ?? account)
        }
    }

    func setActiveAccount(_ account: Account) {
        setActiveAccount(mid: account.profile.mid)
    }

    func setActiveAccount(mid: Int, applyingCookies: Bool = true, notify: Bool = true) {
        guard storedAccounts.contains(where: { $0.profile.mid == mid }) else { return }
        activeMID = mid
        persistActiveMID()
        updateAccount(mid: mid) { account in
            account.lastActiveAt = Date()
        }
        if applyingCookies {
            applyActiveAccountCookies()
        }
        persistAll()
        if notify {
            notifyChange()
        }
    }

    func updateActiveAccount(token: LoginToken, cookies: [HTTPCookie]? = nil) {
        guard let mid = activeAccount?.profile.mid else { return }
        updateAccount(mid: mid) { account in
            account.token = token
            account.lastActiveAt = Date()
            if let cookies {
                account.cookies = cookies.map(StoredCookie.init)
            }
        }
        persistAll()
        notifyChange()
    }

    /// Second chance for a name that did not arrive at sign-in. Only the active
    /// account can be refreshed: the profile endpoint answers for whoever the
    /// cookie jar says is signed in, and the jar only ever holds one account.
    func refreshActiveAccountProfile() {
        guard let account = activeAccount else { return }
        let mid = account.profile.mid
        fetchProfile(for: mid, using: account.token) { [weak self] profile in
            guard let self, let profile else { return }
            self.applyProfile(profile, to: mid)
        }
    }

    func syncActiveAccountCookies() {
        guard let mid = activeAccount?.profile.mid else { return }
        let cookies = CookieHandler.shared.currentStoredCookies()
        updateAccount(mid: mid) { account in
            account.cookies = cookies
        }
        persistAll()
    }

    @discardableResult
    func removeAccount(_ account: Account) -> Bool {
        storedAccounts.removeAll(where: { $0.profile.mid == account.profile.mid })
        persistAccounts()
        let removedActive = activeMID == account.profile.mid
        if removedActive {
            activeMID = nil
            persistActiveMID()
            if let next = storedAccounts.sorted(by: { $0.lastActiveAt > $1.lastActiveAt }).first {
                setActiveAccount(mid: next.profile.mid)
            } else {
                CookieHandler.shared.removeCookie()
                notifyChange()
            }
        } else {
            notifyChange()
        }
        return !storedAccounts.isEmpty
    }

    func removeAllAccounts() {
        storedAccounts.removeAll()
        persistAccounts()
        activeMID = nil
        persistActiveMID()
        CookieHandler.shared.removeCookie()
        notifyChange()
    }

    func handleAuthenticationFailure() {
        guard let account = activeAccount else { return }
        _ = removeAccount(account)
    }

    // MARK: - Private helpers

    /// The profile comes from a *web* endpoint, which means two things this has
    /// to work around.
    ///
    /// It needs the device fingerprint that the cookie swap immediately before
    /// this call may have dropped — without a buvid, 风控 rejects the request and
    /// the account gets stored as "UID 12345" with no avatar. `ensureFingerprint`
    /// is a no-op once the jar has one, so the common path costs nothing.
    ///
    /// And it answers for whoever the *cookies* say is signed in, not for
    /// `access_key`. A reply for a different mid means the jar is not the one we
    /// think it is, and writing that name onto this account would be worse than
    /// leaving the placeholder — so it is checked and dropped.
    private func fetchProfile(for mid: Int,
                              using token: LoginToken,
                              allowRetry: Bool = true,
                              completion: @escaping (Profile?) -> Void)
    {
        WebRequest.ensureFingerprint {
            WebRequest.requestLoginInfo(accessKey: token.accessToken) { [weak self] result in
                DispatchQueue.main.async {
                    if case let .success(json) = result, json["mid"].intValue == mid {
                        completion(Profile(mid: mid,
                                           username: json["uname"].stringValue,
                                           avatar: json["face"].stringValue))
                        return
                    }
                    // A -352 clears the wbi key cache on its way out, so a second
                    // attempt signs with fresh keys and usually lands.
                    guard let self, allowRetry else {
                        Logger.warn("profile fetch failed for mid \(mid), keeping placeholder name")
                        return completion(nil)
                    }
                    self.fetchProfile(for: mid, using: token, allowRetry: false, completion: completion)
                }
            }
        }
    }

    private func applyProfile(_ profile: Profile, to mid: Int) {
        guard storedAccounts.contains(where: { $0.profile.mid == mid }) else { return }
        updateAccount(mid: mid) { account in
            account.profile = profile
        }
        persistAll()
        notifyChange()
    }

    private func applyActiveAccountCookies() {
        guard let cookies = activeAccount?.cookies else { return }
        CookieHandler.shared.replaceCookies(with: cookies)
    }

    private func loadFromStorage() {
        if let data = storage.data(forKey: accountsKey) {
            do {
                storedAccounts = try JSONDecoder().decode([Account].self, from: data)
            } catch {
                storedAccounts = []
            }
        }
        if storage.object(forKey: activeKey) != nil {
            let mid = storage.integer(forKey: activeKey)
            activeMID = storedAccounts.contains(where: { $0.profile.mid == mid }) ? mid : nil
        }
    }

    private func persistAll() {
        persistAccounts()
        persistActiveMID()
    }

    private func persistAccounts() {
        let encoder = JSONEncoder()
        if let data = try? encoder.encode(storedAccounts) {
            storage.set(data, forKey: accountsKey)
        } else {
            storage.removeObject(forKey: accountsKey)
        }
    }

    private func persistActiveMID() {
        if let activeMID {
            storage.set(activeMID, forKey: activeKey)
        } else {
            storage.removeObject(forKey: activeKey)
        }
    }

    private func upsert(account: Account) {
        if let index = storedAccounts.firstIndex(where: { $0.profile.mid == account.profile.mid }) {
            storedAccounts[index] = account
        } else {
            storedAccounts.append(account)
        }
    }

    private func updateAccount(mid: Int, update: (inout Account) -> Void) {
        guard let index = storedAccounts.firstIndex(where: { $0.profile.mid == mid }) else { return }
        update(&storedAccounts[index])
    }

    private func notifyChange() {
        NotificationCenter.default.post(name: AccountManager.didUpdateNotification, object: self)
    }
}
