#!/usr/bin/env python3

import os
import sys
import hashlib
import re

def generate_xcode_id(file_path):
    """Generate a unique 24-character hex ID for Xcode project"""
    hash_object = hashlib.md5(file_path.encode())
    hex_dig = hash_object.hexdigest().upper()
    return hex_dig[:24]

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
    return swift_files

def read_project_file(project_path):
    """Read the Xcode project file"""
    with open(project_path, 'r') as f:
        return f.read()

def find_existing_files(content):
    """Find existing file references in project"""
    existing_files = set()
    
    # Find file references
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
    
    # Generate IDs for new files
    build_file_id_start = int('1A000001000000000000014', 16)  # Start after existing IDs
    file_ref_id_start = int('2A000001000000000000014', 16)
    
    build_file_entries = []
    file_ref_entries = []
    sources_entries = []
    
    for i, file_info in enumerate(new_files):
        build_file_id = f"{build_file_id_start + i:024X}"
        file_ref_id = f"{file_ref_id_start + i:024X}"
        
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
    
    # Find insertion points and add entries
    
    # 1. Add to PBXBuildFile section
    build_file_end_pattern = r'(/\* End PBXBuildFile section \*/)'
    build_file_insertion = '\n'.join(build_file_entries) + '\n'
    content = re.sub(build_file_end_pattern, build_file_insertion + r'\1', content)
    
    # 2. Add to PBXFileReference section  
    file_ref_end_pattern = r'(/\* End PBXFileReference section \*/)'
    file_ref_insertion = '\n'.join(file_ref_entries) + '\n'
    content = re.sub(file_ref_end_pattern, file_ref_insertion + r'\1', content)
    
    # 3. Add to Sources build phase
    sources_pattern = r'(files = \(\s*\n)(.*?)(\s*\);)'
    def replace_sources(match):
        prefix = match.group(1)
        existing_sources = match.group(2)
        suffix = match.group(3)
        
        new_sources = '\n'.join(sources_entries)
        if existing_sources.strip():
            return prefix + existing_sources + '\n' + new_sources + suffix
        else:
            return prefix + new_sources + suffix
    
    content = re.sub(sources_pattern, replace_sources, content, flags=re.DOTALL)
    
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
    
    print("Updating project file...")
    updated_content = add_files_to_project(content, swift_files)
    
    # Write updated project file
    with open(project_file, 'w') as f:
        f.write(updated_content)
    
    print("Project file updated successfully!")
    print(f"Added {len([f for f in swift_files if f['filename'] not in find_existing_files(content)])} new Swift files")

if __name__ == "__main__":
    main()