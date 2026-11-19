// [streamlock-patch] v11
import QtQuick 2.0
import QtQuick.Controls 2.2
import QtQuick.Layouts 1.2

import StreamLock 1.0

// 串流前的密码弹窗
NavigableDialog {
    id: lockDialog

    signal unlocked()
    signal cancelled()

    property string hostUuid: ""
    property string hostName: ""

    modal: true
    focus: true
    closePolicy: Popup.NoAutoClose
    standardButtons: Dialog.NoButton
    implicitWidth: 400
    width: 400
    padding: 24

    property string errorText: ""
    property int cooldown: 0

    function reset()
    {
        passwordField.text = ""
        errorText = ""
        cooldown = StreamLock.cooldownRemaining()
        cooldownTimer.running = cooldown > 0
    }

    function tryUnlock()
    {
        if (cooldown > 0 || passwordField.text.length === 0) {
            return
        }

        var error = StreamLock.unlockHost(hostUuid, passwordField.text)
        if (error === "") {
            close()
            unlocked()
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
        reset()
        passwordField.forceActiveFocus()
    }

    Timer {
        id: cooldownTimer
        interval: 1000
        repeat: true
        running: false

        onTriggered: {
            lockDialog.cooldown = StreamLock.cooldownRemaining()
            if (lockDialog.cooldown <= 0) {
                cooldownTimer.stop()
                passwordField.forceActiveFocus()
            }
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 14

        // 标题行：图标 + 标题
        RowLayout {
            spacing: 10

            Image {
                source: "qrc:/res/baseline-lock-24px.svg"
                sourceSize.width: 20
                sourceSize.height: 20
            }

            Label {
                text: qsTr("串流密码")
                font.pointSize: 14
            }

            Item {
                Layout.fillWidth: true
            }
        }

        Label {
            Layout.fillWidth: true
            text: qsTr("请输入「%1」的密码").arg(lockDialog.hostName.length > 0 ?
                                                 lockDialog.hostName : qsTr("这台电脑"))
            font.pointSize: 10
            color: "#b0bec5"
            wrapMode: Label.WordWrap
        }

        TextField {
            id: passwordField
            Layout.fillWidth: true
            implicitHeight: 38
            font.pointSize: 11
            placeholderText: qsTr("密码")
            echoMode: TextInput.Password
            inputMethodHints: Qt.ImhSensitiveData | Qt.ImhNoAutoUppercase | Qt.ImhNoPredictiveText | Qt.ImhHiddenText
            onAccepted: lockDialog.tryUnlock()
            onTextChanged: lockDialog.errorText = ""
        }

        Label {
            Layout.fillWidth: true
            text: lockDialog.errorText
            color: "#ff8a80"
            font.pointSize: 10
            wrapMode: Label.WordWrap
            visible: text !== ""
        }

        Label {
            Layout.fillWidth: true
            text: qsTr("失败次数过多，请 %1 秒后再试").arg(lockDialog.cooldown)
            color: "#ffcc80"
            font.pointSize: 10
            wrapMode: Label.WordWrap
            visible: lockDialog.cooldown > 0
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
                onClicked: {
                    lockDialog.close()
                    lockDialog.cancelled()
                }
            }

            Button {
                text: qsTr("解锁")
                highlighted: true
                font.pointSize: 10
                implicitWidth: 96
                implicitHeight: 34
                enabled: passwordField.text.length > 0 && lockDialog.cooldown <= 0
                onClicked: lockDialog.tryUnlock()
            }
        }
    }
}
