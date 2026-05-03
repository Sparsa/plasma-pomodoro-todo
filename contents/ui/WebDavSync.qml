import QtQuick
import org.kde.plasma.plasmoid

// WebDAV bidirectional sync engine.
//
// Stores tasks as a single JSON file on any WebDAV server (Nextcloud, ownCloud,
// Hetzner Storage Box, generic httpd with DAV, etc.).  The file URL is the full
// URL to that file — e.g.
//   https://cloud.example.com/remote.php/dav/files/user/pomodoro-tasks.json
//
// Auth: HTTP Basic (username + password).  Password lives in KWallet only
// ("webdav-password") — never in plasmoid.configuration.
//
// Conflict strategy: GET → merge per-task by lastModified → PUT.
// ETag-based optimistic locking: a 412 triggers one automatic retry.
// Deletion tracking: each workspace carries webdavSyncedUids — the set of UIDs
// present after the last sync — so we can tell "locally deleted" from "remotely
// added" without any additional server calls.
Item {
    id: webdavRoot
    visible: false

    // ── Public API ─────────────────────────────────────────────────────────────
    signal syncComplete(bool success, string message)

    property string syncStatus:   ""       // "" | "syncing" | "ok" | "error"
    property string syncMessage:  ""
    property bool   isSyncing:    false
    property bool   allowAutoSync: true    // set false inside config pages

    property var    _lastSyncData:               null
    property bool   _pendingTimerPush:           false
    property int    _pendingSessionCount:        0
    property string _pendingTimerMode:           ""
    property bool   _pendingIsRunning:           false
    property string _pendingEndTime:             ""
    property int    _pendingRemainingSeconds:    0
    property string _pendingLastModified:        ""

    signal timerStateReceived(var data)

    // Trigger a full sync cycle (pull → merge → push).
    function sync() {
        if (isSyncing) return
        if (!plasmoid.configuration.webdavEnabled) return
        var url = (plasmoid.configuration.webdavUrl || "").trim()
        if (!url) {
            syncStatus  = "error"
            syncMessage = i18n("No file URL — open Settings › WebDAV")
            syncComplete(false, syncMessage)
            return
        }
        var username = (plasmoid.configuration.webdavUsername || "").trim()
        var password = (plasmoid.configuration.webdavPassword || "").trim()
        if (!password) {
            syncStatus  = "error"
            syncMessage = i18n("No password saved — open Settings › WebDAV")
            syncComplete(false, syncMessage)
            return
        }

        isSyncing   = true
        syncStatus  = "syncing"
        syncMessage = i18n("Syncing…")

        _doSync(url, username, password)
    }

    // Debounced push — call from saveTasks() so changes are flushed after 2 s idle.
    function schedulePush() {
        pushDebounce.restart()
    }

    // Push timer state. Called on start/pause/reset/skip/session-complete.
    // isRunning, endTime, remainingSeconds, lastModified are optional for
    // backwards compat — defaults to a session-complete (isRunning: false) push.
    function pushTimerState(sessionCount, timerMode, isRunning, endTime, remainingSeconds, lastModified) {
        if (!plasmoid.configuration.webdavEnabled) return
        _pendingTimerPush          = true
        _pendingSessionCount       = sessionCount
        _pendingTimerMode          = timerMode
        _pendingIsRunning          = isRunning !== undefined ? !!isRunning : false
        _pendingEndTime            = endTime   || ""
        _pendingRemainingSeconds   = remainingSeconds || 0
        _pendingLastModified       = lastModified || new Date().toISOString()
        _doPushTimerState()
    }

    // GET the timer file and emit timerStateReceived — used by the fast-poll timer
    // in main.qml and by _finish() after a successful task sync.
    function pollTimerState() {
        if (!plasmoid.configuration.webdavEnabled) return
        var url = (plasmoid.configuration.webdavUrl || "").trim()
        if (!url) return
        var password = (plasmoid.configuration.webdavPassword || "").trim()
        if (!password) return
        var timerUrl = url.endsWith(".json")
            ? url.slice(0, -5) + "-timer.json"
            : url + "-timer.json"

        var xhr = new XMLHttpRequest()
        xhr.open("GET", timerUrl)
        if (plasmoid.configuration.webdavUsername)
            xhr.setRequestHeader("Authorization", _authHeader(plasmoid.configuration.webdavUsername, password))
        xhr.timeout = 10000
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE) return
            if (xhr.status === 200) {
                try { webdavRoot.timerStateReceived(JSON.parse(xhr.responseText)) } catch(e) {}
            }
        }
        xhr.onerror   = function() {}
        xhr.ontimeout = function() {}
        xhr.send()
    }

    function _doPushTimerState() {
        var url = (plasmoid.configuration.webdavUrl || "").trim()
        if (!url) return
        var password = (plasmoid.configuration.webdavPassword || "").trim()
        if (!password) return
        var timerUrl = url.endsWith(".json")
            ? url.slice(0, -5) + "-timer.json"
            : url + "-timer.json"

        var body = {
            sessionCount:     webdavRoot._pendingSessionCount,
            timerMode:        webdavRoot._pendingTimerMode,
            isRunning:        webdavRoot._pendingIsRunning,
            remainingSeconds: webdavRoot._pendingRemainingSeconds,
            lastModified:     webdavRoot._pendingLastModified
        }
        if (webdavRoot._pendingEndTime)
            body.endTime = webdavRoot._pendingEndTime

        var xhr = new XMLHttpRequest()
        xhr.open("PUT", timerUrl)
        if (plasmoid.configuration.webdavUsername)
            xhr.setRequestHeader("Authorization", _authHeader(plasmoid.configuration.webdavUsername, password))
        xhr.setRequestHeader("Content-Type", "application/json; charset=utf-8")
        xhr.timeout = 10000
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE) return
            if (xhr.status >= 200 && xhr.status < 300)
                webdavRoot._pendingTimerPush = false
        }
        xhr.onerror   = function() {}
        xhr.ontimeout = function() {}
        xhr.send(JSON.stringify(body))
    }

    // One-shot connectivity check — used by ConfigWebDav.
    // callback(ok: bool, message: string)
    function testConnection(url, username, password, callback) {
        var xhr = new XMLHttpRequest()
        xhr.open("HEAD", url)
        if (username)
            xhr.setRequestHeader("Authorization", _authHeader(username, password))
        xhr.timeout = 10000
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE) return
            if (xhr.status === 200 || xhr.status === 404) {
                callback(true, i18n("Connected"))
            } else if (xhr.status === 401 || xhr.status === 403) {
                callback(false, i18n("Authentication failed — check username and password"))
            } else if (xhr.status === 0) {
                callback(false, i18n("Network error — check URL and server address"))
            } else {
                callback(false, i18n("Server returned HTTP %1", xhr.status))
            }
        }
        xhr.ontimeout = function() { callback(false, i18n("Connection timed out")) }
        xhr.onerror   = function() { callback(false, i18n("Network error — check URL and server address")) }
        xhr.send()
    }

    // ── Private: sync orchestration ────────────────────────────────────────────

    function _doSync(url, username, password) {
        var local = []
        try { local = JSON.parse(plasmoid.configuration.tasks) } catch(e) {}
        if (!Array.isArray(local)) local = []

        _get(url, username, password, function(getOk, etag, remote) {
            if (!getOk) {
                isSyncing   = false
                syncStatus  = "error"
                syncMessage = typeof remote === "string" ? remote : i18n("Download failed")
                syncComplete(false, syncMessage)
                return
            }

            // remote === null means 404: file not on server yet — first upload.
            var merged = remote === null
                ? JSON.parse(JSON.stringify(local))
                : _merge(local, remote)

            // Stamp new webdavSyncedUids so the next sync can detect deletions.
            merged = merged.map(function(ws) {
                var copy = JSON.parse(JSON.stringify(ws))
                copy.webdavSyncedUids = (copy.tasks || []).map(function(t) { return t.uid }).filter(Boolean)
                return copy
            })

            _put(url, username, password, merged, etag, function(putOk, newEtag, conflict) {
                if (conflict) {
                    // Another client wrote the file while we were merging — retry once.
                    _get(url, username, password, function(ok2, etag2, remote2) {
                        if (!ok2) {
                            isSyncing   = false
                            syncStatus  = "error"
                            syncMessage = i18n("Sync conflict — retry failed")
                            syncComplete(false, syncMessage)
                            return
                        }
                        var merged2 = remote2 === null
                            ? JSON.parse(JSON.stringify(local))
                            : _merge(local, remote2)
                        merged2 = merged2.map(function(ws) {
                            var copy = JSON.parse(JSON.stringify(ws))
                            copy.webdavSyncedUids = (copy.tasks || []).map(function(t) { return t.uid }).filter(Boolean)
                            return copy
                        })
                        _put(url, username, password, merged2, etag2, function(ok3, etagOrMsg3) {
                            _finish(ok3, etagOrMsg3, merged2)
                        })
                    })
                    return
                }
                _finish(putOk, newEtag, merged)
            })
        })
    }

    // etagOrMsg: ETag string on success, error message string on failure.
    function _finish(ok, etagOrMsg, data) {
        if (ok) {
            if (etagOrMsg) plasmoid.configuration.webdavLastEtag = etagOrMsg
            webdavRoot._lastSyncData = data
            syncStatus  = "ok"
            syncMessage = i18n("Synced")
            if (webdavRoot._pendingTimerPush) _doPushTimerState()
            pollTimerState()
        } else {
            syncStatus  = "error"
            syncMessage = (typeof etagOrMsg === "string" && etagOrMsg)
                ? etagOrMsg
                : i18n("Upload failed — check server permissions")
        }
        isSyncing = false
        syncComplete(ok, syncMessage)
    }

    // ── Private: HTTP ──────────────────────────────────────────────────────────

    // callback(ok, etag, data)
    //   ok=true,  etag="",  data=null   → 404, file not on server yet
    //   ok=true,  etag=str, data=[...]  → 200, parsed JSON
    //   ok=false, etag="",  data=errStr → error
    function _get(url, username, password, callback) {
        var xhr = new XMLHttpRequest()
        xhr.open("GET", url)
        if (username)
            xhr.setRequestHeader("Authorization", _authHeader(username, password))
        xhr.timeout = 15000
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE) return
            if (xhr.status === 200) {
                var data = []
                try {
                    data = JSON.parse(xhr.responseText)
                } catch(e) {
                    callback(false, "", i18n("Server returned invalid JSON — is the URL correct?"))
                    return
                }
                callback(true, xhr.getResponseHeader("ETag") || "", data)
            } else if (xhr.status === 404) {
                callback(true, "", null)
            } else if (xhr.status === 401 || xhr.status === 403) {
                callback(false, "", i18n("Authentication failed — check credentials in Settings › WebDAV"))
            } else if (xhr.status === 0) {
                callback(false, "", i18n("Network error — check URL and server address"))
            } else {
                callback(false, "", i18n("Download failed (HTTP %1)", xhr.status))
            }
        }
        xhr.ontimeout = function() { callback(false, "", i18n("Network timeout")) }
        xhr.onerror   = function() { callback(false, "", i18n("Network error — check URL and server address")) }
        xhr.send()
    }

    // callback(ok, newEtag, conflict)
    //   conflict=true on HTTP 412 Precondition Failed
    function _put(url, username, password, data, etag, callback) {
        var xhr = new XMLHttpRequest()
        xhr.open("PUT", url)
        if (username)
            xhr.setRequestHeader("Authorization", _authHeader(username, password))
        xhr.setRequestHeader("Content-Type", "application/json; charset=utf-8")
        if (etag)
            xhr.setRequestHeader("If-Match", etag)
        xhr.timeout = 15000
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE) return
            if (xhr.status === 412) {
                callback(false, "", true)
            } else if (xhr.status >= 200 && xhr.status < 300) {
                callback(true, xhr.getResponseHeader("ETag") || "", false)
            } else if (xhr.status === 401 || xhr.status === 403) {
                callback(false, i18n("Authentication failed — check credentials in Settings › WebDAV"), false)
            } else if (xhr.status === 0) {
                callback(false, i18n("Network error — check URL and server address"), false)
            } else {
                callback(false, i18n("Upload failed (HTTP %1)", xhr.status), false)
            }
        }
        xhr.ontimeout = function() { callback(false, i18n("Network timeout"), false) }
        xhr.onerror   = function() { callback(false, i18n("Network error — check URL and server address"), false) }
        xhr.send(JSON.stringify(data))
    }

    // ── Private: merge ─────────────────────────────────────────────────────────

    // Merge local and remote workspace arrays.
    // local carries webdavSyncedUids (UIDs present after the previous sync),
    // which lets us distinguish "locally added" from "remotely deleted" and vice-versa.
    function _merge(local, remote) {
        var remoteByName = {}
        ;(remote || []).forEach(function(ws) { if (ws.name) remoteByName[ws.name] = ws })
        var localNames = {}
        ;(local  || []).forEach(function(ws) { if (ws.name) localNames[ws.name]  = true })

        var result = []

        ;(local || []).forEach(function(localWs) {
            var remoteWs = remoteByName[localWs.name]
            if (!remoteWs) {
                result.push(JSON.parse(JSON.stringify(localWs)))
                return
            }
            var merged = JSON.parse(JSON.stringify(localWs))
            merged.tasks = _mergeTasks(localWs, remoteWs)
            result.push(merged)
        })

        // Workspaces that exist only on the remote (added from another client).
        ;(remote || []).forEach(function(remoteWs) {
            if (remoteWs.name && !localNames[remoteWs.name])
                result.push(JSON.parse(JSON.stringify(remoteWs)))
        })

        return result
    }

    function _mergeTasks(localWs, remoteWs) {
        var localTasks  = localWs.tasks  || []
        var remoteTasks = remoteWs.tasks || []
        var prevSynced  = localWs.webdavSyncedUids || []   // UIDs at last successful sync

        var localByUid  = {}
        localTasks.forEach(function(t)  { if (t.uid) localByUid[t.uid]  = t })
        var remoteByUid = {}
        remoteTasks.forEach(function(t) { if (t.uid) remoteByUid[t.uid] = t })

        var result   = []
        var seenUids = {}

        // Collect every UID appearing on either side.
        var allUids = Object.keys(localByUid)
        Object.keys(remoteByUid).forEach(function(uid) {
            if (!localByUid[uid]) allUids.push(uid)
        })

        allUids.forEach(function(uid) {
            if (seenUids[uid]) return
            seenUids[uid] = true
            var loc = localByUid[uid]
            var rem = remoteByUid[uid]

            if (loc && rem) {
                // Present in both — newer lastModified wins.
                var locMod = loc.lastModified || ""
                var remMod = rem.lastModified || ""
                result.push(JSON.parse(JSON.stringify(remMod > locMod ? rem : loc)))

            } else if (loc && !rem) {
                // Only local.
                // Not in prevSynced → added locally after last sync → keep.
                // In prevSynced → absent on remote = remote deleted → drop.
                if (prevSynced.indexOf(uid) < 0)
                    result.push(JSON.parse(JSON.stringify(loc)))

            } else if (!loc && rem) {
                // Only remote.
                // Not in prevSynced → added remotely after last sync → pull.
                // In prevSynced → absent locally = local deleted → drop.
                if (prevSynced.indexOf(uid) < 0)
                    result.push(JSON.parse(JSON.stringify(rem)))
            }
        })

        // Tasks without uid (edge case) — keep all copies rather than risk data loss.
        localTasks.forEach(function(t)  { if (!t.uid) result.push(JSON.parse(JSON.stringify(t))) })
        remoteTasks.forEach(function(t) { if (!t.uid) result.push(JSON.parse(JSON.stringify(t))) })

        return result
    }

    // ── Private: auth ──────────────────────────────────────────────────────────

    function _authHeader(username, password) {
        // Pure-JS UTF-8 base64 — avoids relying on btoa() which is not guaranteed
        // in all QML/Qt versions and can silently break with non-ASCII characters.
        var str = username + ":" + password
        var bytes = []
        for (var i = 0; i < str.length; i++) {
            var c = str.charCodeAt(i)
            if (c < 0x80) {
                bytes.push(c)
            } else if (c < 0x800) {
                bytes.push(0xC0 | (c >> 6))
                bytes.push(0x80 | (c & 0x3F))
            } else {
                bytes.push(0xE0 | (c >> 12))
                bytes.push(0x80 | ((c >> 6) & 0x3F))
                bytes.push(0x80 | (c & 0x3F))
            }
        }
        var chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
        var b64 = ""
        for (var j = 0; j < bytes.length; j += 3) {
            var b0 = bytes[j]
            var b1 = j + 1 < bytes.length ? bytes[j + 1] : 0
            var b2 = j + 2 < bytes.length ? bytes[j + 2] : 0
            b64 += chars[b0 >> 2]
            b64 += chars[((b0 & 3) << 4) | (b1 >> 4)]
            b64 += j + 1 < bytes.length ? chars[((b1 & 0xF) << 2) | (b2 >> 6)] : "="
            b64 += j + 2 < bytes.length ? chars[b2 & 0x3F] : "="
        }
        return "Basic " + b64
    }

    // ── Timers ─────────────────────────────────────────────────────────────────

    Timer {
        id: periodicTimer
        interval: Math.max(1, plasmoid.configuration.webdavSyncInterval) * 60000
        repeat:   true
        running:  webdavRoot.allowAutoSync &&
                  plasmoid.configuration.webdavEnabled &&
                  plasmoid.configuration.webdavSyncInterval > 0 &&
                  !webdavRoot.isSyncing
        onTriggered: webdavRoot.sync()
    }

    Timer {
        id: pushDebounce
        interval: 2000
        repeat:   false
        onTriggered: webdavRoot.sync()
    }
}
