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

    // Customizable modifier keys
    static let modifierKeyNone = env["modifier_key_none"] ?? "Edit Workflow in Alfred"
    static let modifierKeyCmd = env["modifier_key_cmd"] ?? "Open Configuration"
    static let modifierKeyOption = env["modifier_key_option"] ?? "Show All Actions"
    static let modifierKeyShift = env["modifier_key_shift"] ?? "Show Workflow Folder"
    static let modifierKeyCtrl = env["modifier_key_ctrl"] ?? "Trash Workflow"
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

// MARK: - Action Resolution

struct ActionDetails {
    let subtitle: String
    let arg: String
    let icon: [String: String]
    let valid: Bool
    let variables: [String: String]
}

func buildSecondaryMenuItem(
    actionName: String,
    name: String,
    bundleid: String,
    workflowFolderPath: String,
    workflowDataFolder: String,
    workflowCacheFolder: String,
    infoArg: String,
    secondaryMenuJsonString: String,
    folderName: String,
    dataFolderExists: Bool,
    cacheFolderExists: Bool
) -> [String: Any] {
    let details = resolveAction(
        actionName,
        name: name,
        bundleid: bundleid,
        workflowFolderPath: workflowFolderPath,
        workflowDataFolder: workflowDataFolder,
        workflowCacheFolder: workflowCacheFolder,
        infoArg: infoArg,
        secondaryMenuJsonString: secondaryMenuJsonString,
        folderName: folderName,
        dataFolderExists: dataFolderExists,
        cacheFolderExists: cacheFolderExists
    )

    var item: [String: Any] = [
        "title": actionName,
        "subtitle": details.subtitle,
        "icon": details.icon
    ]

    if !details.valid {
        item["valid"] = false
    }

    if !details.arg.isEmpty {
        item["arg"] = details.arg
    }

    if !details.variables.isEmpty {
        item["variables"] = details.variables
    }

    return item
}

