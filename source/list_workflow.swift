#!/usr/bin/swift

import Foundation

// MARK: - Helpers

extension FileManager {
    func isDirectory(atPath path: String) -> Bool {
        var isDir: ObjCBool = false
        let exists = fileExists(atPath: path, isDirectory: &isDir)
        return exists && isDir.boolValue
    }
}

struct Environment {
    static let env = ProcessInfo.processInfo.environment
    static let alfredPreferences = env["alfred_preferences"]!
    static let workflowCacheFolder = env["alfred_workflow_cache"]!
    static let workflowDataFolder = env["alfred_workflow_data"]!
    static let alfredVersion = env["alfred_version"]!
    static let alfredVersionBuild = env["alfred_version_build"]!
    static let onlyShowEnabled = (env["only_show_enabled"] ?? "0") == "1"
}

func getMacOSVersion() -> String {
    let os = ProcessInfo.processInfo.operatingSystemVersion
    return "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)"
}

// MARK: - Main

let fileManager = FileManager.default
let workflowsDir = URL(fileURLWithPath: Environment.alfredPreferences).appendingPathComponent("workflows")

// Get list of workflow directories (those that contain an info.plist)
guard let workflowDirs = try? fileManager.contentsOfDirectory(at: workflowsDir,
                                                                includingPropertiesForKeys: nil,
                                                                options: .skipsHiddenFiles)
else {
    print("{\"cache\": {\"seconds\": 7200}, \"items\": []}")
    exit(0)
}

var enabledItems = [[String: Any]]()
var disabledItems = [[String: Any]]()

