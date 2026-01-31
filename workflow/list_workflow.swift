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
    static let excludedCategories = (env["excluded_categories"] ?? "")
    .components(separatedBy: .newlines)
    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    .filter { !$0.isEmpty }
    static let showKeywords = (env["description_or_keywords_to_show_in_subtitle"] ?? "Description") == "Keywords"
}

func getMacOSVersion() -> String {
    let os = ProcessInfo.processInfo.operatingSystemVersion
    return "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)"
}

struct WorkflowHistory: Codable {
    struct Preferences: Codable {
        let workflows: [String]
    }
    let preferences: Preferences
}

// MARK: - Keyword Extraction

func resolveVariableKeyword(_ keyword: String, workflowDir: URL, userConfig: [[String: Any]]?) -> String {
    // Find all {var:varname} patterns using regex
    let pattern = #"\{var:([^}]+)\}"#
    guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
        return keyword
    }
    
    var resolvedKeyword = keyword
    let nsString = keyword as NSString
    let matches = regex.matches(in: keyword, options: [], range: NSRange(location: 0, length: nsString.length))
    
    // Load prefs.plist if it exists
    let prefsPath = workflowDir.appendingPathComponent("prefs.plist")
    var prefsDict: [String: Any]? = nil
    if FileManager.default.fileExists(atPath: prefsPath.path),
       let prefsData = try? Data(contentsOf: prefsPath),
       let prefsObj = try? PropertyListSerialization.propertyList(from: prefsData, options: [], format: nil) {
        prefsDict = prefsObj as? [String: Any]
    }
    
    // Process matches in reverse order to maintain string indices
    for match in matches.reversed() {
        let fullMatchRange = match.range(at: 0)
        let variableNameRange = match.range(at: 1)
        
        let fullMatch = nsString.substring(with: fullMatchRange)
        let variableName = nsString.substring(with: variableNameRange)
        
        var resolvedValue: String? = nil
        
        // First try to get value from prefs.plist
        if let prefs = prefsDict {
            resolvedValue = prefs[variableName] as? String
        }
        
        // If not found in prefs, try user config defaults
        if resolvedValue == nil, let userConfig = userConfig {
            for configItem in userConfig {
                if let variable = configItem["variable"] as? String,
                   variable.lowercased() == variableName.lowercased(),
                   let config = configItem["config"] as? [String: Any],
                   let defaultValue = config["default"] as? String {
                    resolvedValue = defaultValue
                    break
                }
            }
        }
        
        // Replace the pattern with resolved value
        if let resolved = resolvedValue {
            resolvedKeyword = (resolvedKeyword as NSString).replacingCharacters(in: fullMatchRange, with: resolved)
        }
    }
    
    return resolvedKeyword
}

func extractKeywords(from plist: [String: Any], workflowDir: URL) -> [String] {
    guard let objects = plist["objects"] as? [[String: Any]] else { return [] }
    
    let inputTypes = [
        "alfred.workflow.input.scriptfilter",
        "alfred.workflow.input.keyword",
        "alfred.workflow.input.listfilter",
        "alfred.workflow.input.filefilter"
    ]
    
    let userConfig = plist["userconfigurationconfig"] as? [[String: Any]]
    var keywords = [String]()
    
    for obj in objects {
        guard let type = obj["type"] as? String,
              inputTypes.contains(type),
              let config = obj["config"] as? [String: Any],
              let keyword = config["keyword"] as? String,
              !keyword.isEmpty else { continue }
        
        // Resolve any {var:} patterns in the keyword
        var finalKeyword = resolveVariableKeyword(keyword, workflowDir: workflowDir, userConfig: userConfig)
        
        // Strip all whitespace from the keyword
        let strippedKeyword = finalKeyword.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if !strippedKeyword.isEmpty {
            keywords.append(strippedKeyword)
        }
    }
    
    return keywords
}

// MARK: - Main

let fileManager = FileManager.default
let workflowsDir = URL(fileURLWithPath: Environment.alfredPreferences).appendingPathComponent("workflows")

// Get list of workflow directories (those that contain an info.plist)
guard let workflowDirs = try? fileManager.contentsOfDirectory(at: workflowsDir,
                                                                includingPropertiesForKeys: nil,
                                                                options: .skipsHiddenFiles)
