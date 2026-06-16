#!/usr/bin/env python3

import os
import re
import uuid

def generate_uuid():
    """Generate a random UUID for Xcode file references"""
    return str(uuid.uuid4()).upper().replace('-', '')[:24]

def find_swift_files():
    """Find all Swift files that should be in the project"""
    swift_files = []
    for root, dirs, files in os.walk('SmartEdge'):
        for file in files:
            if file.endswith('.swift'):
                full_path = os.path.join(root, file)
                swift_files.append(full_path)
    return sorted(swift_files)

def read_project_file():
    """Read the Xcode project file"""
    with open('SmartEdge.xcodeproj/project.pbxproj', 'r') as f:
        return f.read()

def get_existing_files(content):
    """Get files already in the project"""
    existing_files = set()
    # Find file references
    for match in re.finditer(r'([A-F0-9]{24}) /\* (.+\.swift)', content):
        filename = match.group(2)
        existing_files.add(filename)
    return existing_files

def add_files_to_project():
    """Add missing Swift files to Xcode project"""
    content = read_project_file()
    swift_files = find_swift_files()
    existing_files = get_existing_files(content)
    
    print(f"Found {len(swift_files)} Swift files")
    print(f"Project already contains {len(existing_files)} files")
    
    missing_files = []
    for filepath in swift_files:
        filename = os.path.basename(filepath)
        if filename not in existing_files:
            missing_files.append(filepath)
    
    if not missing_files:
        print("No missing files found!")
        return
    
    print(f"\nMissing files ({len(missing_files)}):")
    for filepath in missing_files:
        print(f"  {filepath}")
    
    # Find the Sources build phase
    sources_match = re.search(r'(\w+) /\* Sources \*/ = \{.*?files = \((.*?)\);', content, re.DOTALL)
    if not sources_match:
        print("Could not find Sources build phase!")
        return
    
    sources_phase_id = sources_match.group(1)
    current_files = sources_match.group(2)
    
    # Add file references section
    file_refs_section = []
    build_file_refs = []
    
    for filepath in missing_files:
        filename = os.path.basename(filepath)
        file_ref_id = generate_uuid()
        build_file_id = generate_uuid()
        
        # Add file reference
        file_refs_section.append(f"\t\t{file_ref_id} /* {filename} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {filepath}; sourceTree = \"<group>\"; }};")
        
        # Add build file reference
        build_file_refs.append(f"\t\t{build_file_id} /* {filename} in Sources */ = {{isa = PBXBuildFile; fileRef = {file_ref_id} /* {filename} */; }};")
        
        # Add to sources build phase
        current_files = current_files.strip()
        if not current_files.endswith(','):
            current_files += ','
        current_files += f"\n\t\t\t\t{build_file_id} /* {filename} in Sources */,"
    
    # Insert file references
    pbx_file_ref_start = content.find('/* Begin PBXFileReference section */')
    if pbx_file_ref_start != -1:
        insert_pos = content.find('\n', pbx_file_ref_start) + 1
        content = content[:insert_pos] + '\n'.join(file_refs_section) + '\n' + content[insert_pos:]
    
    # Insert build file references
    pbx_build_file_start = content.find('/* Begin PBXBuildFile section */')
    if pbx_build_file_start != -1:
        insert_pos = content.find('\n', pbx_build_file_start) + 1
        content = content[:insert_pos] + '\n'.join(build_file_refs) + '\n' + content[insert_pos:]
    
    # Update sources build phase
    updated_sources = f"{sources_phase_id} /* Sources */ = {{\n\t\t\tisa = PBXSourcesBuildPhase;\n\t\t\tbuildActionMask = 2147483647;\n\t\t\tfiles = ({current_files}\n\t\t\t);\n\t\t\trunOnlyForDeploymentPostprocessing = 0;\n\t\t}};"
    
    pattern = rf'{re.escape(sources_phase_id)} /\* Sources \*/ = \{{.*?\}};'
    content = re.sub(pattern, updated_sources, content, flags=re.DOTALL)
    
    # Write back to project file
    with open('SmartEdge.xcodeproj/project.pbxproj', 'w') as f:
        f.write(content)
    
    print(f"\nAdded {len(missing_files)} files to Xcode project")

if __name__ == "__main__":
    add_files_to_project()