for workflowDir in workflowDirs {
    let plistPath = workflowDir.appendingPathComponent("info.plist")
    guard fileManager.fileExists(atPath: plistPath.path) else { continue }
    
    // Read the plist as a dictionary via PropertyListSerialization
    guard let plistData = try? Data(contentsOf: plistPath),
          let plistObj = try? PropertyListSerialization.propertyList(from: plistData, options: [], format: nil),
          let plist = plistObj as? [String: Any]
    else { continue }
    
    // Determine if workflow is enabled.
    // (Ruby: enabled = (plist['disabled'] == false))
    let enabled = (plist["disabled"] as? Bool) == false
    
    // If only-show-enabled is set, skip disabled workflows.
    if Environment.onlyShowEnabled && !enabled {
        continue
    }
    
    // Extract basic workflow information.
    let name = plist["name"] as? String ?? "Unknown"
    let desc = plist["description"] as? String ?? ""
    let versionRaw = plist["version"] as? String ?? ""
    let version = versionRaw.isEmpty ? "" : "v\(versionRaw)"
    let bundleid = plist["bundleid"] as? String ?? ""
    let createdbyRaw = plist["createdby"] as? String ?? ""
    let createdby = createdbyRaw.isEmpty ? "" : "by \(createdbyRaw)"
    
    // Build subtitle (combine creator and description, or fallback).
    var subtitleParts = [String]()
    if !createdby.isEmpty { subtitleParts.append(createdby) }
    if !desc.isEmpty { subtitleParts.append(desc) }
    let subtitle = subtitleParts.isEmpty ? "No author or Description" : subtitleParts.joined(separator: "・")
    
    // Build title – add a warning symbol if disabled, and include version if available.
    var titleParts = [String]()
    if enabled {
        titleParts.append(name)
    } else {
        titleParts.append("🚫 \(name)")
    }
    if !version.isEmpty { titleParts.append(version) }
    let title = titleParts.joined(separator: "・")
    
    // Determine workflow folder path and folder name.
    let workflowFolderPath = workflowDir.path
    let folderName = workflowDir.lastPathComponent
    
    // --- Build the secondary menu (shown via the alt modifier) ---
    var secondaryMenuItems = [[String: Any]]()
    
    // 1. Open Configuration
    secondaryMenuItems.append([
        "title": "Open Configuration",
        "subtitle": "Open configuration of ‘\(name)’ in Alfred Preferences.",
        "variables": ["chosen_action": "Open Configuration"],
        "icon": ["path": "icons/Alfred Preferences.png"]
    ])
    
    // 2. Copy Bundle Id
    if bundleid.isEmpty {
        secondaryMenuItems.append([
            "title": "Copy Bundle Id",
            "subtitle": "No Bundle Id",
            "valid": false,
            "icon": ["path": "icons/copy.png"]
        ])
    } else {
        secondaryMenuItems.append([
            "title": "Copy Bundle Id",
            "subtitle": "Copy Bundle Id for ‘\(name)’: \(bundleid)",
            "arg": bundleid,
            "variables": ["chosen_action": "Copy Bundle Id"],
            "icon": ["path": "icons/copy.png"]
        ])
    }
    
    // 3. Copy workflow info (includes macOS and Alfred version)
    let macVersion = getMacOSVersion()
    let infoArg = "\(name)・\(version.isEmpty ? "version empty" : version), bundle ID: \(bundleid.isEmpty ? "no bundle Id" : bundleid) . Alfred version: \(Environment.alfredVersion) \(Environment.alfredVersionBuild). macOS: \(macVersion)."
    secondaryMenuItems.append([
        "title": "Copy Information for Workflow",
        "subtitle": "Copy workflow info for ‘\(name)’. Name, version, bundle Id, macOS and Alfred version included.",
        "arg": infoArg,
        "variables": ["chosen_action": "Copy Information for Workflow"],
        "icon": ["path": "icons/copy.png"]
    ])
    
    // 4. Show Workflow Folder
    secondaryMenuItems.append([
        "title": "Show Workflow Folder",
        "subtitle": "Show workflow folder of ‘\(name)’ in Finder",
        "arg": workflowFolderPath,
        "variables": ["chosen_action": "Show Workflow Folder"],
        "icon": ["path": "icons/finder.png"]
    ])
    
    // 5. Data Folder – use the directory part of alfred_workflow_data
    let workflowDataFolder = URL(fileURLWithPath: Environment.workflowDataFolder)
        .deletingLastPathComponent()
        .appendingPathComponent(bundleid).path
    var dataFolderMod: [String: Any] = [:]
    if !bundleid.isEmpty && fileManager.isDirectory(atPath: workflowDataFolder) {
        dataFolderMod = ["subtitle": "Data folder", "arg": workflowDataFolder]
        secondaryMenuItems.append([
            "title": "Show Data Folder",
            "subtitle": "Show data folder of ‘\(name)’ in Finder",
            "arg": workflowDataFolder,
            "variables": ["chosen_action": "Show Data Folder"],
            "icon": ["path": "icons/finder.png"]
        ])
    } else {
        dataFolderMod = ["subtitle": "No data folder found", "valid": false]
        secondaryMenuItems.append([
            "title": "No Data folder Found",
            "subtitle": "No data folder found for workflow ‘\(name)’.",
            "valid": false,
            "icon": ["path": "icons/Empty.png"]
        ])
    }
    
    // 6. Cache Folder – use the directory part of alfred_workflow_cache
    let workflowCacheFolder = URL(fileURLWithPath: Environment.workflowCacheFolder)
        .deletingLastPathComponent()
        .appendingPathComponent(bundleid).path
    var cacheFolderMod: [String: Any] = [:]
    if !bundleid.isEmpty && fileManager.isDirectory(atPath: workflowCacheFolder) {
        cacheFolderMod = ["subtitle": "Cache folder", "arg": workflowCacheFolder]
        secondaryMenuItems.append([
            "title": "Show Cache Folder",
            "subtitle": "Show cache folder of ‘\(name)’ in Finder",
            "arg": workflowCacheFolder,
            "variables": ["chosen_action": "Show Cache Folder"],
            "icon": ["path": "icons/finder.png"]
        ])
    } else {
        cacheFolderMod = ["subtitle": "No cache folder found", "valid": false]
        secondaryMenuItems.append([
            "title": "No cache folder Found",
            "subtitle": "No cache folder found for workflow ‘\(name)’.",
            "valid": false,
            "icon": ["path": "icons/Empty.png"]
        ])
    }
    
    // 7. Trash Workflow
    secondaryMenuItems.append([
        "title": "Trash Workflow",
        "subtitle": "Trash workflow ‘\(name)’. Can be undone from the Trash.",
        "arg": workflowFolderPath,
        "variables": ["chosen_action": "Trash Workflow"],
        "icon": ["path": "icons/trash.png"]
    ])
    
    // 8. Export Workflow
    secondaryMenuItems.append([
        "title": "Export Workflow",
        "subtitle": "Export as ‘\(name).alfredworkflow’ to your Desktop",
        "arg": workflowFolderPath,
        "variables": ["chosen_action": "Export Workflow"],
        "icon": ["path": "icons/alfred_workflow.png"]
    ])
    
    // Build the secondary menu JSON (to be passed via the alt modifier)
    let secondaryMenuJson: [String: Any] = ["items": secondaryMenuItems]
    let secondaryMenuJsonData = try? JSONSerialization.data(withJSONObject: secondaryMenuJson, options: [])
    let secondaryMenuJsonString = secondaryMenuJsonData.flatMap { String(data: $0, encoding: .utf8) } ?? ""
    
    // --- Build the main modifiers dictionary ---
    var mods = [String: [String: Any]]()
    mods["cmd"] = ["subtitle": "Open configuration"]
    if bundleid.isEmpty {
        mods["shift+cmd"] = ["subtitle": "No Bundle Id", "valid": false]
    } else {
        mods["shift+cmd"] = ["subtitle": "Copy Bundle Id: \(bundleid)", "arg": bundleid]
    }
    mods["shift+cmd+alt"] = ["subtitle": "Copy workflow info", "arg": infoArg]
    mods["shift"] = ["subtitle": "Workflow folder", "arg": workflowFolderPath]
    mods["ctrl"] = dataFolderMod
    mods["alt+ctrl"] = cacheFolderMod
    mods["shift+ctrl"] = ["subtitle": "Trash workflow", "arg": workflowFolderPath]
    mods["alt"] = ["subtitle": "Show All Actions",
                   "variables": ["script_filter_res": secondaryMenuJsonString],
                   "arg": ""]
    
    // Determine the main icon (use icon.png if it exists, otherwise fallback)
    let iconPathCandidate = workflowDir.appendingPathComponent("icon.png").path
    let mainIconPath = fileManager.fileExists(atPath: iconPathCandidate) ? iconPathCandidate : "icons/Empty.png"
    let iconDict = ["path": mainIconPath]
    
    // Build the main item
    let item: [String: Any] = [
        "title": title,
        "subtitle": subtitle.isEmpty ? "No description or version" : subtitle,
        "mods": mods,
        "action": [String: Any](),  // empty action object
        "arg": folderName,
        "icon": iconDict,
        "uid": title,
        "match": "\(desc) \(createdby) \(name)"
    ]
    
    if enabled {
        enabledItems.append(item)
    } else {
        disabledItems.append(item)
    }
}

// Concatenate enabled and disabled items (keeping their order)
let allItems = enabledItems + disabledItems

// Output the final JSON with a cache timeout of 7200 seconds.
let output: [String: Any] = [
    "items": allItems
]

if let jsonData = try? JSONSerialization.data(withJSONObject: output, options: []),
   let jsonString = String(data: jsonData, encoding: .utf8) {
    print(jsonString)
} else {
    print("{\"items\": []}")
}