else {
    print("{\"items\": [{\"title\": \"Error\", \"subtitle\": \"Could not read workflows directory.\"}]}")
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

    let categoryRaw = plist["category"] as? String ?? ""
    // If the workflow is in an excluded category, skip it.
    if Environment.excludedCategories.contains(categoryRaw) {
        continue
    }
    
    // Extract other basic workflow information.
    let name = plist["name"] as? String ?? "Unknown"
    let desc = plist["description"] as? String ?? ""
    let category = categoryRaw.isEmpty ? "" : "🧷\(categoryRaw)"
    let versionRaw = plist["version"] as? String ?? ""
    let version = versionRaw.isEmpty ? "" : "v\(versionRaw)"
    let bundleid = plist["bundleid"] as? String ?? ""
    let createdbyRaw = plist["createdby"] as? String ?? ""
    let createdby = createdbyRaw.isEmpty ? "" : "by 👤\(createdbyRaw)"
    
    // Extract keywords for use in subtitle and match
    let keywords = extractKeywords(from: plist, workflowDir: workflowDir)
    let keywordsCommaSeparated = keywords.joined(separator: ", ")
    
    // Build subtitle (combine creator, category, and description/keywords).
    var subtitleParts = [String]()
    if !createdby.isEmpty { subtitleParts.append(createdby) }
    if !category.isEmpty { subtitleParts.append(category) }
    
    // Add either keywords or description based on user configuration
    if Environment.showKeywords {
        if !keywords.isEmpty {
            let keywordsString = "🔑Keywords: " + keywordsCommaSeparated
            subtitleParts.append(keywordsString)
        }
    } else {
        if !desc.isEmpty { subtitleParts.append(desc) }
    }
    
    let fallbackMessage = Environment.showKeywords ? "No author, category or keywords" : "No author, category or description"
    let subtitle = subtitleParts.isEmpty ? fallbackMessage : subtitleParts.joined(separator: "・")
    
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

    // 1. Edit Workflow in Alfred
    secondaryMenuItems.append([
        "title": "Edit Workflow in Alfred",
        "subtitle": "Edit ‘\(name)’ workflow in Alfred Preferences.",
        "variables": ["chosen_action": "Edit Workflow in Alfred"],
        "icon": ["path": "icons/Alfred Preferences.png"],
        "arg": folderName
    ])

    // 2. Open Configuration
    secondaryMenuItems.append([
        "title": "Open Configuration",
        "subtitle": "Open configuration of ‘\(name)’ in Alfred Preferences.",
        "variables": ["chosen_action": "Open Configuration"],
        "icon": ["path": "icons/Alfred Preferences.png"],
        "arg": folderName
    ])
    
    // 3. Copy Bundle Id
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

    // 4. Copy Workflow Name
    secondaryMenuItems.append([
        "title": "Copy Workflow Name",
        "subtitle": "Copy workflow name ‘\(name)’",
        "arg": name,
        "variables": ["chosen_action": "Copy Workflow Name"],
        "icon": ["path": "icons/copy.png"]
    ])
    
    // 5. Copy Workflow Information (includes macOS and Alfred version)
    let macVersion = getMacOSVersion()
    let infoArg = "\(name)・\(version.isEmpty ? "version empty" : version), bundle ID: \(bundleid.isEmpty ? "no bundle Id" : bundleid) . Alfred version: \(Environment.alfredVersion) \(Environment.alfredVersionBuild). macOS: \(macVersion)."
    secondaryMenuItems.append([
        "title": "Copy Workflow Information",
        "subtitle": "Copy workflow info for ‘\(name)’. Name, version, bundle Id, macOS and Alfred version included.",
        "arg": infoArg,
        "variables": ["chosen_action": "Copy Workflow Information"],
        "icon": ["path": "icons/copy.png"]
    ])
    
    // 6. Show Workflow Folder
    secondaryMenuItems.append([
        "title": "Show Workflow Folder",
        "subtitle": "Show workflow folder of ‘\(name)’ in Finder",
        "arg": workflowFolderPath,
        "variables": ["chosen_action": "Show Workflow Folder"],
        "icon": ["path": "icons/finder.png"]
    ])
    
    // 7. Show Data Folder – use the directory part of alfred_workflow_data
    let workflowDataFolder = URL(fileURLWithPath: Environment.workflowDataFolder)
        .deletingLastPathComponent()
        .appendingPathComponent(bundleid).path
    var dataFolderMod: [String: Any] = [:]
    if !bundleid.isEmpty && fileManager.isDirectory(atPath: workflowDataFolder) {
        dataFolderMod = ["subtitle": "Data folder", "arg": workflowDataFolder, "icon": ["path": "icons/finder.png"]]
        secondaryMenuItems.append([
            "title": "Show Data Folder",
            "subtitle": "Show data folder of ‘\(name)’ in Finder",
            "arg": workflowDataFolder,
            "variables": ["chosen_action": "Show Data Folder"],
            "icon": ["path": "icons/finder.png"]
        ])
    } else {
        dataFolderMod = ["subtitle": "No data folder found", "valid": false, "icon": ["path": "icons/Empty.png"]]
        secondaryMenuItems.append([
            "title": "No Data folder Found",
            "subtitle": "No data folder found for workflow ‘\(name)’.",
            "valid": false,
            "icon": ["path": "icons/Empty.png"]
        ])
    }
    
    // 8. Show Cache Folder – use the directory part of alfred_workflow_cache
    let workflowCacheFolder = URL(fileURLWithPath: Environment.workflowCacheFolder)
        .deletingLastPathComponent()
        .appendingPathComponent(bundleid).path
    var cacheFolderMod: [String: Any] = [:]
    if !bundleid.isEmpty && fileManager.isDirectory(atPath: workflowCacheFolder) {
        cacheFolderMod = ["subtitle": "Cache folder", "arg": workflowCacheFolder, "icon": ["path": "icons/finder.png"]]
        secondaryMenuItems.append([
            "title": "Show Cache Folder",
            "subtitle": "Show cache folder of ‘\(name)’ in Finder",
            "arg": workflowCacheFolder,
            "variables": ["chosen_action": "Show Cache Folder"],
            "icon": ["path": "icons/finder.png"]
        ])
    } else {
        cacheFolderMod = ["subtitle": "No cache folder found", "valid": false, "icon": ["path": "icons/Empty.png"]]
        secondaryMenuItems.append([
            "title": "No cache folder Found",
            "subtitle": "No cache folder found for workflow ‘\(name)’.",
            "valid": false,
            "icon": ["path": "icons/Empty.png"]
        ])
    }
    
    // 9. Trash Workflow
    secondaryMenuItems.append([
        "title": "Trash Workflow",
        "subtitle": "Trash workflow ‘\(name)’. Can be undone from the Trash.",
        "arg": workflowFolderPath,
        "variables": ["chosen_action": "Trash Workflow"],
        "icon": ["path": "icons/trash.png"]
    ])
    
    // 10. Export Workflow
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
    mods["cmd"] = ["subtitle": "Open configuration", "icon": ["path": "icons/Alfred Preferences.png"]]
    if bundleid.isEmpty {
        mods["shift+cmd"] = ["subtitle": "No Bundle Id", "valid": false, "icon": ["path": "icons/copy.png"]]
    } else {
        mods["shift+cmd"] = ["subtitle": "Copy Bundle Id: \(bundleid)", "arg": bundleid, "icon": ["path": "icons/copy.png"]]
    }
    mods["shift+cmd+alt"] = ["subtitle": "Copy workflow info", "arg": infoArg, "icon": ["path": "icons/copy.png"]]
    mods["shift"] = ["subtitle": "Workflow folder", "arg": workflowFolderPath, "icon": ["path": "icons/finder.png"]]
    mods["ctrl"] = dataFolderMod
    mods["alt+ctrl"] = cacheFolderMod
    mods["shift+ctrl"] = ["subtitle": "Trash workflow", "arg": workflowFolderPath, "icon": ["path": "icons/trash.png"]]
    mods["alt"] = ["subtitle": "Show All Actions",
                   "variables": ["script_filter_res": secondaryMenuJsonString],
                   "arg": "",
                   "icon": ["path": "icons/actions.png"]]
    
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
        "match": Environment.showKeywords ? "\(keywordsCommaSeparated) \(createdby) \(name)" : "\(desc) \(createdby) \(name)"
    ]
    
    if enabled {
        enabledItems.append(item)
    } else {
        disabledItems.append(item)
    }
}

