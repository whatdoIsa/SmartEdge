#!/usr/bin/env python3

import re
import os

def clean_project_file():
    """Remove references to deleted files from Xcode project"""
    project_file = 'SmartEdge.xcodeproj/project.pbxproj'
    
    # Files that were deleted
    deleted_files = [
        'SmartEdge/UI/NotchShape.swift',
        'SmartEdge/Features/Notch/Models/NotchModels.swift', 
        'SmartEdge/Shared/Models/MockServices.swift',
        'SmartEdge/Features/Notch/Components/AlbumArtworkView.swift',
        'SmartEdge/Features/Notch/Components/MusicVisualizerView.swift'
    ]
    
    with open(project_file, 'r') as f:
        content = f.read()
    
    original_content = content
    
    for deleted_file in deleted_files:
        filename = os.path.basename(deleted_file)
        
        # Remove file reference lines
        pattern = rf'.*{re.escape(filename)}.*?= \{{isa = PBXFileReference.*?\}};'
        content = re.sub(pattern, '', content, flags=re.MULTILINE)
        
        # Remove build file lines  
        pattern = rf'.*{re.escape(filename)} in Sources.*?= \{{isa = PBXBuildFile.*?\}};'
        content = re.sub(pattern, '', content, flags=re.MULTILINE)
        
        # Remove from sources build phase
        pattern = rf'.*{re.escape(filename)} in Sources.*?,\n?'
        content = re.sub(pattern, '', content, flags=re.MULTILINE)
        
        print(f"Removed references to: {filename}")
    
    # Clean up empty lines
    content = re.sub(r'\n\s*\n\s*\n', '\n\n', content)
    
    if content != original_content:
        with open(project_file, 'w') as f:
            f.write(content)
        print("Project file cleaned up!")
    else:
        print("No changes needed.")

if __name__ == "__main__":
    clean_project_file()