func resolveAction(
    _ actionName: String,
    name: String,
    bundleid: String,
    workflowFolderPath: String,
    workflowDataFolder: String,
    workflowCacheFolder: String,
    infoArg: String,
    secondaryMenuJsonString: String,
    folderName: String,
    dataFolderExists: Bool,
    cacheFolderExists: Bool
) -> ActionDetails {
    switch actionName {
    case "Show All Actions":
        return ActionDetails(
            subtitle: "Show All Actions",
            arg: "",
            icon: ["path": "icons/actions.png"],
            valid: true,
            variables: ["script_filter_res": secondaryMenuJsonString, "chosen_action": "Show All Actions"]
        )

    case "Edit Workflow in Alfred":
        return ActionDetails(
            subtitle: "Edit ‘\(name)’ workflow in Alfred Preferences.",
            arg: folderName,
            icon: ["path": "icons/Alfred Preferences.png"],
            valid: true,
            variables: ["chosen_action": "Edit Workflow in Alfred"]
        )

    case "Open Configuration":
        return ActionDetails(
            subtitle: "Open configuration of ‘\(name)’ in Alfred Preferences.",
            arg: folderName,
            icon: ["path": "icons/Alfred Preferences.png"],
            valid: true,
            variables: ["chosen_action": "Open Configuration"]
        )

    case "Copy Bundle Id":
        if bundleid.isEmpty {
            return ActionDetails(
                subtitle: "No Bundle Id",
                arg: "",
                icon: ["path": "icons/copy.png"],
                valid: false,
                variables: ["chosen_action": "Copy Bundle Id"]
            )
        } else {
            return ActionDetails(
                subtitle: "Copy Bundle Id for ‘\(name)’: \(bundleid)",
                arg: bundleid,
                icon: ["path": "icons/copy.png"],
                valid: true,
                variables: ["chosen_action": "Copy Bundle Id"]
            )
        }

    case "Copy Workflow Name":
        return ActionDetails(
            subtitle: "Copy workflow name ‘\(name)’",
            arg: name,
            icon: ["path": "icons/copy.png"],
            valid: true,
            variables: ["chosen_action": "Copy Workflow Name"]
        )

    case "Copy Workflow Information":
        return ActionDetails(
            subtitle: "Copy workflow info for ‘\(name)’. Name, version, bundle Id, macOS and Alfred version included.",
            arg: infoArg,
            icon: ["path": "icons/copy.png"],
            valid: true,
            variables: ["chosen_action": "Copy Workflow Information"]
        )

    case "Show Workflow Folder":
        return ActionDetails(
            subtitle: "Show workflow folder of ‘\(name)’ in Finder",
            arg: workflowFolderPath,
            icon: ["path": "icons/finder.png"],
            valid: true,
            variables: ["chosen_action": "Show Workflow Folder"]
        )

    case "Show Data Folder":
        if dataFolderExists {
            return ActionDetails(
                subtitle: "Show data folder of ‘\(name)’ in Finder",
                arg: workflowDataFolder,
                icon: ["path": "icons/finder.png"],
                valid: true,
                variables: ["chosen_action": "Show Data Folder"]
            )
        } else {
            return ActionDetails(
                subtitle: "No data folder found for workflow ‘\(name)’.",
                arg: "",
                icon: ["path": "icons/Empty.png"],
                valid: false,
                variables: ["chosen_action": "Show Data Folder"]
            )
        }

    case "Show Cache Folder":
        if cacheFolderExists {
            return ActionDetails(
                subtitle: "Show cache folder of ‘\(name)’ in Finder",
                arg: workflowCacheFolder,
                icon: ["path": "icons/finder.png"],
                valid: true,
                variables: ["chosen_action": "Show Cache Folder"]
            )
        } else {
            return ActionDetails(
                subtitle: "No cache folder found for workflow ‘\(name)’.",
                arg: "",
                icon: ["path": "icons/Empty.png"],
                valid: false,
                variables: ["chosen_action": "Show Cache Folder"]
            )
        }

    case "Reload Workflow":
        return ActionDetails(
            subtitle: "Reload ‘\(name)’ workflow in Alfred.",
            arg: folderName,
            icon: ["path": "icons/Alfred Preferences.png"],
            valid: true,
            variables: ["chosen_action": "Reload Workflow"]
        )

    case "Export Workflow":
        return ActionDetails(
            subtitle: "Export as ‘\(name).alfredworkflow’.",
            arg: workflowFolderPath,
            icon: ["path": "icons/alfred_workflow.png"],
            valid: true,
            variables: ["chosen_action": "Export Workflow"]
        )

    case "Trash Workflow":
        return ActionDetails(
            subtitle: "Trash workflow ‘\(name)’. Can be undone from the Trash.",
            arg: workflowFolderPath,
            icon: ["path": "icons/trash.png"],
            valid: true,
            variables: ["chosen_action": "Trash Workflow"]
        )

    default:
        // Fallback to Edit Workflow in Alfred
        return ActionDetails(
            subtitle: "Edit ‘\(name)’ workflow in Alfred Preferences.",
            arg: folderName,
            icon: ["path": "icons/Alfred Preferences.png"],
            valid: true,
            variables: ["chosen_action": "Edit Workflow in Alfred"]
        )
    }
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
    // First, calculate the data needed for action resolution
    let macVersion = getMacOSVersion()
    let infoArg = "\(name)・\(version.isEmpty ? "version empty" : version), bundle ID: \(bundleid.isEmpty ? "no bundle Id" : bundleid) . Alfred version: \(Environment.alfredVersion) \(Environment.alfredVersionBuild). macOS: \(macVersion)."

    // Calculate folder paths and existence
    let workflowDataFolder = URL(fileURLWithPath: Environment.workflowDataFolder)
        .deletingLastPathComponent()
        .appendingPathComponent(bundleid).path
    let dataFolderExists = !bundleid.isEmpty && fileManager.isDirectory(atPath: workflowDataFolder)

    let workflowCacheFolder = URL(fileURLWithPath: Environment.workflowCacheFolder)
        .deletingLastPathComponent()
        .appendingPathComponent(bundleid).path
    let cacheFolderExists = !bundleid.isEmpty && fileManager.isDirectory(atPath: workflowCacheFolder)

    // Build secondary menu items using the helper function
    let actionNames = [
        "Edit Workflow in Alfred",
        "Open Configuration",
        "Copy Bundle Id",
        "Copy Workflow Name",
        "Copy Workflow Information",
        "Show Workflow Folder",
        "Show Data Folder",
        "Show Cache Folder",
        "Reload Workflow",
        "Export Workflow",
        "Trash Workflow"
    ]

    var secondaryMenuItems = [[String: Any]]()
    for actionName in actionNames {
        let item = buildSecondaryMenuItem(
            actionName: actionName,
            name: name,
            bundleid: bundleid,
            workflowFolderPath: workflowFolderPath,
            workflowDataFolder: workflowDataFolder,
            workflowCacheFolder: workflowCacheFolder,
            infoArg: infoArg,
            secondaryMenuJsonString: "",  // Will be filled later for "Show All Actions"
            folderName: folderName,
            dataFolderExists: dataFolderExists,
            cacheFolderExists: cacheFolderExists
        )
        secondaryMenuItems.append(item)
    }

    // Build the secondary menu JSON (to be passed via the alt modifier)
    let secondaryMenuJson: [String: Any] = ["items": secondaryMenuItems]
    let secondaryMenuJsonData = try? JSONSerialization.data(withJSONObject: secondaryMenuJson, options: [])
    let secondaryMenuJsonString = secondaryMenuJsonData.flatMap { String(data: $0, encoding: .utf8) } ?? ""

    // --- Resolve actions based on environment variables ---
    let defaultAction = resolveAction(
        Environment.modifierKeyNone,
        name: name,
        bundleid: bundleid,
        workflowFolderPath: workflowFolderPath,
        workflowDataFolder: workflowDataFolder,
        workflowCacheFolder: workflowCacheFolder,
        infoArg: infoArg,
        secondaryMenuJsonString: secondaryMenuJsonString,
        folderName: folderName,
        dataFolderExists: dataFolderExists,
        cacheFolderExists: cacheFolderExists
    )

    let cmdAction = resolveAction(
        Environment.modifierKeyCmd,
        name: name,
        bundleid: bundleid,
        workflowFolderPath: workflowFolderPath,
        workflowDataFolder: workflowDataFolder,
        workflowCacheFolder: workflowCacheFolder,
        infoArg: infoArg,
        secondaryMenuJsonString: secondaryMenuJsonString,
        folderName: folderName,
        dataFolderExists: dataFolderExists,
        cacheFolderExists: cacheFolderExists
    )

    let optionAction = resolveAction(
        Environment.modifierKeyOption,
        name: name,
        bundleid: bundleid,
        workflowFolderPath: workflowFolderPath,
        workflowDataFolder: workflowDataFolder,
        workflowCacheFolder: workflowCacheFolder,
        infoArg: infoArg,
        secondaryMenuJsonString: secondaryMenuJsonString,
        folderName: folderName,
        dataFolderExists: dataFolderExists,
        cacheFolderExists: cacheFolderExists
    )

    let shiftAction = resolveAction(
        Environment.modifierKeyShift,
        name: name,
        bundleid: bundleid,
        workflowFolderPath: workflowFolderPath,
        workflowDataFolder: workflowDataFolder,
        workflowCacheFolder: workflowCacheFolder,
        infoArg: infoArg,
        secondaryMenuJsonString: secondaryMenuJsonString,
        folderName: folderName,
        dataFolderExists: dataFolderExists,
        cacheFolderExists: cacheFolderExists
    )

    let ctrlAction = resolveAction(
        Environment.modifierKeyCtrl,
        name: name,
        bundleid: bundleid,
        workflowFolderPath: workflowFolderPath,
        workflowDataFolder: workflowDataFolder,
        workflowCacheFolder: workflowCacheFolder,
        infoArg: infoArg,
        secondaryMenuJsonString: secondaryMenuJsonString,
        folderName: folderName,
        dataFolderExists: dataFolderExists,
        cacheFolderExists: cacheFolderExists
    )

    // --- Build the main modifiers dictionary ---
    var mods = [String: [String: Any]]()

    // Build mod entry for cmd
    var cmdMod: [String: Any] = ["subtitle": cmdAction.subtitle, "icon": cmdAction.icon]
    if !cmdAction.valid { cmdMod["valid"] = false }
    if !cmdAction.arg.isEmpty { cmdMod["arg"] = cmdAction.arg }
    if !cmdAction.variables.isEmpty { cmdMod["variables"] = cmdAction.variables }
    mods["cmd"] = cmdMod

    // Build mod entry for option (alt)
    var optionMod: [String: Any] = ["subtitle": optionAction.subtitle, "icon": optionAction.icon]
    if !optionAction.valid { optionMod["valid"] = false }
    if !optionAction.arg.isEmpty { optionMod["arg"] = optionAction.arg }
    if !optionAction.variables.isEmpty { optionMod["variables"] = optionAction.variables }
    mods["alt"] = optionMod

    // Build mod entry for shift
    var shiftMod: [String: Any] = ["subtitle": shiftAction.subtitle, "icon": shiftAction.icon]
    if !shiftAction.valid { shiftMod["valid"] = false }
    if !shiftAction.arg.isEmpty { shiftMod["arg"] = shiftAction.arg }
    if !shiftAction.variables.isEmpty { shiftMod["variables"] = shiftAction.variables }
    mods["shift"] = shiftMod

    // Build mod entry for ctrl
    var ctrlMod: [String: Any] = ["subtitle": ctrlAction.subtitle, "icon": ctrlAction.icon]
    if !ctrlAction.valid { ctrlMod["valid"] = false }
    if !ctrlAction.arg.isEmpty { ctrlMod["arg"] = ctrlAction.arg }
    if !ctrlAction.variables.isEmpty { ctrlMod["variables"] = ctrlAction.variables }
    mods["ctrl"] = ctrlMod

    // Determine the main icon (use icon.png if it exists, otherwise fallback)
    let iconPathCandidate = workflowDir.appendingPathComponent("icon.png").path
    let mainIconPath = fileManager.fileExists(atPath: iconPathCandidate) ? iconPathCandidate : "icons/Empty.png"
    let iconDict = ["path": mainIconPath]

    // Build the main item with dynamic default action
    var item: [String: Any] = [
        "title": title,
        "subtitle": subtitle.isEmpty ? "No description or version" : subtitle,
        "mods": mods,
        "action": [String: Any](),  // empty action object
        "arg": defaultAction.arg,
        "icon": iconDict,
        "match": Environment.showKeywords ? "\(keywordsCommaSeparated) \(createdby) \(name)" : "\(desc) \(createdby) \(name)"
    ]

    // Add variables from default action
    if !defaultAction.variables.isEmpty {
        item["variables"] = defaultAction.variables
    }

    // Add valid flag if needed
    if !defaultAction.valid {
        item["valid"] = false
    }

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
