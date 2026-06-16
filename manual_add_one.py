#!/usr/bin/env python3

import os
import re

def read_project_file(project_path):
    """Read the Xcode project file"""
    with open(project_path, 'r') as f:
        return f.read()

def add_settings_viewmodel(content):
    """Manually add SettingsViewModel.swift with correct path setup"""
    
    # Use the next available ID after the existing ones
    build_file_id = "1A000001000000000000014"  # Next after 13 existing ones
    file_ref_id = "2A000001000000000000014"
    
    filename = "SettingsViewModel.swift"
    
    # Build file entry
    build_file_entry = f"\t\t{build_file_id} /* {filename} in Sources */ = {{isa = PBXBuildFile; fileRef = {file_ref_id} /* {filename} */; }};"
    
    # File reference entry - use JUST the filename, like existing files
    file_ref_entry = f"\t\t{file_ref_id} /* {filename} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {filename}; sourceTree = \"<group>\"; }};"
    
    # Sources entry
    sources_entry = f"\t\t\t\t{build_file_id} /* {filename} in Sources */,"
    
    # Add to PBXBuildFile section
    build_file_pattern = r'(/\* End PBXBuildFile section \*/)'
    content = re.sub(build_file_pattern, build_file_entry + '\n\t\t' + r'\1', content)
    
    # Add to PBXFileReference section
    file_ref_pattern = r'(/\* End PBXFileReference section \*/)'
    content = re.sub(file_ref_pattern, file_ref_entry + '\n\t\t' + r'\1', content)
    
    # Add to Sources build phase
    sources_pattern = r'(\w+ /\* Sources \*/ = \{[^}]+files = \(\s*\n)(.*?)(\s*\);[^}]+\};)'
    
    def replace_sources(match):
        prefix = match.group(1)
        existing_sources = match.group(2)
        suffix = match.group(3)
        
        if existing_sources.strip():
            return prefix + existing_sources + '\n' + sources_entry + suffix
        else:
            return prefix + sources_entry + suffix
    
    content = re.sub(sources_pattern, replace_sources, content, flags=re.DOTALL)
    
    return content

def main():
    project_dir = "/Users/dean_ssong/Desktop/SmartEdge"
    project_file = os.path.join(project_dir, "SmartEdge.xcodeproj", "project.pbxproj")
    
    print("Reading project file...")
    content = read_project_file(project_file)
    
    print("Adding SettingsViewModel.swift...")
    updated_content = add_settings_viewmodel(content)
    
    # Write updated project file
    with open(project_file, 'w') as f:
        f.write(updated_content)
    
    print("SettingsViewModel.swift added!")
    print("Now copy the actual file to the project root for Xcode to find it...")

if __name__ == "__main__":
    main()