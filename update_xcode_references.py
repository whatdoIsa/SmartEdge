#!/usr/bin/env python3

import re
import os

def update_project_file():
    project_file = 'SmartEdge.xcodeproj/project.pbxproj'
    
    # Read the project file
    with open(project_file, 'r') as f:
        content = f.read()
    
    print("Updating file references in Xcode project...")
    
    # Define file path mappings (old -> new)
    path_mappings = {
        'SettingsViewModel.swift': 'SmartEdge/Features/Settings/SettingsViewModel.swift',
        'AppCoordinator.swift': 'SmartEdge/Core/Coordinators/AppCoordinator.swift',
        'AppCoordinatorProtocol.swift': 'SmartEdge/Core/Protocols/AppCoordinatorProtocol.swift',
        'ServiceContainer.swift': 'SmartEdge/Core/Services/ServiceContainer.swift',
        'ServiceProtocols.swift': 'SmartEdge/Core/Protocols/ServiceProtocols.swift',
        'MediaService.swift': 'SmartEdge/Core/Services/MediaService.swift',
        'MediaServiceProtocol.swift': 'SmartEdge/Core/Protocols/MediaServiceProtocol.swift',
        'NotchWindowService.swift': 'SmartEdge/Core/Services/NotchWindowService.swift',
        'NotchWindowProtocol.swift': 'SmartEdge/Core/Protocols/NotchWindowProtocol.swift',
        'NotchView.swift': 'SmartEdge/Features/Notch/NotchView.swift',
        'NotchViewModel.swift': 'SmartEdge/Features/Notch/NotchViewModel.swift',
        'NotchModels.swift': 'SmartEdge/Shared/Models/NotchModels.swift',
        'MediaModels.swift': 'SmartEdge/Shared/Models/MediaModels.swift',
        'SmartEdgeError.swift': 'SmartEdge/Shared/Models/SmartEdgeError.swift',
        'NotchShape.swift': 'SmartEdge/Shared/Components/NotchShape.swift'
    }
    
    # Update file references in the project
    for old_file, new_path in path_mappings.items():
        # Look for file references with just filename
        pattern = fr'(path = )({old_file})(; sourceTree.*?;)'
        if re.search(pattern, content):
            content = re.sub(pattern, fr'\1{new_path}\3', content)
            print(f"Updated: {old_file} -> {new_path}")
        
        # Look for file references with partial paths
        pattern = fr'(path = )([^"]*/{old_file})(; sourceTree.*?;)'
        if re.search(pattern, content):
            content = re.sub(pattern, fr'\1{new_path}\3', content)
            print(f"Updated path: {old_file} -> {new_path}")
    
    # Write the updated content back to the project file
    with open(project_file, 'w') as f:
        f.write(content)
    
    print("Project file updated successfully!")

if __name__ == "__main__":
    update_project_file()