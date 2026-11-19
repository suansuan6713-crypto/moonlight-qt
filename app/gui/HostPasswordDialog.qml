// [streamlock-patch] v11
import QtQuick 2.0
import QtQuick.Controls 2.2
import QtQuick.Layouts 1.2

import StreamLock 1.0

// 添加 / 修改 / 删除某台电脑的串流密码（调用前必须已验证）
NavigableDialog {
    id: hostPasswordDialog

    signal saved()

    property string hostUuid: ""
    property string hostName: ""
    property string errorText: ""

    readonly property bool hasPassword: StreamLock.hostHasPassword(hostPasswordDialog.hostUuid)
    readonly property bool formValid: newPasswordField.text.length >= StreamLock.minimumPasswordLength
                                       && newPasswordField.text === confirmPasswordField.text

    modal: true
    focus: true
    closePolicy: Popup.CloseOnEscape
    standardButtons: Dialog.NoButton
    implicitWidth: 400
    width: 400
    padding: 24

    onOpened: {
        newPasswordField.text = ""
        confirmPasswordField.text = ""
        errorText = ""
        newPasswordField.forceActiveFocus()
    }

    onAccepted: {
        var error = StreamLock.setHostPassword(hostUuid, newPasswordField.text)
        if (error !== "") {
            errorText = error
            Qt.callLater(function() { hostPasswordDialog.open() })
            return
        }

        saved()
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
                text: hasPassword ? qsTr("修改串流密码") : qsTr("添加串流密码")
                font.pointSize: 14
            }

            Item {
                Layout.fillWidth: true
            }
        }

        Label {
            Layout.fillWidth: true
            text: qsTr("「%1」的密码，串流到它、修改密码、删除它时都会用到。").arg(hostPasswordDialog.hostName)
            font.pointSize: 10
            color: "#b0bec5"
            wrapMode: Label.WordWrap
        }

        Label {
            Layout.fillWidth: true
            text: hostPasswordDialog.errorText
            color: "#ff8a80"
            font.pointSize: 10
            wrapMode: Label.WordWrap
            visible: text !== ""
        }

        // 新密码
        ColumnLayout {
            spacing: 5
            Layout.fillWidth: true

            Label {
                text: qsTr("新密码（至少 %1 位）").arg(StreamLock.minimumPasswordLength)
                font.pointSize: 10
                color: "#b0bec5"
            }

            TextField {
                id: newPasswordField
                Layout.fillWidth: true
                implicitHeight: 38
                font.pointSize: 11
                echoMode: TextInput.Password
                inputMethodHints: Qt.ImhSensitiveData | Qt.ImhNoAutoUppercase | Qt.ImhNoPredictiveText | Qt.ImhHiddenText
                onAccepted: if (hostPasswordDialog.formValid) hostPasswordDialog.accept()
            }
        }

        // 确认
        ColumnLayout {
            spacing: 5
            Layout.fillWidth: true

            Label {
                text: qsTr("再输一次")
                font.pointSize: 10
                color: "#b0bec5"
            }

            TextField {
                id: confirmPasswordField
                Layout.fillWidth: true
                implicitHeight: 38
                font.pointSize: 11
                echoMode: TextInput.Password
                inputMethodHints: Qt.ImhSensitiveData | Qt.ImhNoAutoUppercase | Qt.ImhNoPredictiveText | Qt.ImhHiddenText
                onAccepted: if (hostPasswordDialog.formValid) hostPasswordDialog.accept()
            }
        }

        Item {
            height: 2
        }

        // 按钮行：删除（左）/ 取消 / 确定（右）
        RowLayout {
            spacing: 8

            Button {
                text: qsTr("删除这台的密码")
                visible: hostPasswordDialog.hasPassword
                flat: true
                font.pointSize: 9
                implicitHeight: 34
                onClicked: removeConfirmDialog.open()
            }

            Item {
                Layout.fillWidth: true
            }

            Button {
                text: qsTr("取消")
                flat: true
                font.pointSize: 10
                implicitWidth: 88
                implicitHeight: 34
                onClicked: hostPasswordDialog.reject()
            }

            Button {
                text: qsTr("确定")
                highlighted: true
                font.pointSize: 10
                implicitWidth: 96
                implicitHeight: 34
                enabled: hostPasswordDialog.formValid
                onClicked: hostPasswordDialog.accept()
            }
        }
    }

    NavigableMessageDialog {
        id: removeConfirmDialog
        text: qsTr("确定删除「%1」的串流密码吗？删除后串流到它就不再需要密码。").arg(hostPasswordDialog.hostName)
        standardButtons: Dialog.Yes | Dialog.No

        onAccepted: {
            var error = StreamLock.removeHostPassword(hostPasswordDialog.hostUuid)
            if (error !== "") {
                hostPasswordDialog.errorText = error
                return
            }

            hostPasswordDialog.close()
            hostPasswordDialog.saved()
        }
    }
}
