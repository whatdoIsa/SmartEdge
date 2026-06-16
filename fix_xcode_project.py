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
    
    # Find file references - look for Swift files specifically
    file_ref_pattern = r'(\w{24}) /\* (.+?\.swift) \*/ = \{isa = PBXFileReference;'
    matches = re.findall(file_ref_pattern, content)
    
    for match in matches:
        existing_files.add(match[1])  # Add filename
    
    return existing_files

def add_files_to_project(content, swift_files):
    """Add missing Swift files to Xcode project"""
    
    existing_files = find_existing_files(content)
    print(f"Found {len(existing_files)} existing Swift files in project")
    
    new_files = []
    for file_info in swift_files:
        if file_info['filename'] not in existing_files:
            new_files.append(file_info)
    
    print(f"Need to add {len(new_files)} new files to project")
    
    if not new_files:
        print("All files are already in the project")
        return content
    
    # Find the highest existing IDs to continue numbering
    build_file_pattern = r'1A(\w{21}) /\*.*?\*/ = \{isa = PBXBuildFile;'
    file_ref_pattern = r'2A(\w{21}) /\*.*?\*/ = \{isa = PBXFileReference;'
    
    build_file_ids = [int(match, 16) for match in re.findall(build_file_pattern, content)]
    file_ref_ids = [int(match, 16) for match in re.findall(file_ref_pattern, content)]
    
    next_build_id = max(build_file_ids) + 1 if build_file_ids else int('000001000000000000014', 16)
    next_file_ref_id = max(file_ref_ids) + 1 if file_ref_ids else int('000001000000000000014', 16)
    
    build_file_entries = []
    file_ref_entries = []
    sources_entries = []
    
    for i, file_info in enumerate(new_files):
        build_file_id = f"1A{next_build_id + i:021X}"
        file_ref_id = f"2A{next_file_ref_id + i:021X}"
        
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
    build_file_insertion = '\n'.join(build_file_entries) + '\n\t\t'
    content = re.sub(build_file_pattern, build_file_insertion + r'\1', content)
    
    # 2. Add to PBXFileReference section (before the End comment)
    file_ref_pattern = r'(/\* End PBXFileReference section \*/)'
    file_ref_insertion = '\n'.join(file_ref_entries) + '\n\t\t'
    content = re.sub(file_ref_pattern, file_ref_insertion + r'\1', content)
    
    # 3. Add to Sources build phase - find PBXSourcesBuildPhase
    # Look for the section that contains "Sources" and has "files = ("
    sources_build_pattern = r'(isa = PBXSourcesBuildPhase;.*?files = \(\s*\n)(.*?)(\s*\);)'
    
    def replace_sources(match):
        prefix = match.group(1)
        existing_sources = match.group(2)
        suffix = match.group(3)
        
        new_sources = '\n'.join(sources_entries)
        if existing_sources.strip():
            return prefix + existing_sources + '\n' + new_sources + suffix
        else:
            return prefix + new_sources + suffix
    
    content = re.sub(sources_build_pattern, replace_sources, content, flags=re.DOTALL)
    
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
    
    # Find existing frameworks
    existing_frameworks = set()
    framework_pattern = r'(\w{24}) /\* (.+?\.framework) in Frameworks \*/'
    matches = re.findall(framework_pattern, content)
    
    for match in matches:
        existing_frameworks.add(match[1])
    
    new_frameworks = [fw for fw in frameworks_needed if fw not in existing_frameworks]
    
    if not new_frameworks:
        print("All required frameworks are already linked")
        return content
        
    print(f"Adding {len(new_frameworks)} frameworks: {new_frameworks}")
    
    # Generate IDs for frameworks
    next_framework_id = int('000001000000000000100', 16) + 50  # Start well above existing IDs
    
    framework_build_entries = []
    framework_ref_entries = []
    framework_files_entries = []
    
    for i, framework in enumerate(new_frameworks):
        build_file_id = f"1A{next_framework_id + i:021X}"
        file_ref_id = f"2A{next_framework_id + i:021X}"
        
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
    build_file_pattern = r'(/\* End PBXBuildFile section \*/)'
    build_file_insertion = '\n'.join(framework_build_entries) + '\n\t\t'
    content = re.sub(build_file_pattern, build_file_insertion + r'\1', content)
    
    # Add framework file references
    file_ref_pattern = r'(/\* End PBXFileReference section \*/)'
    file_ref_insertion = '\n'.join(framework_ref_entries) + '\n\t\t'
    content = re.sub(file_ref_pattern, file_ref_insertion + r'\1', content)
    
    # Add to frameworks build phase
    frameworks_pattern = r'(isa = PBXFrameworksBuildPhase;.*?files = \(\s*\n)(.*?)(\s*\);)'
    
    def replace_frameworks(match):
        prefix = match.group(1)
        existing_frameworks = match.group(2) 
        suffix = match.group(3)
        
        new_fw_entries = '\n'.join(framework_files_entries)
        if existing_frameworks.strip():
            return prefix + existing_frameworks + '\n' + new_fw_entries + suffix
        else:
            return prefix + new_fw_entries + suffix
    
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