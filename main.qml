/******************************************************************************
 *
 * Copyright (C) 2018-2019 Marton Borzak <hello@martonborzak.com>
 *
 * This file is part of the YIO-Remote software project.
 *
 * YIO-Remote software is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * YIO-Remote software is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with YIO-Remote software. If not, see <https://www.gnu.org/licenses/>.
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 *****************************************************************************/

import QtQuick 2.11
import QtQuick.Controls 2.5
import QtQuick.VirtualKeyboard 2.2
import QtQuick.VirtualKeyboard.Settings 2.2

import Style 1.0

import Launcher 1.0
import JsonFile 1.0
import Battery 1.0
import DisplayControl 1.0
import Proximity 1.0
import StandbyControl 1.0

import Entity.Remote 1.0

// TODO: Softwareupdate needs to be moved to c++
import "qrc:/scripts/softwareupdate.js" as JSUpdate
import "qrc:/basic_ui" as BasicUI // TODO: can this be done in a singleton?

ApplicationWindow {
    id: applicationWindow
    objectName : "applicationWindow"

    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////\
    //
    // CURRENT SOFTWARE VERSION
    property real _current_version: 0.2 // change this when bumping the software version

    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    // TODO: Battery stuff should be moved to c++
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    // BATTERY
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    property real battery_voltage: 5
    property real battery_level: 1
    property real battery_health: 100
    property real battery_time: (new Date()).getTime()
    property int  battery_design_capacity: 0
    property int  battery_remaining_capacity: 0
    property int  battery_averagepower: 0
    property int  battery_averagecurrent: 0
    property bool wasBatteryWarning: false

    property var battery_data: []

    signal batteryDataUpdated()

    function checkBattery() {
        // read battery data
        battery_voltage = Battery.getVoltage() / 1000
        battery_level = Battery.getStateOfCharge() / 100
        battery_health = Battery.getStateOfHealth()
        battery_design_capacity = Battery.getDesignCapacity()
        battery_remaining_capacity = Battery.getRemainingCapacity()
        battery_averagepower = Battery.getAveragePower()
        battery_averagecurrent = Battery.getAverageCurrent()

        if (battery_level != -1) {

            // if the designcapacity is off correct it
            if (battery_design_capacity != Battery.capacity) {
                console.debug("Design capacity doesn't match. Recalibrating battery.");
                Battery.changeCapacity(Battery.capacity);
            }

            // if voltage is too low and we are sourcing power, turn off the remote after timeout
            if (0 < battery_voltage && battery_voltage <= 3.4 && battery_averagepower < 0) {
                shutdownDelayTimer.start();
            }

            // hide and show the charging screen
            if (battery_averagepower >= 0 && chargingScreen.item) {
                console.debug("Charging screen visible");
                chargingScreen.item.state = "visible";
                // cancel shutdown when started charging
                if (shutdownDelayTimer.running) {
                    shutdownDelayTimer.stop();
                }
            } else if (chargingScreen.item) {
                chargingScreen.item.state = "hidden";
            }

            // charging is done
            if (battery_averagepower == 0 && battery_level == 1) {
                // signal with the dock that the remote is fully charged
                var obj = integrations.get(config.settings.paired_dock);
                obj.sendCommand("dock", "", Remote.C_REMOTE_CHARGED, "");
            }

            console.debug("Average power:" + battery_averagepower + "mW");
            console.debug("Average current:" + battery_averagecurrent + "mA");
        }
    }

    Timer {
        id: shutdownDelayTimer
        running: false
        repeat: false
        interval: 20000

        onTriggered: {
            loadingScreen.source = "qrc:/basic_ui/ClosingScreen.qml";
            loadingScreen.active = true;
        }
    }

    // battery data logger
    Timer {
        running: true
        repeat: true
        interval: 600000

        onTriggered: {
            if (battery_data.length > 35) {
                battery_data.splice(0, 1);
            }

            var tmpA = battery_data;

            var tmp = {};
            tmp.timestamp = new Date();
            tmp.level = battery_level;
            tmp.power = Battery.getAveragePower();
            tmp.voltage = battery_voltage;

            tmpA.push(tmp);
            battery_data = tmpA;

            applicationWindow.batteryDataUpdated();
        }
    }

    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    // MAIN WINDOW PROPERTIES
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    visible: true
    width: 480
    height: 800
    color: Style.colorBackground


    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    // TRANSLATIONS
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    property var translations: translationsJson.read()

    JsonFile {
        id: translationsJson
        name: appPath + "/translations.json"
    }

    // TODO: Softwareupdate in c++
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    // SOFTWARE UPDATE
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    property bool updateAvailable: false
    property real _new_version
    property string updateURL

    Timer {
        repeat: true
        running: true
        interval: 3600000
        triggeredOnStart: true

        onTriggered: {
            if (config.settings.softwareupdate) {
                JSUpdate.checkForUpdate();

                if (updateAvailable) {
                    var hour = new Date().getHours();
                    if (hour >= 3 && hour <= 5) {
                        // TODO create a update service class instead of launching hard coded shell scripts from QML
                        fileio.write("/usr/bin/updateURL", updateURL);
                        mainLauncher.launch("systemctl restart update.service");
                        Qt.quit();
                    }
                }
            }
        }
    }

    Launcher { id: mainLauncher }

    onUpdateAvailableChanged: {
        if (updateAvailable) {
            //: Notification text when new software update is available
            notifications.add(qsTr("New software version is available!") + translateHandler.emptyString);
        }
    }

    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    // CONFIGURATION
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    Component.onCompleted: {
        // change dark mode to the configured value
        Style.darkMode = Qt.binding(function () { return config.ui_config.darkMode });

        // TODO(mze) Does the initialization need to be here? Better located in hardware factory.
        //           Or is there some magic sauce calling the setter if config.settings.proximity changed?
        Proximity.proximitySetting = Qt.binding(function() { return config.settings.proximity })

        // load the integrations
        integrations.load();

        // set the language
        translateHandler.selectLanguage(config.settings.language);

        // load bluetooth
        bluetoothArea.init(config.config);
        if (config.settings.bluetootharea) {
            bluetoothArea.startScan();
        }

        // Start websocket API
        api.start();

        // FIXME initialize capacity in device builder
        Battery.capacity = 2500;
        Battery.begin();
        checkBattery();
    }

    // load the entities when the integrations are loaded
    Connections {
        target: integrations

        onLoadComplete: {
            console.debug("Integrations are loaded.");
            entities.load();
        }
    }

    Connections {
        target: entities

        onEntitiesLoaded: {
            console.debug("Entities are loaded.");

            // when everything is loaded, load the main UI
            if (fileio.exists("/wifisetup")) {
                console.debug("Starting WiFi setup");
                loader_main.setSource("qrc:/wifiSetup.qml");
            } else {
                loader_main.setSource("qrc:/MainContainer.qml");
            }
        }
    }

    // TODO: this will be a singleton c++ class
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    // BUTTON HANDLER
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    ButtonHandler{
        id: buttonHandler
    }


    // TODO: this will be a singleton c++ class
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    // QML GUI STUFF
    // The main container holds almost all the GUI elements. The secondary container is used to load the buttons into, with their open state.

    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    // MAIN CONTAINER
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    Loader {
        id: loader_main
        asynchronous: true
        width: 480
        height: 800
        x: 0
        y: 0
        active: false
        state: "visible"

        transform: Scale {
            id: scale
            origin.x: loader_main.width/2
            origin.y: loader_main.height/2
        }

        states: [
            State { name: "hidden"; PropertyChanges {target: loader_main; y: -60; scale: 0.8; opacity: 0.4}},
            State { name: "visible"; PropertyChanges {target: loader_main; scale: 1; opacity: 1}}
        ]
        transitions: [
            Transition {to: "hidden"; PropertyAnimation { target: loader_main; properties: "y, scale, opacity"; easing.type: Easing.OutExpo; duration: 800 }},
            Transition {to: "visible"; PropertyAnimation { target: loader_main; properties: "y, scale, opacity"; easing.type: Easing.OutExpo; duration: 500 }}
        ]

        Connections {
            target: loader_main.item
            enabled: loader_main.status == Loader.Ready
            ignoreUnknownSignals: true

            onLoadedItems: {
                console.debug("Setting loading screen to loaded");
                loadingScreen.item.state = "loaded";
            }
        }
    }

    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    // SECONDARY CONTAINER
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    property alias loader_second: loader_second

    Loader {
        id: loader_second
        asynchronous: true
    }

    property alias contentWrapper: contentWrapper

    Item {
        id: contentWrapper
        width: 480
        height: 800
        x: 0
        y: 0
    }

    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    // VOLUME
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    property alias volume: volume

    BasicUI.Volume {
        id: volume
        anchors {
            bottom: parent.bottom
            horizontalCenter: parent.horizontalCenter
        }
    }

    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    // CHARING SCREEN
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    // Visible when charging

    property alias chargingScreen: chargingScreen
    Loader {
        id: chargingScreen
        width: 480
        height: 800
        x: 0
        y: 0
        asynchronous: true
        source: "qrc:/basic_ui/ChargingScreen.qml"
    }


    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    // LOW BATTERY POPUP NOTIFICAITON
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    // Pops up when battery level is under 20%
    // TODO: this should be a signal connection to the singleton c++ class
    onBattery_levelChanged: {
        if (battery_level < 0.1 && !wasBatteryWarning) {
            lowBatteryNotification.item.open();
            wasBatteryWarning = true;
            standbyControl.touchDetected = true;

            // signal with the dock that it is low battery
            var obj = integrations.get(config.settings.paired_dock);
            obj.sendCommand("dock", "", Remote.C_REMOTE_LOWBATTERY, "");
        }
        if (battery_level > 0.2) {
            wasBatteryWarning = false;
        }
    }

    property alias lowBatteryNotification: lowBatteryNotification

    Loader {
        id: lowBatteryNotification
        width: 480
        height: 800
        x: 0
        y: 0
        asynchronous: true
        source: "qrc:/basic_ui/PopupLowBattery.qml"
    }


    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    // NOTIFICATIONS
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    // TODO: can this be done in c++?
    function showNotification(data) {
        var comp = Qt.createComponent("qrc:/basic_ui/Notification.qml");
        var obj = comp.createObject(notificationsRow, {type: data.error, text: data.text, actionlabel: data.actionlabel, action: data.action, timestamp: data.timestamp, idN: data.id, _state: "visible"});
    }

    Column {
        objectName: "notificationsRow"
        id: notificationsRow
        anchors.fill: parent
        spacing: 10
        topPadding: 20
    }

    //////////////////////////////////////////////////////////////////////////////////////////////////
    // NOTIFICATION DRAWER
    //////////////////////////////////////////////////////////////////////////////////////////////////

    Drawer {
        id: notificationsDrawer
        width: parent.width
        height: notifications.list.length > 5 ? 100 + 5 * 104 : 100 + (notifications.list.length + 1) * 104
        edge: Qt.TopEdge
        dragMargin: 20
        interactive: loader_main.state == "visible" ? true : false
        dim: false
        opacity: position

        background: Item {
            x: parent.width - 1
            width: parent.width
            height: parent.height
//            color: Style.colorBackgroundTransparent
        }

        Rectangle {
            width: parent.width
            height: parent.height - 40
            y: 40
            color: Style.colorBackground
            opacity: notificationsDrawer.position
        }

        onOpened: {
            loader_main.item.mainNavigation.opacity = 0.3
            loader_main.item.mainNavigationSwipeview.opacity = 0.3
        }

        onClosed: {
            loader_main.item.mainNavigation.opacity = 1
            loader_main.item.mainNavigationSwipeview.opacity = 1
        }

        Loader {
            width: parent.width
            height: parent.height

            asynchronous: true
            active: notificationsDrawer.position > 0 ? true : false
            source: notificationsDrawer.position > 0 ? "qrc:/basic_ui/NotificationDrawer.qml" : ""
        }

//        property int n: notifications.list.length

//        onNChanged: {
//            if (n==0) {
//                notificationsDrawer.close();
//            }
//        }

        Connections {
            target: notifications

            onListIsEmpty: {
                    notificationsDrawer.close();
            }
        }
    }

    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    // LOADING SCREEN
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    property alias loadingScreen: loadingScreen
    Loader {
        id: loadingScreen
        objectName: "loadingScreen"
        width: parent.width
        height: parent.height

        asynchronous: true
        active: true
        source: "qrc:/basic_ui/LoadingScreen.qml"

        onSourceChanged: {
            if (source == "") {
                console.debug("Now load the rest off stuff");
                //battery.checkBattery();
            }
        }
    }

    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    // STANDBY MODE TOUCHEVENT OVERLAY
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    // captures all touch events when in standby mode. Avoids clicking on random buttons when waking up the display
    property alias touchEventCatcher: touchEventCatcher

    MouseArea {
        id: touchEventCatcher
        anchors.fill: parent
        enabled: false
        pressAndHoldInterval: 5000

        onPressAndHold: {
            console.debug("Disabling touch even catcher");

            touchEventCatcher.enabled = false;
            DisplayControl.setMode(DisplayControl.StandbyOff);
            if (config.settings.autobrightness) {
                DisplayControl.setBrightness(DisplayControl.ambientBrightness());
            } else {
                DisplayControl.setBrightness(DisplayControl.userBrightness());
            }
        }
    }

    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    // KEYBOARD
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    InputPanel {
        id: inputPanel
        width: parent.width
        y: applicationWindow.height

        states: State {
            name: "visible"
            when: inputPanel.active
            PropertyChanges {
                target: inputPanel
                y: applicationWindow.height - inputPanel.height
            }
        }
        transitions: Transition {
            id: inputPanelTransition
            from: ""
            to: "visible"
            reversible: true
            ParallelAnimation {
                NumberAnimation {
                    properties: "y"
                    duration: 300
                    easing.type: Easing.InOutExpo
                }
            }
        }
    }
}
