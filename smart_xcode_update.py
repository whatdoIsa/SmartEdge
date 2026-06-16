#!/usr/bin/env python3

import os
import re

def find_swift_files(directory):
    """Find all Swift files in the SmartEdge target directory"""
    swift_files = []
    for root, dirs, files in os.walk(directory):
        for file in files:
            if file.endswith('.swift'):
                full_path = os.path.join(root, file)
                rel_path = os.path.relpath(full_path, directory)
                swift_files.append({
                    'filename': file,
                    'relative_path': rel_path,
                    'full_path': full_path
                })
    return sorted(swift_files, key=lambda x: x['filename'])

def read_project_file(project_path):
    """Read the Xcode project file"""
    with open(project_path, 'r') as f:
        return f.read()

def find_existing_files(content):
    """Find existing file references in project"""
    existing_files = set()
    
    # Find file references - looking for any .swift files
    file_ref_pattern = r'/\* (.+?\.swift) \*/ = \{isa = PBXFileReference;'
    matches = re.findall(file_ref_pattern, content)
    
    for match in matches:
        existing_files.add(match)  # Add filename
    
    return existing_files

def get_next_ids(content):
    """Get the next available IDs for build files and file references"""
    
    # Find all build file IDs starting with 1A
    build_file_pattern = r'(1A\w{21}) /\*.*?\*/ = \{isa = PBXBuildFile;'
    build_ids = []
    for match in re.findall(build_file_pattern, content):
        # Convert hex to int for comparison
        build_ids.append(int(match, 16))
    
    # Find all file reference IDs starting with 2A
    file_ref_pattern = r'(2A\w{21}) /\*.*?\*/ = \{isa = PBXFileReference;'
    file_ref_ids = []
    for match in re.findall(file_ref_pattern, content):
        file_ref_ids.append(int(match, 16))
    
    # Get next available IDs
    next_build_id = max(build_ids) + 1 if build_ids else int('1A000001000000000000014', 16)
    next_file_ref_id = max(file_ref_ids) + 1 if file_ref_ids else int('2A000001000000000000014', 16)
    
    return next_build_id, next_file_ref_id

def add_files_to_project(content, swift_files):
    """Add missing Swift files to Xcode project"""
    
    existing_files = find_existing_files(content)
    print(f"Found {len(existing_files)} existing Swift files in project: {sorted(existing_files)}")
    
    new_files = []
    for file_info in swift_files:
        if file_info['filename'] not in existing_files:
            new_files.append(file_info)
    
    print(f"Need to add {len(new_files)} new files to project")
    
    if not new_files:
        print("All files are already in the project")
        return content
    
    next_build_id, next_file_ref_id = get_next_ids(content)
    
    build_file_entries = []
    file_ref_entries = []
    sources_entries = []
    
    for i, file_info in enumerate(new_files):
        build_file_id = f"{next_build_id + i:024X}"
        file_ref_id = f"{next_file_ref_id + i:024X}"
        
        # Build file entry
        build_file_entries.append(
            f"\t\t{build_file_id} /* {file_info['filename']} in Sources */ = {{isa = PBXBuildFile; fileRef = {file_ref_id} /* {file_info['filename']} */; }};"
        )
        
        # File reference entry  
        file_ref_entries.append(
            f"\t\t{file_ref_id} /* {file_info['filename']} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = \"{file_info['filename']}\"; sourceTree = \"<group>\"; }};"
        )
        
        # Sources entry
        sources_entries.append(
            f"\t\t\t\t{build_file_id} /* {file_info['filename']} in Sources */,"
        )
    
    # 1. Add to PBXBuildFile section (before the End comment)
    build_file_pattern = r'(/\* End PBXBuildFile section \*/)'
    if build_file_entries:
        build_file_insertion = '\n'.join(build_file_entries) + '\n\t\t'
        content = re.sub(build_file_pattern, build_file_insertion + r'\1', content)
    
    # 2. Add to PBXFileReference section (before the End comment)
    file_ref_pattern = r'(/\* End PBXFileReference section \*/)'
    if file_ref_entries:
        file_ref_insertion = '\n'.join(file_ref_entries) + '\n\t\t'
        content = re.sub(file_ref_pattern, file_ref_insertion + r'\1', content)
    
    # 3. Find the PBXSourcesBuildPhase section and add files
    if sources_entries:
        sources_pattern = r'(\w+) /\* Sources \*/ = \{(\s+isa = PBXSourcesBuildPhase;.*?files = \(\s*\n)(.*?)(\s*\);.*?\};)'
        
        def replace_sources(match):
            section_id = match.group(1)
            prefix = match.group(2)
            existing_sources = match.group(3)
            suffix = match.group(4)
            
            new_sources = '\n'.join(sources_entries)
            if existing_sources.strip():
                return section_id + ' /* Sources */ = {' + prefix + existing_sources + '\n' + new_sources + suffix
            else:
                return section_id + ' /* Sources */ = {' + prefix + new_sources + suffix
        
        content = re.sub(sources_pattern, replace_sources, content, flags=re.DOTALL)
    
    return content

