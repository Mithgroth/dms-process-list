import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Common
import qs.Services
import qs.Widgets
import qs.Modules.Plugins

DesktopPluginComponent {
    id: root

    widgetWidth: 560
    widgetHeight: 640
    minWidth: 320
    minHeight: 240

    property bool showHeader: pluginData.showHeader ?? true
    property real transparency: pluginData.transparency ?? 0.8
    property string colorMode: pluginData.colorMode ?? "primary"
    property color customColor: pluginData.customColor ?? "#ffffff"
    property string sortBy: pluginData.sortBy ?? "cpu"
    property bool sortDescending: pluginData.sortDescending ?? true
    property bool groupedView: pluginData.groupedView ?? true
    property string processScope: pluginData.processScope ?? "user"
    property bool hideIdleProcesses: pluginData.hideIdleProcesses ?? false
    property bool showPid: pluginData.showPid ?? true
    property bool showCpu: pluginData.showCpu ?? true
    property bool showMemory: pluginData.showMemory ?? true
    property real idleCpuThreshold: pluginData.idleCpuThreshold ?? 0.1
    property real idleMemoryThreshold: pluginData.idleMemoryThreshold ?? 0.2
    property string currentLoginUser: (Quickshell.env("USER") || "").trim()

    property var rawProcesses: []
    property var processes: []
    property int groupCount: 0
    property int visibleProcessCount: 0
    property var expandedGroups: ({})
    property string lastError: ""
    property bool ownerScopeAvailable: false

    readonly property color accentColor: {
        switch (colorMode) {
        case "secondary":
            return Theme.secondary;
        case "custom":
            return customColor;
        default:
            return Theme.primary;
        }
    }
    readonly property color bgColor: Theme.withAlpha(Theme.surface, root.transparency)
    readonly property color tileBg: Theme.withAlpha(Theme.surfaceContainerHigh, root.transparency)
    readonly property color textColor: Theme.surfaceText
    readonly property color dimColor: Theme.surfaceVariantText
    readonly property color rowHoverColor: Theme.withAlpha(root.accentColor, 0.14)
    readonly property color userProcessColor: Theme.withAlpha(root.accentColor, 0.95)
    readonly property color systemProcessColor: Theme.withAlpha(root.dimColor, 0.95)
    readonly property color mixedProcessColor: Theme.surfaceText

    readonly property int cpuColWidth: showCpu ? 78 : 0
    readonly property int memColWidth: showMemory ? 92 : 0
    readonly property int pidColWidth: showPid ? 68 : 0
    readonly property int countColWidth: groupedView ? 60 : 0

    function refreshProcesses() {
        syncFromDgopService();
    }

    function normalizedCpu(cpuValue) {
        return cpuValue || 0;
    }

    function ownerTypeForUsername(username) {
        const user = (username || "").trim();
        if (!user) {
            return "system";
        }
        if (!root.currentLoginUser) {
            return user === "root" ? "system" : "user";
        }
        return user === root.currentLoginUser ? "user" : "system";
    }

    function mergeOwnerType(currentType, nextType) {
        if (!currentType) {
            return nextType;
        }
        if (currentType === nextType) {
            return currentType;
        }
        return "mixed";
    }

    function ownerColor(ownerType) {
        switch (ownerType) {
        case "user":
            return root.userProcessColor;
        case "system":
            return root.systemProcessColor;
        case "mixed":
            return root.mixedProcessColor;
        default:
            return root.dimColor;
        }
    }

    function visibleRawProcesses() {
        if (!root.ownerScopeAvailable && root.processScope !== "all") {
            return root.rawProcesses;
        }

        let scoped = [];
        if (root.processScope === "all") {
            scoped = root.rawProcesses;
        } else if (root.processScope === "system") {
            scoped = root.rawProcesses.filter(process => (process.ownerType || "unknown") === "system");
        } else {
            scoped = root.rawProcesses.filter(process => (process.ownerType || "unknown") === "user");
        }

        if (!root.hideIdleProcesses) {
            return scoped;
        }
        return scoped.filter(process => {
            const cpuNormalized = root.normalizedCpu(process.cpu);
            const mem = process.memoryPercent || 0;
            return cpuNormalized >= root.idleCpuThreshold || mem >= root.idleMemoryThreshold;
        });
    }

    function sortLabel(baseText, key) {
        if (root.sortBy !== key) {
            return baseText;
        }
        return baseText + (root.sortDescending ? "  \u25BC" : "  \u25B2");
    }

    function setSort(key) {
        if (root.sortBy === key) {
            root.sortDescending = !root.sortDescending;
        } else {
            root.sortBy = key;
            root.sortDescending = key !== "name" && key !== "pid";
        }

        pluginData.sortBy = root.sortBy;
        pluginData.sortDescending = root.sortDescending;
        root.rebuildRows();
    }

    function compareRows(a, b) {
        let cmp = 0;
        switch (root.sortBy) {
        case "count":
            cmp = (a.count || 0) - (b.count || 0);
            break;
        case "memory":
            cmp = (a.memoryPercent || 0) - (b.memoryPercent || 0);
            break;
        case "name":
            cmp = (a.command || "").localeCompare(b.command || "");
            break;
        case "pid":
            cmp = (a.pid || 0) - (b.pid || 0);
            break;
        case "cpu":
        default:
            cmp = (a.cpu || 0) - (b.cpu || 0);
            break;
        }

        if (cmp === 0) {
            cmp = (a.command || "").localeCompare(b.command || "");
        }
        if (cmp === 0) {
            cmp = (a.pid || 0) - (b.pid || 0);
        }
        return root.sortDescending ? -cmp : cmp;
    }

    function sortProcesses(data) {
        const sorted = data.slice();
        sorted.sort((a, b) => {
            return root.compareRows(a, b);
        });
        return sorted;
    }

    function toggleGroup(command) {
        const nextExpanded = {};
        for (const key in root.expandedGroups) {
            nextExpanded[key] = root.expandedGroups[key];
        }
        nextExpanded[command] = !nextExpanded[command];
        root.expandedGroups = nextExpanded;
        root.rebuildRows();
    }

    function buildGroupedRows(data) {
        const grouped = {};
        for (const process of data) {
            const command = ((process.command || "").trim()) || "unknown";
            if (!grouped[command]) {
                grouped[command] = {
                    "command": command,
                    "count": 0,
                    "cpu": 0,
                    "memoryPercent": 0,
                    "pid": process.pid || 0,
                    "ownerType": process.ownerType || "unknown",
                    "children": []
                };
            }

            const entry = grouped[command];
            entry.count += 1;
            entry.cpu += process.cpu || 0;
            entry.memoryPercent += process.memoryPercent || 0;
            entry.pid = Math.min(entry.pid, process.pid || 0);
            entry.ownerType = root.mergeOwnerType(entry.ownerType, process.ownerType || "unknown");
            entry.children.push(process);
        }

        const groups = Object.values(grouped);
        groups.sort((a, b) => root.compareRows(a, b));

        const rows = [];
        let groupedRows = 0;
        for (const group of groups) {
            if ((group.count || 0) <= 1) {
                const onlyProcess = group.children[0];
                rows.push({
                    "rowId": "process-" + onlyProcess.pid.toString(),
                    "rowType": "process",
                    "command": onlyProcess.command,
                    "count": 1,
                    "cpu": onlyProcess.cpu,
                    "memoryPercent": onlyProcess.memoryPercent,
                    "pid": onlyProcess.pid,
                    "ownerType": onlyProcess.ownerType || "unknown"
                });
                continue;
            }

            groupedRows += 1;
            rows.push({
                "rowId": "group-" + group.command,
                "rowType": "group",
                "command": group.command,
                "count": group.count,
                "cpu": group.cpu,
                "memoryPercent": group.memoryPercent,
                "pid": group.pid,
                "ownerType": group.ownerType || "unknown"
            });

            if (root.expandedGroups[group.command]) {
                const children = root.sortProcesses(group.children);
                for (const process of children) {
                    rows.push({
                        "rowId": "process-" + process.pid.toString() + "-" + group.command,
                        "rowType": "child",
                        "command": process.command,
                        "count": 1,
                        "cpu": process.cpu,
                        "memoryPercent": process.memoryPercent,
                        "pid": process.pid,
                        "ownerType": process.ownerType || "unknown"
                    });
                }
            }
        }

        return {
            "rows": rows,
            "groupCount": groupedRows
        };
    }

    function rebuildRows() {
        const sourceData = root.visibleRawProcesses();
        root.visibleProcessCount = sourceData.length;
        if (root.groupedView) {
            const groupedData = root.buildGroupedRows(sourceData);
            root.processes = groupedData.rows;
            root.groupCount = groupedData.groupCount;
            return;
        }

        root.processes = root.sortProcesses(sourceData);
        root.groupCount = 0;
    }

    function syncFromDgopService() {
        if (!DgopService.dgopAvailable) {
            root.rawProcesses = [];
            root.processes = [];
            root.groupCount = 0;
            root.visibleProcessCount = 0;
            root.ownerScopeAvailable = false;
            root.lastError = "dgop not available";
            return;
        }

        const source = Array.isArray(DgopService.allProcesses) ? DgopService.allProcesses : [];
        let hasOwnerData = false;
        const parsed = [];

        for (const proc of source) {
            const pid = parseInt(proc.pid, 10);
            if (!isFinite(pid) || pid <= 0) {
                continue;
            }

            const username = (proc.username || "").trim();
            const cpu = parseFloat(proc.cpu);
            const memoryPercent = parseFloat(proc.memoryPercent);
            const pssPercent = parseFloat(proc.pssPercent);
            const command = ((proc.command || "").trim()) || ((proc.fullCommand || "").trim()) || "unknown";

            if (username.length > 0) {
                hasOwnerData = true;
            }

            parsed.push({
                "pid": pid,
                "rowId": "process-" + pid.toString(),
                "cpu": isFinite(cpu) ? cpu : 0,
                "memoryPercent": isFinite(memoryPercent) ? memoryPercent : (isFinite(pssPercent) ? pssPercent : 0),
                "command": command,
                "username": username,
                "ownerType": username.length > 0 ? root.ownerTypeForUsername(username) : "unknown"
            });
        }

        root.rawProcesses = parsed;
        root.ownerScopeAvailable = hasOwnerData;
        if (!root.ownerScopeAvailable && root.processScope !== "all") {
            root.processScope = "all";
            pluginData.processScope = "all";
        }
        root.rebuildRows();
        root.lastError = "";
    }

    Component.onCompleted: {
        DgopService.addRef(["processes"]);
        root.refreshProcesses();
    }
    Component.onDestruction: {
        DgopService.removeRef(["processes"]);
    }
    onSortByChanged: rebuildRows()
    onSortDescendingChanged: rebuildRows()
    onGroupedViewChanged: {
        pluginData.groupedView = root.groupedView;
        rebuildRows();
    }
    onProcessScopeChanged: {
        pluginData.processScope = root.processScope;
        rebuildRows();
    }
    onHideIdleProcessesChanged: {
        pluginData.hideIdleProcesses = root.hideIdleProcesses;
        rebuildRows();
    }

    Connections {
        target: DgopService
        function onAllProcessesChanged() {
            root.refreshProcesses();
        }
        function onDgopAvailableChanged() {
            root.refreshProcesses();
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: Theme.cornerRadius
        color: root.bgColor
        border.width: 0

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: Theme.spacingS
                spacing: Theme.spacingS

            Item {
                Layout.fillWidth: true
                implicitHeight: 28

                RowLayout {
                    anchors.fill: parent
                    spacing: Theme.spacingXS

                    Item {
                        Layout.fillWidth: true
                        implicitHeight: processHeader.implicitHeight

                        StyledText {
                            id: processHeader
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.sortLabel(I18n.tr("Process") + " (" + root.visibleProcessCount + ")", "name")
                            font.pixelSize: Theme.fontSizeSmall
                            font.weight: root.sortBy === "name" ? Font.Bold : Font.Medium
                            isMonospace: true
                            color: root.sortBy === "name" ? root.accentColor : root.dimColor
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.setSort("name")
                        }
                    }

                    Item {
                        Layout.preferredWidth: 156
                        implicitHeight: scopeRow.implicitHeight

                        RowLayout {
                            id: scopeRow
                            anchors.fill: parent
                            spacing: Theme.spacingXS

                            Item {
                                Layout.preferredWidth: allScope.implicitWidth
                                implicitHeight: allScope.implicitHeight

                                StyledText {
                                    id: allScope
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "ALL"
                                    font.pixelSize: Theme.fontSizeSmall
                                    font.weight: root.processScope === "all" ? Font.Bold : Font.Medium
                                    isMonospace: true
                                    color: root.processScope === "all" ? root.accentColor : root.dimColor
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.processScope = "all"
                                }
                            }

                            StyledText {
                                text: "|"
                                font.pixelSize: Theme.fontSizeSmall
                                isMonospace: true
                                color: root.dimColor
                            }

                            Item {
                                Layout.preferredWidth: userScope.implicitWidth
                                implicitHeight: userScope.implicitHeight

                                StyledText {
                                    id: userScope
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "USER"
                                    font.pixelSize: Theme.fontSizeSmall
                                    font.weight: root.processScope === "user" ? Font.Bold : Font.Medium
                                    isMonospace: true
                                    color: root.ownerScopeAvailable && root.processScope === "user" ? root.accentColor : root.dimColor
                                    opacity: root.ownerScopeAvailable ? 1 : 0.5
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    enabled: root.ownerScopeAvailable
                                    cursorShape: root.ownerScopeAvailable ? Qt.PointingHandCursor : Qt.ArrowCursor
                                    onClicked: root.processScope = "user"
                                }
                            }

                            StyledText {
                                text: "|"
                                font.pixelSize: Theme.fontSizeSmall
                                isMonospace: true
                                color: root.dimColor
                            }

                            Item {
                                Layout.preferredWidth: systemScope.implicitWidth
                                implicitHeight: systemScope.implicitHeight

                                StyledText {
                                    id: systemScope
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "SYSTEM"
                                    font.pixelSize: Theme.fontSizeSmall
                                    font.weight: root.processScope === "system" ? Font.Bold : Font.Medium
                                    isMonospace: true
                                    color: root.ownerScopeAvailable && root.processScope === "system" ? root.accentColor : root.dimColor
                                    opacity: root.ownerScopeAvailable ? 1 : 0.5
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    enabled: root.ownerScopeAvailable
                                    cursorShape: root.ownerScopeAvailable ? Qt.PointingHandCursor : Qt.ArrowCursor
                                    onClicked: root.processScope = "system"
                                }
                            }
                        }
                    }

                    Item {
                        Layout.preferredWidth: 74
                        implicitHeight: idleFilterHeader.implicitHeight

                        StyledText {
                            id: idleFilterHeader
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.right: parent.right
                            horizontalAlignment: Text.AlignRight
                            text: root.hideIdleProcesses ? "IDLE:ON" : "IDLE:OFF"
                            font.pixelSize: Theme.fontSizeSmall
                            font.weight: root.hideIdleProcesses ? Font.Bold : Font.Medium
                            isMonospace: true
                            color: root.hideIdleProcesses ? root.accentColor : root.dimColor
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.hideIdleProcesses = !root.hideIdleProcesses
                        }
                    }

                    Item {
                        visible: root.groupedView
                        Layout.preferredWidth: root.countColWidth
                        implicitHeight: countHeader.implicitHeight

                        StyledText {
                            id: countHeader
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.right: parent.right
                            horizontalAlignment: Text.AlignRight
                            text: root.sortLabel("COUNT", "count")
                            font.pixelSize: Theme.fontSizeSmall
                            font.weight: root.sortBy === "count" ? Font.Bold : Font.Medium
                            isMonospace: true
                            color: root.sortBy === "count" ? root.accentColor : root.dimColor
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.setSort("count")
                        }
                    }

                    Item {
                        visible: root.showCpu
                        Layout.preferredWidth: root.cpuColWidth
                        implicitHeight: cpuHeader.implicitHeight

                        StyledText {
                            id: cpuHeader
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.right: parent.right
                            horizontalAlignment: Text.AlignRight
                            text: root.sortLabel("CPU%", "cpu")
                            font.pixelSize: Theme.fontSizeSmall
                            font.weight: root.sortBy === "cpu" ? Font.Bold : Font.Medium
                            isMonospace: true
                            color: root.sortBy === "cpu" ? root.accentColor : root.dimColor
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.setSort("cpu")
                        }
                    }

                    Item {
                        visible: root.showMemory
                        Layout.preferredWidth: root.memColWidth
                        implicitHeight: memHeader.implicitHeight

                        StyledText {
                            id: memHeader
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.right: parent.right
                            horizontalAlignment: Text.AlignRight
                            text: root.sortLabel("MEM%", "memory")
                            font.pixelSize: Theme.fontSizeSmall
                            font.weight: root.sortBy === "memory" ? Font.Bold : Font.Medium
                            isMonospace: true
                            color: root.sortBy === "memory" ? root.accentColor : root.dimColor
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.setSort("memory")
                        }
                    }

                    Item {
                        visible: root.showPid
                        Layout.preferredWidth: root.pidColWidth
                        implicitHeight: pidHeader.implicitHeight

                        StyledText {
                            id: pidHeader
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.right: parent.right
                            horizontalAlignment: Text.AlignRight
                            text: root.sortLabel("PID", "pid")
                            font.pixelSize: Theme.fontSizeSmall
                            font.weight: root.sortBy === "pid" ? Font.Bold : Font.Medium
                            isMonospace: true
                            color: root.sortBy === "pid" ? root.accentColor : root.dimColor
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.setSort("pid")
                        }
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                height: 1
                color: Theme.withAlpha(Theme.outline, 0.15)
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: Theme.cornerRadius
                color: root.tileBg
                border.width: 0

                Item {
                    anchors.fill: parent
                    anchors.margins: Theme.spacingXS

                    StyledText {
                        anchors.centerIn: parent
                        text: root.lastError ? I18n.tr("Failed to load processes") : I18n.tr("No running processes")
                        color: Theme.surfaceVariantText
                        visible: root.processes.length === 0
                    }

                    DankListView {
                        id: listView
                        anchors.fill: parent
                        visible: root.processes.length > 0
                        spacing: 1
                        clip: true
                        model: ScriptModel {
                            values: root.processes
                            objectProp: "rowId"
                        }

                        delegate: Rectangle {
                            id: rowRoot

                            required property var modelData
                            required property int index

                            width: listView.width
                            height: 30
                            radius: Theme.cornerRadius - 4
                            color: rowArea.containsMouse ? root.rowHoverColor : "transparent"

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: Theme.spacingS
                                anchors.rightMargin: Theme.spacingS
                                spacing: Theme.spacingS

                                StyledText {
                                    Layout.fillWidth: true
                                    text: {
                                        if (rowRoot.modelData.rowType === "group") {
                                            const marker = root.expandedGroups[rowRoot.modelData.command] ? "[-] " : "[+] ";
                                            return marker + (rowRoot.modelData.command || "") + " (" + (rowRoot.modelData.count || 0) + ")";
                                        }
                                        if (rowRoot.modelData.rowType === "child") {
                                            return "  - " + (rowRoot.modelData.command || "");
                                        }
                                        return rowRoot.modelData.command || "";
                                    }
                                    font.pixelSize: Theme.fontSizeSmall
                                    isMonospace: true
                                    color: root.ownerColor(rowRoot.modelData.ownerType)
                                    elide: Text.ElideRight
                                }

                                StyledText {
                                    visible: root.groupedView
                                    Layout.preferredWidth: root.countColWidth
                                    horizontalAlignment: Text.AlignRight
                                    text: rowRoot.modelData.rowType === "group" ? (rowRoot.modelData.count || 0).toString() : ""
                                    font.pixelSize: Theme.fontSizeSmall
                                    isMonospace: true
                                    color: root.dimColor
                                }

                                StyledText {
                                    visible: root.showCpu
                                    Layout.preferredWidth: root.cpuColWidth
                                    horizontalAlignment: Text.AlignRight
                                    text: root.normalizedCpu(rowRoot.modelData.cpu).toFixed(1) + "%"
                                    font.pixelSize: Theme.fontSizeSmall
                                    isMonospace: true
                                    color: rowRoot.modelData.rowType === "group" ? root.textColor : root.dimColor
                                }

                                StyledText {
                                    visible: root.showMemory
                                    Layout.preferredWidth: root.memColWidth
                                    horizontalAlignment: Text.AlignRight
                                    text: (rowRoot.modelData.memoryPercent || 0).toFixed(1) + "%"
                                    font.pixelSize: Theme.fontSizeSmall
                                    isMonospace: true
                                    color: rowRoot.modelData.rowType === "group" ? root.textColor : root.dimColor
                                }

                                StyledText {
                                    visible: root.showPid
                                    Layout.preferredWidth: root.pidColWidth
                                    horizontalAlignment: Text.AlignRight
                                    text: rowRoot.modelData.rowType === "group" ? "-" : (rowRoot.modelData.pid || 0).toString()
                                    font.pixelSize: Theme.fontSizeSmall
                                    isMonospace: true
                                    color: root.dimColor
                                }
                            }

                            MouseArea {
                                id: rowArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: rowRoot.modelData.rowType === "group" ? Qt.PointingHandCursor : Qt.ArrowCursor
                                onClicked: {
                                    if (rowRoot.modelData.rowType === "group") {
                                        root.toggleGroup(rowRoot.modelData.command);
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
