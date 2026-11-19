// [streamlock-patch] v11
import QtQuick 2.0
import QtQuick.Controls 2.2
import QtQuick.Layouts 1.2

import StreamLock 1.0

// 修改/删除密码、删除电脑前，先验证密码
NavigableDialog {
    id: adminPasswordDialog

    signal verified()

    modal: true
    focus: true
    closePolicy: Popup.CloseOnEscape
    standardButtons: Dialog.NoButton
    implicitWidth: 400
    width: 400
    padding: 24

    // 为空 = 只接受管理员密码；不为空 = 管理员密码或这台电脑的串流密码都可以
    property string hostUuid: ""
    property string promptText: qsTr("请输入管理员密码。")
    property string errorText: ""
    property int cooldown: 0

    function tryVerify()
    {
        if (cooldown > 0 || passwordField.text.length === 0) {
            return
        }

        var error = hostUuid.length > 0 ? StreamLock.authorizeHostEdit(hostUuid, passwordField.text)
                                        : StreamLock.verifyAdminPassword(passwordField.text)
        if (error === "") {
            passwordField.text = ""
            close()
            verified()
        }
        else {
            errorText = error
            passwordField.text = ""
            passwordField.forceActiveFocus()
            cooldown = StreamLock.cooldownRemaining()
            cooldownTimer.running = cooldown > 0
        }
    }

    onOpened: {
        passwordField.text = ""
        errorText = ""
        cooldown = StreamLock.cooldownRemaining()
        cooldownTimer.running = cooldown > 0
        passwordField.forceActiveFocus()
    }

    Timer {
        id: cooldownTimer
        interval: 1000
        repeat: true
        running: false

        onTriggered: {
            adminPasswordDialog.cooldown = StreamLock.cooldownRemaining()
            if (adminPasswordDialog.cooldown <= 0) {
                cooldownTimer.stop()
                passwordField.forceActiveFocus()
            }
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 14

        // 标题行
        RowLayout {
            spacing: 10

            Image {
                source: "qrc:/res/baseline-lock-24px.svg"
                sourceSize.width: 20
                sourceSize.height: 20
            }

            Label {
                text: qsTr("验证密码")
                font.pointSize: 14
            }

            Item {
                Layout.fillWidth: true
            }
        }

        Label {
            Layout.fillWidth: true
            text: adminPasswordDialog.promptText
            font.pointSize: 10
            color: "#b0bec5"
            wrapMode: Label.WordWrap
        }

        TextField {
            id: passwordField
            Layout.fillWidth: true
            implicitHeight: 38
            font.pointSize: 11
            placeholderText: hostUuid.length > 0 ? qsTr("管理员密码 或 这台电脑的密码") : qsTr("管理员密码")
            echoMode: TextInput.Password
            inputMethodHints: Qt.ImhSensitiveData | Qt.ImhNoAutoUppercase | Qt.ImhNoPredictiveText | Qt.ImhHiddenText
            onAccepted: adminPasswordDialog.tryVerify()
            onTextChanged: adminPasswordDialog.errorText = ""
        }

        Label {
            Layout.fillWidth: true
            text: adminPasswordDialog.errorText
            color: "#ff8a80"
            font.pointSize: 10
            wrapMode: Label.WordWrap
            visible: text !== ""
        }

        Label {
            Layout.fillWidth: true
            text: qsTr("失败次数过多，请 %1 秒后再试").arg(adminPasswordDialog.cooldown)
            color: "#ffcc80"
            font.pointSize: 10
            wrapMode: Label.WordWrap
            visible: adminPasswordDialog.cooldown > 0
        }

        Item {
            height: 2
        }

        // 按钮行
        RowLayout {
            spacing: 8

            Item {
                Layout.fillWidth: true
            }

            Button {
                text: qsTr("取消")
                flat: true
                font.pointSize: 10
                implicitWidth: 88
                implicitHeight: 34
                onClicked: adminPasswordDialog.close()
            }

            Button {
                text: qsTr("确定")
                highlighted: true
                font.pointSize: 10
                implicitWidth: 96
                implicitHeight: 34
                enabled: passwordField.text.length > 0 && adminPasswordDialog.cooldown <= 0
                onClicked: adminPasswordDialog.tryVerify()
            }
        }
    }
}
