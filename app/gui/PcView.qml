import QtQuick 2.9
import QtQuick.Controls 2.2
import QtQuick.Layouts 1.3

import ComputerModel 1.0

import ComputerManager 1.0
import StreamingPreferences 1.0
import SystemProperties 1.0
import SdlGamepadKeyNavigation 1.0
import StreamLock 1.0

CenteredGridView {
    property ComputerModel computerModel : createModel()

    id: pcGrid
    focus: true
    activeFocusOnTab: true
    topMargin: 20
    bottomMargin: 5
    cellWidth: 310; cellHeight: 330;
    objectName: qsTr("Computers")

    // [streamlock-patch] 密码流程的临时状态
    property string pendingAction: ""
    property int pendingComputerIndex: -1
    property string pendingComputerName: ""
    property bool pendingShowHidden: false
    property int pendingDeleteIndex: -1
    property string pendingDeleteName: ""
    property string pendingEditUuid: ""
    property string pendingEditName: ""

    Component.onCompleted: {
        // Don't show any highlighted item until interacting with them.
        // We do this here instead of onActivated to avoid losing the user's
        // selection when backing out of a different page of the app.
        currentIndex = -1
    }

    // Note: Any initialization done here that is critical for streaming must
    // also be done in CliStartStreamSegue.qml, since this code does not run
    // for command-line initiated streams.
    StackView.onActivated: {
        // Setup signals on CM
        ComputerManager.computerAddCompleted.connect(addComplete)

        // Highlight the first item if a gamepad is connected
        if (currentIndex === -1 && SdlGamepadKeyNavigation.getConnectedGamepads() > 0) {
            currentIndex = 0
        }
    }

    StackView.onDeactivating: {
        ComputerManager.computerAddCompleted.disconnect(addComplete)
    }

    function pairingComplete(error)
    {
        // Close the PIN dialog
        pairDialog.close()

        // Display a failed dialog if we got an error
        if (error !== undefined) {
            errorDialog.text = error
            errorDialog.helpText = ""
            errorDialog.open()
        }
    }

    function addComplete(success, detectedPortBlocking)
    {
        if (!success) {
            errorDialog.text = qsTr("Unable to connect to the specified PC.")

            if (detectedPortBlocking) {
                errorDialog.text += "\n\n" + qsTr("This PC's Internet connection is blocking Moonlight. Streaming over the Internet may not work while connected to this network.")
            }
            else {
                errorDialog.helpText = qsTr("Click the Help button for possible solutions.")
            }

            errorDialog.open()
        }
    }

    function createModel()
    {
        var model = Qt.createQmlObject('import ComputerModel 1.0; ComputerModel {}', parent, '')
        model.initialize(ComputerManager)
        model.pairingCompleted.connect(pairingComplete)
        model.connectionTestCompleted.connect(testConnectionDialog.connectionTestComplete)
        return model
    }

    // [streamlock-patch] Open a PC, asking for its stream password when needed
    function requestAppView(computerIndex, name, uuid, showHidden)
    {
        if (StreamLock.hostHasPassword(uuid) && !StreamLock.hostUnlocked(uuid)) {
            pendingAction = "appview"
            pendingComputerIndex = computerIndex
            pendingComputerName = name
            pendingShowHidden = showHidden
            hostUnlockDialog.hostUuid = uuid
            hostUnlockDialog.hostName = name
            hostUnlockDialog.open()
            return
        }

        openAppView(computerIndex, name, showHidden)
    }

    function openAppView(computerIndex, name, showHidden)
    {
        var component = Qt.createComponent("AppView.qml")
        var appView = component.createObject(stackView, {"computerIndex": computerIndex, "objectName": name, "showHiddenGames": showHidden})
        stackView.push(appView)
    }

    function openPendingAppView()
    {
        if (pendingComputerIndex >= 0) {
            openAppView(pendingComputerIndex, pendingComputerName, pendingShowHidden)
            pendingComputerIndex = -1
        }
    }

    // [streamlock-patch] 右键菜单：添加/修改这台电脑的串流密码
    // 已有密码时：管理员密码或这台电脑的当前密码都能通过
    // 还没有密码时：只接受管理员密码
    function requestPasswordEdit(uuid, name)
    {
        const hasPassword = StreamLock.hostHasPassword(uuid)

        if (!hasPassword && !StreamLock.adminPasswordSet) {
            errorDialog.text = qsTr("请先在「设置 → 串流密码锁」里设置管理员密码。")
            errorDialog.helpText = ""
            errorDialog.open()
            return
        }

        pendingAction = "edit"
        pendingEditUuid = uuid
        pendingEditName = name

        if (hasPassword) {
            // 修改已有密码：每次都要先验证（管理员密码或这台电脑的串流密码）
            adminPasswordDialog.hostUuid = uuid
            adminPasswordDialog.promptText = qsTr("请输入管理员密码，或「%1」的串流密码。").arg(name)
            adminPasswordDialog.open()
            return
        }

        // 第一次添加密码：管理员密码即可（验证过 10 分钟内不重复问）
        if (StreamLock.adminUnlocked) {
            openHostPasswordDialog()
            return
        }

        adminPasswordDialog.hostUuid = ""
        adminPasswordDialog.promptText = qsTr("请输入管理员密码。")
        adminPasswordDialog.open()
    }

    function openHostPasswordDialog()
    {
        hostPasswordDialog.hostUuid = pendingEditUuid
        hostPasswordDialog.hostName = pendingEditName
        hostPasswordDialog.open()
    }

    // [streamlock-patch] 删除电脑也要管理员密码
    function requestDeletePc(computerIndex, name, uuid)
    {
        pendingDeleteIndex = computerIndex
        pendingDeleteName = name

        // 没设管理员密码时保持原样
        if (!StreamLock.adminPasswordSet) {
            openDeletePcDialog()
            return
        }

        pendingAction = "delete"
        if (StreamLock.adminUnlocked) {
            openDeletePcDialog()
        }
        else {
            adminPasswordDialog.hostUuid = ""
            adminPasswordDialog.promptText = qsTr("删除电脑需要管理员密码。")
            adminPasswordDialog.open()
        }
    }

    function openDeletePcDialog()
    {
        deletePcDialog.pcIndex = pendingDeleteIndex
        deletePcDialog.pcName = pendingDeleteName
        deletePcDialog.open()
    }

    Row {
        anchors.centerIn: parent
        spacing: 5
        visible: pcGrid.count === 0

        BusyIndicator {
            id: searchSpinner
            visible: StreamingPreferences.enableMdns
            running: visible
        }

        Label {
            height: searchSpinner.height
            elide: Label.ElideRight
            text: StreamingPreferences.enableMdns ? qsTr("Searching for compatible hosts on your local network...")
                                                  : qsTr("Automatic PC discovery is disabled. Add your PC manually.")
            font.pointSize: 20
            verticalAlignment: Text.AlignVCenter
            wrapMode: Text.Wrap
        }
    }

    model: computerModel

    delegate: NavigableItemDelegate {
        width: 300; height: 320;
        grid: pcGrid

        property alias pcContextMenu : pcContextMenuLoader.item

        // [streamlock-patch] 这台电脑是否有串流密码
        property bool hostLocked: {
            // 依赖 revision，改密码后角标会自动刷新
            StreamLock.revision
            return StreamLock.hostHasPassword(model.uuid)
        }

        Image {
            id: pcIcon
            anchors.horizontalCenter: parent.horizontalCenter
            source: "qrc:/res/desktop_windows-48px.svg"
            sourceSize {
                width: 200
                height: 200
            }
        }

        Image {
            // TODO: Tooltip
            id: stateIcon
            anchors.horizontalCenter: pcIcon.horizontalCenter
            anchors.verticalCenter: pcIcon.verticalCenter
            anchors.verticalCenterOffset: !model.online ? -18 : -16
            visible: !model.statusUnknown && (!model.online || !model.paired)
            source: !model.online ? "qrc:/res/warning_FILL1_wght300_GRAD200_opsz24.svg" : "qrc:/res/baseline-lock-24px.svg"
            sourceSize {
                width: !model.online ? 75 : 70
                height: !model.online ? 75 : 70
            }
        }

        BusyIndicator {
            id: statusUnknownSpinner
            anchors.horizontalCenter: pcIcon.horizontalCenter
            anchors.verticalCenter: pcIcon.verticalCenter
            anchors.verticalCenterOffset: -15
            width: 75
            height: 75
            visible: model.statusUnknown
            running: visible
        }

        Label {
            id: pcNameText
            text: model.name

            width: parent.width
            anchors.top: pcIcon.bottom
            anchors.bottom: parent.bottom
            font.pointSize: 30
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            elide: Text.ElideRight
        }

        // [streamlock-patch] 有密码的电脑右上角显示一个小锁胶囊
        Rectangle {
            visible: hostLocked
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.margins: 10
            width: lockBadgeRow.width + 16
            height: 24
            radius: 12
            color: "#3300bcd4"
            border.width: 1
            border.color: "#4400bcd4"

            Row {
                id: lockBadgeRow
                anchors.centerIn: parent
                spacing: 4

                Image {
                    anchors.verticalCenter: parent.verticalCenter
                    source: "qrc:/res/baseline-lock-24px.svg"
                    sourceSize.width: 13
                    sourceSize.height: 13
                }

                Label {
                    anchors.verticalCenter: parent.verticalCenter
                    text: qsTr("密码")
                    font.pointSize: 8
                    color: "#4dd0e1"
                }
            }
        }

        // Display a tooltip with the full name if it's truncated
        ToolTip.text: model.name
        ToolTip.delay: 1000
        ToolTip.timeout: 5000
        ToolTip.visible: (hovered || highlighted) && pcNameText.truncated

        Loader {
            id: pcContextMenuLoader
            asynchronous: true
            sourceComponent: NavigableMenu {
                id: pcContextMenu
                initiator: pcContextMenuLoader.parent
                MenuItem {
                    text: qsTr("PC Status: %1").arg(model.online ? qsTr("Online") : qsTr("Offline"))
                    font.bold: true
                    enabled: false
                }
                NavigableMenuItem {
                    text: qsTr("View All Apps")
                    onTriggered: pcGrid.requestAppView(index, model.name, model.uuid, true)
                    visible: model.online && model.paired
                }
                NavigableMenuItem {
                    text: qsTr("Wake PC")
                    onTriggered: computerModel.wakeComputer(index)
                    visible: !model.online && model.wakeable
                }
                NavigableMenuItem {
                    text: qsTr("Test Network")
                    onTriggered: {
                        computerModel.testConnectionForComputer(index)
                        testConnectionDialog.open()
                    }
                }

                NavigableMenuItem {
                    text: qsTr("Rename PC")
                    onTriggered: {
                        renamePcDialog.pcIndex = index
                        renamePcDialog.originalName = model.name
                        renamePcDialog.open()
                    }
                }
                NavigableMenuItem {
                    text: {
                        // 菜单是独立组件，这里不能直接引用 delegate 的属性
                        StreamLock.revision
                        return StreamLock.hostHasPassword(model.uuid) ? qsTr("修改密码…") : qsTr("添加密码…")
                    }
                    visible: model.paired
                    onTriggered: pcGrid.requestPasswordEdit(model.uuid, model.name)
                }
                NavigableMenuItem {
                    text: qsTr("删除电脑")
                    onTriggered: pcGrid.requestDeletePc(index, model.name, model.uuid)
                }
                NavigableMenuItem {
                    text: qsTr("View Details")
                    onTriggered: {
                        showPcDetailsDialog.pcDetails = model.details
                        showPcDetailsDialog.open()
                    }
                }
            }
        }

        onClicked: {
            if (model.online) {
                if (!model.serverSupported) {
                    errorDialog.text = qsTr("The version of GeForce Experience on %1 is not supported by this build of Moonlight. You must update Moonlight to stream from %1.").arg(model.name)
                    errorDialog.helpText = ""
                    errorDialog.open()
                }
                else if (model.paired) {
                    // [streamlock-patch] Ask for this PC's password before opening it
                    pcGrid.requestAppView(index, model.name, model.uuid, false)
                }
                else {
                    var pin = computerModel.generatePinString()

                    // Kick off pairing in the background
                    computerModel.pairComputer(index, pin)

                    // Display the pairing dialog
                    pairDialog.pin = pin
                    pairDialog.open()
                }
            } else if (!model.online) {
                // Using open() here because it may be activated by keyboard
                pcContextMenu.open()
            }
        }

        onPressAndHold: {
            // popup() ensures the menu appears under the mouse cursor
            if (pcContextMenu.popup) {
                pcContextMenu.popup()
            }
            else {
                // Qt 5.9 doesn't have popup()
                pcContextMenu.open()
            }
        }

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.RightButton;
            onClicked: {
                parent.pressAndHold()
            }
        }

        Keys.onMenuPressed: {
            // We must use open() here so the menu is positioned on
            // the ItemDelegate and not where the mouse cursor is
            pcContextMenu.open()
        }

        Keys.onDeletePressed: {
            pcGrid.requestDeletePc(index, model.name, model.uuid)
        }
    }

    ErrorMessageDialog {
        id: errorDialog

        // Using Setup-Guide here instead of Troubleshooting because it's likely that users
        // will arrive here by forgetting to enable GameStream or not forwarding ports.
        helpUrl: "https://github.com/moonlight-stream/moonlight-docs/wiki/Setup-Guide"
    }

    NavigableMessageDialog {
        id: pairDialog
        closePolicy: Popup.CloseOnEscape

        // don't allow edits to the rest of the window while open
        property string pin : "0000"
        text:qsTr("Please enter %1 on your host PC. This dialog will close when pairing is completed.").arg(pin)+"\n\n"+
             qsTr("If your host PC is running Sunshine, navigate to the Sunshine web UI to enter the PIN.")
        standardButtons: Dialog.Cancel
        onRejected: {
            // FIXME: We should interrupt pairing here
        }
    }

    NavigableMessageDialog {
        id: deletePcDialog
        // don't allow edits to the rest of the window while open
        property int pcIndex : -1
        property string pcName : ""
        text: qsTr("Are you sure you want to remove '%1'?").arg(pcName)
        standardButtons: Dialog.Yes | Dialog.No

        onAccepted: {
            computerModel.deleteComputer(pcIndex)
        }
    }

    NavigableMessageDialog {
        id: testConnectionDialog
        closePolicy: Popup.CloseOnEscape
        standardButtons: Dialog.Ok

        onAboutToShow: {
            testConnectionDialog.text = qsTr("Moonlight is testing your network connection to determine if any required ports are blocked.") + "\n\n" + qsTr("This may take a few seconds…")
            showSpinner = true
        }

        function connectionTestComplete(result, blockedPorts)
        {
            if (result === -1) {
                text = qsTr("The network test could not be performed because none of Moonlight's connection testing servers were reachable from this PC. Check your Internet connection or try again later.")
                imageSrc = "qrc:/res/baseline-warning-24px.svg"
            }
            else if (result === 0) {
                text = qsTr("This network does not appear to be blocking Moonlight. If you still have trouble connecting, check your PC's firewall settings.") + "\n\n" + qsTr("If you are trying to stream over the Internet, install the Moonlight Internet Hosting Tool on your gaming PC and run the included Internet Streaming Tester to check your gaming PC's Internet connection.")
                imageSrc = "qrc:/res/baseline-check_circle_outline-24px.svg"
            }
            else {
                text = qsTr("Your PC's current network connection seems to be blocking Moonlight. Streaming over the Internet may not work while connected to this network.") + "\n\n" + qsTr("The following network ports were blocked:") + "\n"
                text += blockedPorts
                imageSrc = "qrc:/res/baseline-error_outline-24px.svg"
            }

            // Stop showing the spinner and show the image instead
            showSpinner = false
        }
    }

    NavigableDialog {
        id: renamePcDialog
        property string label: qsTr("Enter the new name for this PC:")
        property string originalName
        property int pcIndex : -1;

        standardButtons: Dialog.Ok | Dialog.Cancel

        onOpened: {
            // Force keyboard focus on the textbox so keyboard navigation works
            editText.forceActiveFocus()
        }

        onClosed: {
            editText.clear()
        }

        onAccepted: {
            if (editText.text) {
                computerModel.renameComputer(pcIndex, editText.text)
            }
        }

        ColumnLayout {
            Label {
                text: renamePcDialog.label
                font.bold: true
            }

            TextField {
                id: editText
                placeholderText: renamePcDialog.originalName
                Layout.fillWidth: true
                focus: true

                Keys.onReturnPressed: {
                    renamePcDialog.accept()
                }

                Keys.onEnterPressed: {
                    renamePcDialog.accept()
                }
            }
        }
    }

    NavigableMessageDialog {
        id: showPcDetailsDialog
        property string pcDetails : "";
        text: showPcDetailsDialog.pcDetails
        imageSrc: "qrc:/res/baseline-help_outline-24px.svg"
        standardButtons: Dialog.Ok
    }

    // [streamlock-patch] 串流/删除前的密码弹窗，以及添加/修改密码弹窗
    StreamLockDialog {
        id: hostUnlockDialog
        onUnlocked: pcGrid.openPendingAppView()
    }

    AdminPasswordDialog {
        id: adminPasswordDialog
        onVerified: {
            if (pcGrid.pendingAction === "delete") {
                pcGrid.openDeletePcDialog()
            }
            else {
                pcGrid.openHostPasswordDialog()
            }
        }
    }

    HostPasswordDialog {
        id: hostPasswordDialog
    }

    ScrollBar.vertical: ScrollBar {}
}
