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
    # next unless createdby.downcase.include?(Keyword.downcase) || description.downcase.include?(Keyword.downcase) || name.downcase.include?(Keyword.downcase)

    subtitle_parts = []
    
    subtitle_parts << createdby unless createdby.empty?
    subtitle_parts << description unless description.empty?
    subtitle = subtitle_parts.empty? ? "No author or Description" : subtitle_parts.join('・')

    title_parts = []
    title_parts << name
    title_parts << version unless version.empty?
    title = title_parts.join('・')

    mods = {}
    # copy bundle Id
    mods[:'shift+cmd'] = bundleid.empty? ? { subtitle: "No Bundle Id", valid: false} : { subtitle: "Copy Bundle Id: #{bundleid}", arg: bundleid}

    mods[:cmd] = { subtitle: "Open configuration"}
    
    mods[:shift] = { subtitle: "Workflow folder", arg: File.dirname(plist_path)}
    
    # pass data folder
    mods[:ctrl] = !bundleid.empty? && File.directory?(File.join(Workflow_data_folder, bundleid)) ? { subtitle: "Data folder", arg: File.join(Workflow_data_folder, bundleid)} : {subtitle: 'No data folder found', valid: false}
    
    # pass cache folder
    mods[:'alt+ctrl'] = !bundleid.empty? && File.directory?(File.join(Workflow_cache_folder, bundleid)) ? { subtitle: "Cache folder", arg: File.join(Workflow_cache_folder, bundleid)} : {subtitle: 'No cache folder found', valid: false}
    
    # trash workflow
    mods[:'shift+ctrl'] = { subtitle: "Trash workflow", arg: File.dirname(plist_path)}    

    # copy information for workflow
    mods[:'shift+cmd+alt'] = { subtitle: "Copy workflow info", arg: "#{name}・#{version.empty? ? 'version empty' : version}, bundle ID: #{bundleid.empty? ? 'no bundle Id' : bundleid} . Alfred version: #{Alfred_version} #{Alfred_version_build}. macOS: #{`sw_vers -productVersion`.strip}."}    

    icon = {
      path: File.exist?(File.join(File.dirname(plist_path), '/icon.png')) ? File.join(File.dirname(plist_path), 'icon.png') : './Empty.png' 
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

    items << item
  end

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

  puts JSON.generate({ cache: { seconds: 3600 }, items: items })
