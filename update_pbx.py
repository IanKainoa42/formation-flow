from pbxproj import XcodeProject

project_path = 'FormationFlow.xcodeproj/project.pbxproj'
project = XcodeProject.load(project_path)

# Try removing Views.swift
views_file = project.get_files_by_name('Views.swift')
if views_file:
    for f in views_file:
        project.remove_file_by_id(f.get_id())

# Files to add
files_to_add = [
    'MainMenuView.swift', 'FormationThumbnailView.swift', 'FormationListView.swift',
    'FloorCanvasView.swift', 'FloorGridView.swift', 'TransitionViews.swift',
    'TimingControlsView.swift', 'AthleteDetailPanel.swift'
]

# Get the target
target = project.get_target_by_name('FormationFlow')

# Find the group FormationFlow
group = project.get_groups_by_name('FormationFlow')
group_id = group[0].get_id() if group else None

for filename in files_to_add:
    file_path = 'FormationFlow/' + filename
    project.add_file(file_path, parent=group_id, target_name='FormationFlow')

project.save()
print("Project updated successfully.")
