import Cocoa
import Foundation
import ApplicationServices

// List windows as JSON with coordinates and sizes
func listWindows() {
    let options = CGWindowListOption(arrayLiteral: .optionOnScreenOnly)
    guard let windowList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as NSArray? else {
        print("Failed to retrieve window list")
        return
    }

    var windowsArray: [[String: Any]] = []

    for window in windowList {
        guard let windowInfo = window as? [String: Any],
              let windowID = windowInfo[kCGWindowNumber as String] as? Int,
              let windowLayer = windowInfo[kCGWindowLayer as String] as? Int,
              let ownerName = windowInfo[kCGWindowOwnerName as String] as? String,
              let isOnScreen = windowInfo[kCGWindowIsOnscreen as String] as? Bool,
              windowLayer == 0,
              isOnScreen,
              let bounds = windowInfo[kCGWindowBounds as String] as? [String: Any],
              let x = bounds["X"] as? Int,
              let y = bounds["Y"] as? Int,
              let width = bounds["Width"] as? Int,
              let height = bounds["Height"] as? Int
        else { continue }

        let windowName = windowInfo[kCGWindowName as String] as? String ?? "Untitled"

        let windowData: [String: Any] = [
            "id": windowID,
            "owner": ownerName,
            "title": windowName,
            "x": x,
            "y": y,
            "width": width,
            "height": height
        ]
        windowsArray.append(windowData)
    }

    do {
        let jsonData = try JSONSerialization.data(withJSONObject: windowsArray, options: .prettyPrinted)
        if let jsonString = String(data: jsonData, encoding: .utf8) {
            print(jsonString)
        } else {
            print("Failed to convert JSON data to string")
        }
    } catch {
        print("Failed to serialize windows to JSON: \(error)")
    }
}

// Set window position and size
func setWindowPosition(windowID: Int, x: Int, y: Int, width: Int, height: Int) {
    let options = CGWindowListOption(arrayLiteral: .optionOnScreenOnly)
    guard let windowList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as NSArray? else {
        print("Failed to retrieve window list")
        return
    }

    for window in windowList {
        guard let windowInfo = window as? [String: Any],
              let currentWindowID = windowInfo[kCGWindowNumber as String] as? Int,
              currentWindowID == windowID else { continue }

        guard let pid = windowInfo[kCGWindowOwnerPID as String] as? pid_t else {
            print("Could not get PID for window \(windowID)")
            return
        }
        let ownerName = windowInfo[kCGWindowOwnerName as String] as? String ?? "Unknown"
        print("Found window \(windowID) owned by \(ownerName) with PID \(pid)")

        let appElement = AXUIElementCreateApplication(pid)
        var windows: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windows)
        if error != .success || windows == nil {
            print("Failed to access windows for PID \(pid): AXError \(error.rawValue)")
            return
        }

        let axWindows = windows as! NSArray
        if axWindows.count == 0 {
            print("No Accessibility windows found for \(ownerName) (PID \(pid))")
            return
        }

        for axWindow in axWindows {
            var position = CGPoint(x: x, y: y)
            let positionValue = AXValueCreate(.cgPoint, &position)!
            let posError = AXUIElementSetAttributeValue(axWindow as! AXUIElement, kAXPositionAttribute as CFString, positionValue)

            var size = CGSize(width: width, height: height)
            let sizeValue = AXValueCreate(.cgSize, &size)!
            let sizeError = AXUIElementSetAttributeValue(axWindow as! AXUIElement, kAXSizeAttribute as CFString, sizeValue)

            if posError == .success && sizeError == .success {
                print("Window \(windowID) moved to (\(x), \(y)) with size (\(width), \(height))")
                return
            } else {
                print("Failed to set window attributes - Position AXError: \(posError.rawValue), Size AXError: \(sizeError.rawValue)")
            }
        }
        print("Could not manipulate window \(windowID) in \(ownerName)'s Accessibility window list")
        return
    }
    print("Window with ID \(windowID) not found in CGWindowList")
}

// Focus a window by ID
func focusWindow(windowID: Int) {
    let options = CGWindowListOption(arrayLiteral: .optionOnScreenOnly)
    guard let windowList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as NSArray? else {
        print("Failed to retrieve window list")
        return
    }

    for window in windowList {
        guard let windowInfo = window as? [String: Any],
              let currentWindowID = windowInfo[kCGWindowNumber as String] as? Int,
              currentWindowID == windowID else { continue }

        guard let pid = windowInfo[kCGWindowOwnerPID as String] as? pid_t else {
            print("Could not get PID for window \(windowID)")
            return
        }
        let ownerName = windowInfo[kCGWindowOwnerName as String] as? String ?? "Unknown"
        print("Found window \(windowID) owned by \(ownerName) with PID \(pid)")

        // Create an Accessibility element for the application
        let appElement = AXUIElementCreateApplication(pid)

        // Get the windows of the application
        var windows: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windows)
        if error != .success || windows == nil {
            print("Failed to access windows for PID \(pid): AXError \(error.rawValue)")
            return
        }

        let axWindows = windows as! NSArray
        if axWindows.count == 0 {
            print("No Accessibility windows found for \(ownerName) (PID \(pid))")
            return
        }

        // Try focusing each window
        for axWindow in axWindows {
            // Set the window as the main window (brings it to focus)
            let focusError = AXUIElementSetAttributeValue(axWindow as! AXUIElement, kAXMainAttribute as CFString, kCFBooleanTrue)

            // Raise the window to ensure it’s in front
            let raiseError = AXUIElementPerformAction(axWindow as! AXUIElement, kAXRaiseAction as CFString)

            if focusError == .success && raiseError == .success {
                // Activate the application to ensure it takes focus (updated for macOS 14+)
                if let app = NSRunningApplication(processIdentifier: pid) {
                    app.activate() // No options needed in macOS 14+
                }
                print("Window \(windowID) focused")
                return
            } else {
                print("Failed to focus window - Focus AXError: \(focusError.rawValue), Raise AXError: \(raiseError.rawValue)")
            }
        }
        print("Could not focus window \(windowID) in \(ownerName)'s Accessibility window list")
        return
    }
    print("Window with ID \(windowID) not found in CGWindowList")
}

// Main command-line parsing
func main() {
    let arguments = CommandLine.arguments

    guard arguments.count > 1 else {
        print("""
        Usage:
            \(arguments[0]) list
            \(arguments[0]) set <windowID> <x> <y> <width> <height>
            \(arguments[0]) focus <windowID>
        """)
        exit(1)
    }

    let command = arguments[1]

    switch command {
    case "list":
        listWindows()

    case "set":
        guard arguments.count == 7,
              let windowID = Int(arguments[2]),
              let x = Int(arguments[3]),
              let y = Int(arguments[4]),
              let width = Int(arguments[5]),
              let height = Int(arguments[6]) else {
            print("Usage: \(arguments[0]) set <windowID> <x> <y> <width> <height>")
            exit(1)
        }
        setWindowPosition(windowID: windowID, x: x, y: y, width: width, height: height)

    case "focus":
        guard arguments.count == 3,
              let windowID = Int(arguments[2]) else {
            print("Usage: \(arguments[0]) focus <windowID>")
            exit(1)
        }
        focusWindow(windowID: windowID)

    default:
        print("Unknown command: \(command)")
        print("""
        Usage:
            \(arguments[0]) list
            \(arguments[0]) set <windowID> <x> <y> <width> <height>
            \(arguments[0]) focus <windowID>
        """)
        exit(1)
    }
}

// Run the program
main()