def add_frameworks_to_project(content):
    """Add required frameworks to the project"""
    frameworks_needed = [
        'IOKit.framework',
        'CoreAudio.framework', 
        'EventKit.framework',
        'CoreBluetooth.framework',
        'Carbon.framework'
    ]
    
    # Check if frameworks are already present
    existing_frameworks = set()
    framework_pattern = r'/\* (.+?\.framework) (?:in Frameworks )?\*/'
    matches = re.findall(framework_pattern, content)
    
    for match in matches:
        existing_frameworks.add(match)
    
    new_frameworks = [fw for fw in frameworks_needed if fw not in existing_frameworks]
    
    if not new_frameworks:
        print("All required frameworks are already linked")
        return content
        
    print(f"Adding {len(new_frameworks)} frameworks: {new_frameworks}")
    
    # Get next available IDs
    next_build_id, next_file_ref_id = get_next_ids(content)
    
    # Use higher IDs for frameworks to avoid conflicts
    framework_build_id_start = next_build_id + 1000
    framework_file_ref_start = next_file_ref_id + 1000
    
    framework_build_entries = []
    framework_ref_entries = []
    framework_files_entries = []
    
    for i, framework in enumerate(new_frameworks):
        build_file_id = f"{framework_build_id_start + i:024X}"
        file_ref_id = f"{framework_file_ref_start + i:024X}"
        
        # Build file entry for framework
        framework_build_entries.append(
            f"\t\t{build_file_id} /* {framework} in Frameworks */ = {{isa = PBXBuildFile; fileRef = {file_ref_id} /* {framework} */; }};"
        )
        
        # File reference for framework
        framework_ref_entries.append(
            f"\t\t{file_ref_id} /* {framework} */ = {{isa = PBXFileReference; lastKnownFileType = wrapper.framework; name = {framework}; path = System/Library/Frameworks/{framework}; sourceTree = SDKROOT; }};"
        )
        
        # Framework files entry
        framework_files_entries.append(
            f"\t\t\t\t{build_file_id} /* {framework} in Frameworks */,"
        )
    
    # Add framework build file entries
    if framework_build_entries:
        build_file_pattern = r'(/\* End PBXBuildFile section \*/)'
        build_file_insertion = '\n'.join(framework_build_entries) + '\n\t\t'
        content = re.sub(build_file_pattern, build_file_insertion + r'\1', content)
    
    # Add framework file references
    if framework_ref_entries:
        file_ref_pattern = r'(/\* End PBXFileReference section \*/)'
        file_ref_insertion = '\n'.join(framework_ref_entries) + '\n\t\t'
        content = re.sub(file_ref_pattern, file_ref_insertion + r'\1', content)
    
    # Add to frameworks build phase
    if framework_files_entries:
        frameworks_pattern = r'(\w+) /\* Frameworks \*/ = \{(\s+isa = PBXFrameworksBuildPhase;.*?files = \(\s*\n)(.*?)(\s*\);.*?\};)'
        
        def replace_frameworks(match):
            section_id = match.group(1)
            prefix = match.group(2)
            existing_frameworks = match.group(3) 
            suffix = match.group(4)
            
            new_fw_entries = '\n'.join(framework_files_entries)
            if existing_frameworks.strip():
                return section_id + ' /* Frameworks */ = {' + prefix + existing_frameworks + '\n' + new_fw_entries + suffix
            else:
                return section_id + ' /* Frameworks */ = {' + prefix + new_fw_entries + suffix
        
        content = re.sub(frameworks_pattern, replace_frameworks, content, flags=re.DOTALL)
    
    return content

def main():
    project_dir = "/Users/dean_ssong/Desktop/SmartEdge"
    target_dir = os.path.join(project_dir, "SmartEdge")
    project_file = os.path.join(project_dir, "SmartEdge.xcodeproj", "project.pbxproj")
    
    print("Finding Swift files...")
    swift_files = find_swift_files(target_dir)
    print(f"Found {len(swift_files)} Swift files in target directory")
    
    print("Reading project file...")
    content = read_project_file(project_file)
    
    print("Updating project file with Swift files...")
    updated_content = add_files_to_project(content, swift_files)
    
    print("Adding required frameworks...")
    updated_content = add_frameworks_to_project(updated_content)
    
    # Write updated project file
    with open(project_file, 'w') as f:
        f.write(updated_content)
    
    print("Project file updated successfully!")

if __name__ == "__main__":
    main()