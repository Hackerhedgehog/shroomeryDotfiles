import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import qs.shared
import qs.shared.ui

// Text extractor (OCR), in the middle of the screen. A capture
// (`toggle.sh capture`, SUPER+ALT+A, or "New capture" here) freezes the
// screen, lets you drag a region and reads its text with tesseract
// (shroomery/scripts/ocr.sh); the text is copied to the clipboard and shown
// here, editable, with the OCR language to use next time.
CenterPanel {
    id: root
    ipcTarget: "ocr"
    cardWidth: 720
    cardHeight: 520

    // Installed tesseract language codes, and the one captures use.
    property var languages: []
    property string language: "eng"
    readonly property int languageIndex: languages.indexOf(language)

    property bool capturing: false
    // Reopen the panel when a capture started from it is cancelled.
    property bool reopenOnCancel: false
    property string status: "Ready"
    // StatusChip tone for `status`.
    property string statusTone: "normal"

    readonly property int wordCount: textArea.text.trim() === "" ? 0 : textArea.text.trim().split(/\s+/).length

    // ISO 639-2 codes tesseract uses → names; anything else shows its code.
    readonly property var languageNames: ({
        "eng": "English", "est": "Estonian", "fin": "Finnish", "rus": "Russian",
        "deu": "German", "fra": "French", "spa": "Spanish", "ita": "Italian",
        "por": "Portuguese", "nld": "Dutch", "swe": "Swedish", "nor": "Norwegian",
        "dan": "Danish", "pol": "Polish", "ukr": "Ukrainian", "lav": "Latvian",
        "lit": "Lithuanian", "afr": "Afrikaans", "jpn": "Japanese",
        "chi_sim": "Chinese (simplified)", "chi_tra": "Chinese (traditional)",
        "kor": "Korean"
    })

    function languageName(code) {
        return languageNames[code] ?? code;
    }

    function setLanguage(code) {
        if (!code || code === language)
            return;
        language = code;
        languageFile.setText(code + "\n");
    }

    function setStatus(text, tone) {
        status = text;
        statusTone = tone;
    }

    // Hide the panel first so it is not in the way of the selection.
    function capture() {
        if (capturing)
            return;
        capturing = true;
        reopenOnCancel = isOpen;
        if (isOpen) {
            close();
            captureDelay.restart();
        } else {
            startCapture();
        }
    }

    function startCapture() {
        capture_.exitCode = -1;
        capture_.output = null;
        capture_.running = true;
    }

    // Exit codes are ocr.sh's: 1 cancelled, 2 missing program, 3 OCR failed.
    function finishCapture() {
        capturing = false;
        const code = capture_.exitCode;
        if (code === 1) {
            if (reopenOnCancel) {
                setStatus("Capture cancelled", "normal");
                open();
            }
            return;
        }
        if (code !== 0) {
            if (code === 2)
                setStatus("Missing grim, slurp, magick, tesseract or hyprpicker", "error");
            else if (code === 3)
                setStatus("Couldn't read the selected area", "error");
            else
                setStatus("OCR failed (exit " + code + ")", "error");
            open();
            return;
        }
        const text = (capture_.output || "").trim();
        textArea.text = text;
        if (text === "") {
            setStatus("No text found", "busy");
        } else {
            copy(text);
            setStatus("Copied to clipboard", "good");
        }
        open();
    }

    function copy(text) {
        if (text !== "")
            Quickshell.execDetached(["wl-copy", text]);
    }

    onIsOpenChanged: if (!isOpen && !capturing) setStatus("Ready", "normal")

    IpcHandler {
        target: "ocr-capture"
        function run(): void { root.capture(); }
    }

    // Lets the panel slide out of the way before the screen freezes.
    Timer {
        id: captureDelay
        interval: 400
        onTriggered: root.startCapture()
    }

    // The script's exit and its stdout end arrive in either order.
    Process {
        id: capture_
        property int exitCode: -1
        property var output: null
        command: [Paths.ocr, "--lang", root.language]
        stdout: StdioCollector {
            onStreamFinished: {
                capture_.output = this.text;
                if (capture_.exitCode !== -1)
                    root.finishCapture();
            }
        }
        onExited: code => {
            capture_.exitCode = code;
            if (capture_.output !== null)
                root.finishCapture();
        }
    }

    Process {
        running: true
        command: [Paths.ocr, "--list-langs"]
        stdout: StdioCollector {
            onStreamFinished: root.languages = this.text.split("\n").filter(s => s.length > 0)
        }
    }

    FileView {
        id: languageFile
        path: Paths.ocrLanguageSetting
        watchChanges: true
        printErrors: false
        blockLoading: true
        onLoaded: {
            const code = text().trim();
            if (code !== "")
                root.language = code;
        }
        onFileChanged: reload()
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 20
        spacing: 16

        AppHeader {
            glyph: String.fromCodePoint(0xF113D)   // text-recognition
            title: "Text extractor"
            subtitle: "Select an area of the screen to read its text"

            StatusChip {
                text: root.status
                tone: root.statusTone
            }
        }

        Card {
            Layout.fillWidth: true
            Layout.fillHeight: true
            border.color: textArea.activeFocus ? Theme.primary : Theme.outline_variant

            ScrollView {
                id: scroll
                anchors.fill: parent
                anchors.margins: 1
                anchors.bottomMargin: 30
                clip: true
                ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

                TextArea {
                    id: textArea
                    wrapMode: TextEdit.Wrap
                    selectByMouse: true
                    color: Theme.on_surface
                    selectionColor: Theme.primary
                    selectedTextColor: Theme.on_primary
                    font.family: Theme.fontFamily
                    font.pixelSize: 14
                    padding: 16
                    background: Item {}
                }
            }

            // Empty state.
            ColumnLayout {
                anchors.centerIn: parent
                width: Math.min(parent.width - 80, 420)
                spacing: 10
                visible: textArea.text === "" && !textArea.activeFocus

                Rectangle {
                    Layout.alignment: Qt.AlignHCenter
                    implicitWidth: 72
                    implicitHeight: 72
                    radius: 36
                    color: Theme.surface_container_high
                    Text {
                        anchors.centerIn: parent
                        text: String.fromCodePoint(0xF0A6D)   // selection-drag
                        color: Theme.primary
                        font.family: Theme.iconFontFamily
                        font.pixelSize: 34
                    }
                }
                Text {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    text: "No text yet"
                    color: Theme.on_surface
                    font.family: Theme.fontFamily
                    font.pixelSize: 16
                    font.bold: true
                }
                Text {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    text: "Press New capture (or SUPER + ALT + A) and drag over the text you want. It is copied to the clipboard and shown here to edit."
                    color: Theme.on_surface_variant
                    font.family: Theme.fontFamily
                    font.pixelSize: 12
                    wrapMode: Text.Wrap
                }
            }

            // Click anywhere on the empty card to type.
            MouseArea {
                anchors.fill: parent
                visible: textArea.text === "" && !textArea.activeFocus
                cursorShape: Qt.IBeamCursor
                onClicked: textArea.forceActiveFocus()
            }

            Text {
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.margins: 12
                visible: textArea.text !== ""
                text: root.wordCount + (root.wordCount === 1 ? " word · " : " words · ")
                    + textArea.length + (textArea.length === 1 ? " character" : " characters")
                color: Theme.on_surface_variant
                font.family: Theme.fontFamily
                font.pixelSize: 11
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            Text {
                text: String.fromCodePoint(0xF05CA)   // translate
                color: Theme.on_surface_variant
                font.family: Theme.iconFontFamily
                font.pixelSize: 18
            }

            FieldCombo {
                Layout.preferredWidth: 200
                enabled: root.languages.length > 1
                model: root.languages.map(code => root.languageName(code))
                boundIndex: Math.max(0, root.languageIndex)
                onActivated: index => root.setLanguage(root.languages[index])
                ToolTip.visible: hovered && !enabled
                ToolTip.delay: 500
                ToolTip.text: "Install more tesseract-data-* packages for other languages"
            }

            Item { Layout.fillWidth: true }

            PanelButton {
                text: "Clear"
                glyph: String.fromCodePoint(0xF09E7)   // delete-outline
                visible: textArea.text !== ""
                onClicked: {
                    textArea.text = "";
                    root.setStatus("Ready", "normal");
                }
            }

            PanelButton {
                text: "New capture"
                glyph: String.fromCodePoint(0xF0A6D)   // selection-drag
                tonal: true
                enabled: !root.capturing
                onClicked: root.capture()
            }

            PanelButton {
                text: "Copy"
                glyph: String.fromCodePoint(0xF018F)   // content-copy
                filled: true
                enabled: textArea.text !== ""
                onClicked: {
                    root.copy(textArea.text);
                    root.setStatus("Copied to clipboard", "good");
                }
            }
        }
    }
}
