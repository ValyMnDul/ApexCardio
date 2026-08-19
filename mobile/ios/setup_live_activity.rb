require 'xcodeproj'

project_path = File.expand_path('Runner.xcodeproj', __dir__)
extension_name = 'ApexCardioLiveActivityExtension'
extension_folder_name = 'ApexCardioLiveActivityExtension'
deployment_target = '16.1'

project = Xcodeproj::Project.open(project_path)

runner_target = project.targets.find { |target| target.name == 'Runner' }

raise 'Runner target not found.' if runner_target.nil?

runner_group =
  project.main_group.groups.find { |group| group.display_name == 'Runner' }

raise 'Runner group not found.' if runner_group.nil?

extension_group =
  project.main_group.groups.find do |group|
    group.display_name == extension_folder_name
  end

extension_group ||= project.main_group.new_group(
  extension_folder_name,
  extension_folder_name
)

def find_or_create_file(group, file_name)
  existing = group.files.find do |file|
    file.path == file_name || file.display_name == file_name
  end

  existing || group.new_file(file_name)
end

def add_file_once(target, file_ref)
  exists = target.source_build_phase.files.any? do |build_file|
    build_file.file_ref == file_ref
  end

  target.add_file_references([file_ref]) unless exists
end

shared_file = find_or_create_file(
  runner_group,
  'ApexCardioRecordingActivityShared.swift'
)

bridge_file = find_or_create_file(
  runner_group,
  'ApexCardioLiveActivityBridge.swift'
)

live_activity_file = find_or_create_file(
  extension_group,
  'ApexCardioLiveActivity.swift'
)

extension_target =
  project.targets.find { |target| target.name == extension_name }

if extension_target.nil?
  extension_target = project.new_target(
    :app_extension,
    extension_name,
    :ios,
    deployment_target,
    nil,
    :swift
  )
end

unless extension_target.build_configurations.any? { |config| config.name == 'Profile' }
  extension_target.add_build_configuration(
    'Profile',
    :release
  )
end

generated_xcconfig_path = File.expand_path(
  'Flutter/Generated.xcconfig',
  __dir__
)

flutter_values = {}

if File.exist?(generated_xcconfig_path)
  File.readlines(generated_xcconfig_path).each do |line|
    next unless line.include?('=')

    key, value = line.strip.split('=', 2)
    flutter_values[key] = value if key && value
  end
end

flutter_build_name =
  flutter_values['FLUTTER_BUILD_NAME'] ||
  ENV['FLUTTER_BUILD_NAME'] ||
  '1.0.0'

flutter_build_number =
  flutter_values['FLUTTER_BUILD_NUMBER'] ||
  ENV['FLUTTER_BUILD_NUMBER'] ||
  '1'

runner_configurations = runner_target.build_configurations.each_with_object({}) do |config, map|
  map[config.name] = config
end

extension_target.build_configurations.each do |config|
  runner_config =
    runner_configurations[config.name] ||
    runner_configurations['Release'] ||
    runner_target.build_configurations.first

  runner_bundle_id =
    ENV['APEX_IOS_BUNDLE_ID'] ||
    runner_config.build_settings['PRODUCT_BUNDLE_IDENTIFIER']

  if runner_bundle_id.nil? || runner_bundle_id.to_s.strip.empty?
    raise 'Could not determine Runner PRODUCT_BUNDLE_IDENTIFIER.'
  end

  if runner_bundle_id.include?('$(') || runner_bundle_id.include?('${')
    raise <<~MESSAGE
      Runner PRODUCT_BUNDLE_IDENTIFIER contains an unresolved build variable:
      #{runner_bundle_id}

      Set APEX_IOS_BUNDLE_ID in GitHub Actions before running this script.
    MESSAGE
  end

  settings = config.build_settings

  settings['APPLICATION_EXTENSION_API_ONLY'] = 'YES'
  settings['CLANG_ENABLE_MODULES'] = 'YES'
  settings['CURRENT_PROJECT_VERSION'] = flutter_build_number
  settings['GENERATE_INFOPLIST_FILE'] = 'NO'
  settings['INFOPLIST_FILE'] =
    "#{extension_folder_name}/Info.plist"
  settings['IPHONEOS_DEPLOYMENT_TARGET'] =
    deployment_target
  settings['MARKETING_VERSION'] =
    flutter_build_name
  settings['PRODUCT_BUNDLE_IDENTIFIER'] =
    "#{runner_bundle_id}.ApexCardioLiveActivityExtension"
  settings['PRODUCT_NAME'] = '$(TARGET_NAME)'
  settings['SKIP_INSTALL'] = 'YES'
  settings['SWIFT_EMIT_LOC_STRINGS'] = 'YES'
  settings['SWIFT_VERSION'] = '5.0'
  settings['TARGETED_DEVICE_FAMILY'] = '1,2'

  development_team =
    runner_config.build_settings['DEVELOPMENT_TEAM']

  unless development_team.nil? || development_team.to_s.empty?
    settings['DEVELOPMENT_TEAM'] = development_team
  end
end

add_file_once(
  runner_target,
  shared_file
)

add_file_once(
  runner_target,
  bridge_file
)

add_file_once(
  extension_target,
  live_activity_file
)

add_file_once(
  extension_target,
  shared_file
)

%w[
  ActivityKit
  SwiftUI
  WidgetKit
].each do |framework|
  extension_target.add_system_framework(framework)
end

unless runner_target.dependency_for_target(extension_target)
  runner_target.add_dependency(extension_target)
end

embed_phase =
  runner_target.copy_files_build_phases.find do |phase|
    [
      'Embed Foundation Extensions',
      'Embed App Extensions',
    ].include?(phase.name)
  end

if embed_phase.nil?
  embed_phase =
    runner_target.new_copy_files_build_phase(
      'Embed Foundation Extensions'
    )

  embed_phase.symbol_dst_subfolder_spec =
    :plug_ins
  embed_phase.dst_path = ''
end

already_embedded =
  embed_phase.files.any? do |build_file|
    build_file.file_ref == extension_target.product_reference
  end

unless already_embedded
  build_file =
    embed_phase.add_file_reference(
      extension_target.product_reference,
      true
    )

  build_file.settings = {
    'ATTRIBUTES' => [
      'RemoveHeadersOnCopy',
    ],
  }
end

project.save

puts
puts 'ApexCardio Live Activity target configured.'
puts "Target: #{extension_target.name}"
puts "Deployment target: iOS #{deployment_target}"
puts 'Runner files:'
puts '  ApexCardioRecordingActivityShared.swift'
puts '  ApexCardioLiveActivityBridge.swift'
puts 'Extension files:'
puts '  ApexCardioLiveActivity.swift'
puts '  ApexCardioRecordingActivityShared.swift'
puts 'Live Activity extension embedded into Runner.'