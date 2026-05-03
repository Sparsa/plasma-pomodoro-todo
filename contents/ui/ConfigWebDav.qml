import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasmoid

Item {
    id: configPage

    property bool   cfg_webdavEnabled:      plasmoid.configuration.webdavEnabled
    property string cfg_webdavUrl:          plasmoid.configuration.webdavUrl
    property string cfg_webdavUsername:     plasmoid.configuration.webdavUsername
    property string cfg_webdavPassword:     plasmoid.configuration.webdavPassword
    property bool   cfg_webdavAutoSync:     plasmoid.configuration.webdavAutoSync
    property int    cfg_webdavSyncInterval: plasmoid.configuration.webdavSyncInterval

    property bool   obscurePass:  true
    property string testMessage:  ""
    property bool   isTesting:    false
    property bool   testOk:       false

    implicitHeight: form.implicitHeight + Kirigami.Units.largeSpacing * 2

    WebDavSync {
        id: configWebDavSync
        allowAutoSync: false
        onSyncComplete: {}
    }

    function runTestConnection() {
        var url = configPage.cfg_webdavUrl.trim()
        if (!url) {
            configPage.testMessage = i18n("Enter a file URL first.")
            configPage.testOk      = false
            return
        }
        configPage.isTesting   = true
        configPage.testMessage = ""
        configPage.testOk      = false

        configWebDavSync.testConnection(
            url,
            configPage.cfg_webdavUsername.trim(),
            configPage.cfg_webdavPassword,
            function(ok, msg) {
                configPage.isTesting   = false
                configPage.testOk      = ok
                configPage.testMessage = msg
            }
        )
    }

    // ── Form ─────────────────────────────────────────────────────────────────
    Kirigami.FormLayout {
        id: form
        anchors { top: parent.top; left: parent.left; right: parent.right
                  margins: Kirigami.Units.largeSpacing }

        // ── Master toggle ─────────────────────────────────────────────────
        QQC2.CheckBox {
            Kirigami.FormData.label: i18n("WebDAV:")
            text: i18n("Enable WebDAV sync")
            checked: cfg_webdavEnabled
            onToggled: cfg_webdavEnabled = checked
        }

        // ── Server ────────────────────────────────────────────────────────
        Kirigami.Separator {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: i18n("Server")
        }

        QQC2.TextField {
            Kirigami.FormData.label: i18n("File URL:")
            Layout.minimumWidth: Kirigami.Units.gridUnit * 28
            placeholderText: "https://cloud.example.com/…/pomodoro-tasks.json"
            text: cfg_webdavUrl
            onTextChanged: cfg_webdavUrl = text
            inputMethodHints: Qt.ImhUrlCharactersOnly | Qt.ImhNoPredictiveText
        }

        QQC2.Label {
            Layout.fillWidth: true
            text: i18n("Full URL to the JSON file on your WebDAV server.\nNextcloud: https://cloud.example.com/remote.php/dav/files/user/pomodoro-tasks.json")
            wrapMode: Text.WordWrap
            opacity: 0.7
            font.pointSize: Kirigami.Theme.smallFont.pointSize
        }

        QQC2.TextField {
            Kirigami.FormData.label: i18n("Username:")
            Layout.minimumWidth: Kirigami.Units.gridUnit * 20
            text: cfg_webdavUsername
            onTextChanged: cfg_webdavUsername = text
        }

        RowLayout {
            Kirigami.FormData.label: i18n("Password:")
            spacing: Kirigami.Units.smallSpacing

            QQC2.TextField {
                Layout.minimumWidth: Kirigami.Units.gridUnit * 16
                echoMode: configPage.obscurePass ? TextInput.Password : TextInput.Normal
                placeholderText: i18n("Enter password")
                text: cfg_webdavPassword
                onTextChanged: cfg_webdavPassword = text
            }

            QQC2.CheckBox {
                text: i18n("Show")
                onToggled: configPage.obscurePass = !checked
            }
        }

        // ── Test connection ───────────────────────────────────────────────
        Kirigami.Separator {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: i18n("Connection")
        }

        RowLayout {
            Kirigami.FormData.label: " "
            spacing: Kirigami.Units.smallSpacing

            QQC2.Button {
                text: i18n("Test Connection")
                enabled: !configPage.isTesting
                onClicked: configPage.runTestConnection()
            }

            QQC2.BusyIndicator {
                visible: configPage.isTesting
                running: configPage.isTesting
                implicitWidth:  Kirigami.Units.iconSizes.small
                implicitHeight: Kirigami.Units.iconSizes.small
            }
        }

        QQC2.Label {
            visible: configPage.testMessage.length > 0
            text: configPage.testMessage
            color: configPage.testOk
                   ? Kirigami.Theme.positiveTextColor
                   : Kirigami.Theme.negativeTextColor
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
        }

        // ── Auto-sync ─────────────────────────────────────────────────────
        Kirigami.Separator {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: i18n("Sync")
        }

        QQC2.CheckBox {
            Kirigami.FormData.label: i18n("Auto-sync:")
            text: i18n("Sync automatically when tasks change")
            checked: cfg_webdavAutoSync
            onToggled: cfg_webdavAutoSync = checked
        }

        RowLayout {
            Kirigami.FormData.label: i18n("Sync interval:")
            spacing: Kirigami.Units.smallSpacing
            enabled: cfg_webdavAutoSync

            QQC2.SpinBox {
                from: 1
                to:   120
                value: cfg_webdavSyncInterval
                onValueModified: cfg_webdavSyncInterval = value
            }

            QQC2.Label { text: i18n("minutes") }
        }

        QQC2.Label {
            Layout.fillWidth: true
            text: i18n("When auto-sync is on, changes are pushed 2 seconds after you stop editing, and pulled every sync interval.")
            wrapMode: Text.WordWrap
            opacity: 0.7
            font.pointSize: Kirigami.Theme.smallFont.pointSize
        }
    }
}