// Concatenate enabled and disabled items (keeping their order)
var allItems = enabledItems + disabledItems

// Prioritize recently edited workflows
let historyFile = URL(fileURLWithPath: ("~/Library/Application Support/Alfred/history.json" as NSString).expandingTildeInPath)
let historyUIDs: [String] = {
    guard let data = try? Data(contentsOf: historyFile),
          let history = try? JSONDecoder().decode(WorkflowHistory.self, from: data)
    else { return [] }
    return history.preferences.workflows
}()

var historyItems = [[String: Any]]()
var nonHistoryItems = [[String: Any]]()
for item in allItems {
    guard let uid = item["arg"] as? String else { continue }
    historyUIDs.contains(uid) ? historyItems.append(item) : nonHistoryItems.append(item)
}

historyItems.sort { item1, item2 in
    let uid1 = item1["arg"] as! String
    let uid2 = item2["arg"] as! String
    return historyUIDs.firstIndex(of: uid1)! < historyUIDs.firstIndex(of: uid2)!
}

let sortedAllItems = historyItems + nonHistoryItems

// Output the final JSON
let output: [String: Any] = ["items": sortedAllItems]
if let jsonData = try? JSONSerialization.data(withJSONObject: output, options: []),
   let jsonString = String(data: jsonData, encoding: .utf8) {
    print(jsonString)
} else {
    print("{\"items\": []}")
}
