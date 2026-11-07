import Foundation

/// SSAP URIs used by Luma Remote. Cross-checked against Home Assistant's aiowebostv
/// (`endpoints.py`) and lgtv2. Whether each one exists on a given TV is detected at
/// runtime (see `CapabilityStore`) — nothing here is assumed to be supported.
nonisolated enum SSAPEndpoint: String, Sendable, CaseIterable {
    // Discovery of what the TV offers
    case serviceList = "api/getServiceList"
    case systemInfo = "system/getSystemInfo"
    case softwareInfo = "com.webos.service.update/getCurrentSWInformation"
    case connectionInfo = "com.webos.service.connectionmanager/getinfo"

    // Power
    case turnOff = "system/turnOff"
    case powerState = "com.webos.service.tvpower/power/getPowerState"
    case screenOff = "com.webos.service.tvpower/power/turnOffScreen"
    case screenOn = "com.webos.service.tvpower/power/turnOnScreen"

    // Audio
    case audioStatus = "audio/getStatus"
    case volumeUp = "audio/volumeUp"
    case volumeDown = "audio/volumeDown"
    case setMute = "audio/setMute"
    case setVolume = "audio/setVolume"

    // TV tuner
    case channelUp = "tv/channelUp"
    case channelDown = "tv/channelDown"
    case currentChannel = "tv/getCurrentChannel"

    // Inputs
    case externalInputs = "tv/getExternalInputList"
    case switchInput = "tv/switchInput"

    // Apps
    case launchPoints = "com.webos.applicationManager/listLaunchPoints"
    case foregroundApp = "com.webos.applicationManager/getForegroundAppInfo"
    case launch = "system.launcher/launch"

    // Media
    case play = "media.controls/play"
    case pause = "media.controls/pause"
    case stop = "media.controls/stop"
    case rewind = "media.controls/rewind"
    case fastForward = "media.controls/fastForward"

    // Text input
    case insertText = "com.webos.service.ime/insertText"
    case deleteCharacters = "com.webos.service.ime/deleteCharacters"
    case sendEnter = "com.webos.service.ime/sendEnterKey"
    case remoteKeyboard = "com.webos.service.ime/registerRemoteKeyboard"

    // Button / pointer input (returns a URL for a second WebSocket)
    case pointerInputSocket = "com.webos.service.networkinput/getPointerInputSocket"

    // Notifications
    case toast = "system.notifications/createToast"

    var uri: String { "ssap://\(rawValue)" }

    /// Service prefix as listed by `api/getServiceList` (e.g. "audio", "tv").
    var serviceName: String {
        rawValue.components(separatedBy: "/").first ?? rawValue
    }
}
