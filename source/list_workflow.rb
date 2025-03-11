#!/usr/bin/env ruby

require 'fileutils'
require 'json'
require 'open3'

Alfred_preferences = ENV['alfred_preferences']
Workflow_cache_folder = File.dirname(ENV['alfred_workflow_cache'])
Workflow_data_folder = File.dirname(ENV['alfred_workflow_data'])
Alfred_version = ENV['alfred_version']
Alfred_version_build = ENV['alfred_version_build']

Only_show_enabled = ENV['only_show_enabled'] == '1'

# Keyword = ARGV[0]

def parse_plist(plist_path)
  json_str = `plutil -convert json -o - "#{plist_path}" 2>&1`
  if $?.success?
    JSON.parse(json_str)
  else
    puts "Failed to convert #{plist_path} to JSON: #{json_str}"
    {}
  end
  rescue => e
    puts "Error parsing #{plist_path}: #{e}"
    {}
  end

  workflows_dir = File.join(Alfred_preferences, 'workflows')
  plist_paths = Dir.glob(File.join(workflows_dir, '*/info.plist'))

  items = []

  enabled_items = []
  disabled_items = []
  
  plist_paths.each do |plist_path|

    next unless File.exist?(plist_path)

    folder_name = File.basename(File.dirname(plist_path))
    plist = parse_plist(plist_path)

    enabled = plist['disabled'] == false
    next if !enabled && Only_show_enabled

    name = plist['name']
    description = plist['description'] || ''
    version = plist['version'].nil? || plist['version'].empty? ? '' : "v#{plist['version']}"
    bundleid = plist['bundleid'] || ''

    createdby = plist['createdby'].empty? ? '' : "by #{plist['createdby']}"

    # do not process keyword in code
    # since we're using Script Filter caching
    # next unless createdby.downcase.include?(Keyword.downcase) || description.downcase.include?(Keyword.downcase) || name.downcase.include?(Keyword.downcase)

    subtitle_parts = []

    subtitle_parts << createdby unless createdby.empty?
    subtitle_parts << description unless description.empty?
    subtitle = subtitle_parts.empty? ? "No author or Description" : subtitle_parts.join('・')

    title_parts = []
    title_parts << (enabled ? "#{name}" : "🚫 #{name}")
    title_parts << version unless version.empty?
    title = title_parts.join('・')

    secondary_menu_json = {}
    secondary_menu_json_items = []

    mods = {}

    # Open configuration
    mods[:cmd] = { subtitle: "Open configuration" }

    secondary_menu_json_items << { title: 'Open Configuration', subtitle: "Open configuration of ‘#{name}’ in Alfred Preferences.", variables: { chosen_action: 'Open Configuration'}, icon: { path: 'icons/Alfred Preferences.png' } }

    # copy bundle Id
    mods[:'shift+cmd'] = bundleid.empty? ? { subtitle: "No Bundle Id", valid: false } : { subtitle: "Copy Bundle Id: #{bundleid}", arg: bundleid }

    secondary_menu_json_items << { title: 'Copy Bundle Id', subtitle: bundleid.empty? ? 'No Bundle Id' : "Copy Bundle Id for ‘#{name}’: #{bundleid}", valid: !bundleid.empty?, arg: bundleid, variables: { chosen_action: 'Copy Bundle Id'}, icon: { path: 'icons/copy.png' } }

    # copy information for workflow
    info_arg = "#{name}・#{version.empty? ? 'version empty' : version}, bundle ID: #{bundleid.empty? ? 'no bundle Id' : bundleid} . Alfred version: #{Alfred_version} #{Alfred_version_build}. macOS: #{`sw_vers -productVersion`.strip}."

    mods[:'shift+cmd+alt'] = { subtitle: "Copy workflow info", arg: info_arg }

    secondary_menu_json_items << { title: 'Copy Information for Workflow', subtitle: "Copy workflow info for ‘#{name}’. Name, version, bundle Id, macOS and Alfred version included.", arg: info_arg, variables: { chosen_action: 'Copy Information for Workflow' }, icon: { path: 'icons/copy.png' } }

    # Workflow folder
    mods[:shift] = { subtitle: "Workflow folder", arg: File.dirname(plist_path) }

    secondary_menu_json_items << { title: 'Show Workflow Folder', subtitle: "Show workflow folder of ‘#{name}’ in Finder", arg: File.dirname(plist_path), variables: { chosen_action: 'Show Workflow Folder'} , icon: { path: 'icons/finder.png' } }

    # pass data folder
    mods[:ctrl] = !bundleid.empty? && File.directory?(File.join(Workflow_data_folder, bundleid)) ? { subtitle: "Data folder", arg: File.join(Workflow_data_folder, bundleid) } : { subtitle: 'No data folder found', valid: false }

    secondary_menu_json_items << ( !bundleid.empty? && File.directory?(File.join(Workflow_data_folder, bundleid)) ? { title: 'Show Data Folder', subtitle: "Show data folder of ‘#{name}’ in Finder", arg: File.join(Workflow_data_folder, bundleid), variables: { chosen_action: 'Show Data Folder'} , icon: { path: 'icons/finder.png' } } : { title: "No Data folder Found", subtitle: "No data folder found for workflow ‘#{name}’.", valid: false, icon: { path: 'icons/Empty.png' } } )

    # pass cache folder
    mods[:'alt+ctrl'] = !bundleid.empty? && File.directory?(File.join(Workflow_cache_folder, bundleid)) ? { subtitle: "Cache folder", arg: File.join(Workflow_cache_folder, bundleid) } : { subtitle: 'No cache folder found', valid: false }

    secondary_menu_json_items << ( !bundleid.empty? && File.directory?(File.join(Workflow_cache_folder, bundleid)) ? { title: 'Show Cache Folder', subtitle: "Show cache folder of ‘#{name}’ in Finder", arg: File.join(Workflow_cache_folder, bundleid), variables: { chosen_action: 'Show Cache Folder'}, icon: { path: 'icons/finder.png' } } : { title: "No cache folder Found", subtitle: "No cache folder found for workflow ‘#{name}’.", valid: false, icon: { path: 'icons/Empty.png' } } )

    # trash workflow
    mods[:'shift+ctrl'] = { subtitle: "Trash workflow", arg: File.dirname(plist_path) }

    secondary_menu_json_items << { title: 'Trash Workflow', subtitle: "Trash workflow ‘#{name}’. Can be undone from the Trash.", arg: File.dirname(plist_path), variables: { chosen_action: 'Trash Workflow'}, icon: { path: 'icons/trash.png' } }

    # export workflow
    secondary_menu_json_items << { title: 'Export Workflow', subtitle: "Export as ‘#{name}.alfredworkflow’ to your Desktop", arg: File.dirname(plist_path), variables: { chosen_action: 'Export Workflow'}, icon: { path: 'icons/alfred_workflow.png' }}

    # secondary Script Filter
    secondary_menu_json[:items] = secondary_menu_json_items
    mods[:'alt'] = { subtitle: "Show All Actions", variables: { script_filter_res: secondary_menu_json.to_json }, arg: ""}

  
    icon = {
      path: File.exist?(File.join(File.dirname(plist_path), 'icon.png')) ? File.join(File.dirname(plist_path), 'icon.png') : 'icons/Empty.png'
    }
  
    item = {
      title: title,
      subtitle: subtitle.empty? ? 'No description or version' : subtitle,
      mods: mods,
      action: {},
      arg: folder_name,
      icon: icon,
      uid: title,
      match: "#{description} #{createdby} #{name}"
    }
  
    if enabled
      enabled_items << item
    else
      disabled_items << item
    end
  end
  
  # Concatenate enabled and disabled items, keeping their internal order
  items = enabled_items + disabled_items
    

  # do not add empty item
  # since we're using Script Filter caching
  # if items.empty?
  #   puts JSON.generate({ items: [
  #     {
  #       title: "No Workflow Found",
  #       subtitle: "No #{Only_show_enabled ? 'enabled ' : 'installed ' }workflow found for query “#{Keyword}”",
  #       arg: ""
  #     }
  #   ]})
  #   return
  # end

  puts JSON.generate({ cache: { seconds: 7200 }, items: items })
