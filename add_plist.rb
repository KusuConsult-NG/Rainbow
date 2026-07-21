require 'xcodeproj'
project_path = 'ios/Runner.xcodeproj'
project = Xcodeproj::Project.open(project_path)

# Check if it already exists to avoid duplicates
runner_group = project.main_group.find_subpath('Runner', false)
existing_ref = runner_group.files.find { |f| f.path == 'GoogleService-Info.plist' }

if existing_ref
  puts "GoogleService-Info.plist is already in the project."
else
  file_ref = runner_group.new_reference('GoogleService-Info.plist')
  target = project.targets.find { |t| t.name == 'Runner' }
  target.resources_build_phase.add_file_reference(file_ref)
  project.save
  puts "Added GoogleService-Info.plist to project.pbxproj"
end
