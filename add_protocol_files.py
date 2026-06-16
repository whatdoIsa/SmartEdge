#!/usr/bin/env python3

import re
import uuid

def generate_uuid():
    return str(uuid.uuid4()).upper().replace('-', '')[:24]

def add_protocol_files_to_xcode_project():
    project_path = '/Users/dean_ssong/Desktop/SmartEdge/SmartEdge.xcodeproj/project.pbxproj'
    
    with open(project_path, 'r') as f:
        content = f.read()
    
    protocol_files = [
        'NotchCoordinatorProtocol.swift',
        'SystemHUDServiceProtocol.swift'
    ]
    
    # Generate UUIDs for each file
    file_data = []
    for filename in protocol_files:
        file_ref_id = generate_uuid()
        build_file_id = generate_uuid()
        filepath = f'SmartEdge/Core/Protocols/{filename}'
        
        file_data.append({
            'filename': filename,
            'filepath': filepath,
            'file_ref_id': file_ref_id,
            'build_file_id': build_file_id
        })
    
    # Add file references to PBXFileReference section
    pbx_file_ref_start = content.find('/* Begin PBXFileReference section */')
    if pbx_file_ref_start != -1:
        insert_pos = content.find('\n', pbx_file_ref_start) + 1
        file_ref_lines = ""
        for data in file_data:
            file_ref_lines += f'\t\t{data["file_ref_id"]} /* {data["filename"]} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = "{data["filepath"]}"; sourceTree = "<group>"; }};\n'
        content = content[:insert_pos] + file_ref_lines + content[insert_pos:]
    
    # Add build file references to PBXBuildFile section
    pbx_build_file_start = content.find('/* Begin PBXBuildFile section */')
    if pbx_build_file_start != -1:
        insert_pos = content.find('\n', pbx_build_file_start) + 1
        build_file_lines = ""
        for data in file_data:
            build_file_lines += f'\t\t{data["build_file_id"]} /* {data["filename"]} in Sources */ = {{isa = PBXBuildFile; fileRef = {data["file_ref_id"]} /* {data["filename"]} */; }};\n'
        content = content[:insert_pos] + build_file_lines + content[insert_pos:]
    
    # Find and add to Sources build phase
    sources_match = re.search(r'(\w+) /\* Sources \*/ = \{.*?files = \((.*?)\);', content, re.DOTALL)
    if sources_match:
        sources_phase_id = sources_match.group(1)
        current_files = sources_match.group(2).strip()
        
        # Add our build files to the sources
        if current_files and not current_files.endswith(','):
            current_files += ','
        
        for data in file_data:
            current_files += f'\n\t\t\t\t{data["build_file_id"]} /* {data["filename"]} in Sources */,'
        
        # Reconstruct the sources phase
        updated_sources = f'{sources_phase_id} /* Sources */ = {{\n\t\t\tisa = PBXSourcesBuildPhase;\n\t\t\tbuildActionMask = 2147483647;\n\t\t\tfiles = ({current_files}\n\t\t\t);\n\t\t\trunOnlyForDeploymentPostprocessing = 0;\n\t\t}};'
        
        # Replace the old sources section
        pattern = rf'{re.escape(sources_phase_id)} /\* Sources \*/ = \{{.*?\}};'
        content = re.sub(pattern, updated_sources, content, flags=re.DOTALL)
    
    # Write the updated project file
    with open(project_path, 'w') as f:
        f.write(content)
    
    print(f'Successfully added {len(protocol_files)} protocol files to Xcode project')

if __name__ == '__main__':
    add_protocol_files_to_xcode_project()