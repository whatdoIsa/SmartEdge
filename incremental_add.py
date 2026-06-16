#!/usr/bin/env python3

import os
import re
import subprocess

def read_project_file(project_path):
    """Read the Xcode project file"""
    with open(project_path, 'r') as f:
        return f.read()

def get_next_ids(content):
    """Get the next available IDs for build files and file references"""
    
    # Find all build file IDs starting with 1A
    build_file_pattern = r'(1A\w{21}) /\*.*?\*/ = \{isa = PBXBuildFile;'
    build_ids = []
    for match in re.findall(build_file_pattern, content):
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

def find_existing_files(content):
    """Find existing file references in project"""
    existing_files = set()
    
    # Find file references - looking for any .swift files
    file_ref_pattern = r'/\* (.+?\.swift) \*/ = \{isa = PBXFileReference;'
    matches = re.findall(file_ref_pattern, content)
    
    for match in matches:
        existing_files.add(match)  # Add filename
    
    return existing_files

def add_single_file(content, file_path, target_dir):
    """Add a single Swift file to the project"""
    
    filename = os.path.basename(file_path)
    relative_path = os.path.relpath(file_path, target_dir)
    
    # Check if file already exists
    existing_files = find_existing_files(content)
    if filename in existing_files:
        print(f"  {filename} already in project")
        return content, False
    
    next_build_id, next_file_ref_id = get_next_ids(content)
    
    build_file_id = f"{next_build_id:024X}"
    file_ref_id = f"{next_file_ref_id:024X}"
    
    # Build file entry
    build_file_entry = f"\t\t{build_file_id} /* {filename} in Sources */ = {{isa = PBXBuildFile; fileRef = {file_ref_id} /* {filename} */; }};"
    
    # File reference entry
    file_ref_entry = f"\t\t{file_ref_id} /* {filename} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = \"{relative_path}\"; sourceTree = \"<group>\"; }};"
    
    # Sources entry
    sources_entry = f"\t\t\t\t{build_file_id} /* {filename} in Sources */,"
    
    # Add to PBXBuildFile section
    build_file_pattern = r'(/\* End PBXBuildFile section \*/)'
    content = re.sub(build_file_pattern, build_file_entry + '\n\t\t' + r'\1', content)
    
    # Add to PBXFileReference section
    file_ref_pattern = r'(/\* End PBXFileReference section \*/)'
    content = re.sub(file_ref_pattern, file_ref_entry + '\n\t\t' + r'\1', content)
    
    # Add to Sources build phase
    sources_pattern = r'(\w+) /\* Sources \*/ = \{(\s+isa = PBXSourcesBuildPhase;.*?files = \(\s*\n)(.*?)(\s*\);.*?\};)'
    
    def replace_sources(match):
        section_id = match.group(1)
        prefix = match.group(2)
        existing_sources = match.group(3)
        suffix = match.group(4)
        
        if existing_sources.strip():
            return section_id + ' /* Sources */ = {' + prefix + existing_sources + '\n' + sources_entry + suffix
        else:
            return section_id + ' /* Sources */ = {' + prefix + sources_entry + suffix
    
    content = re.sub(sources_pattern, replace_sources, content, flags=re.DOTALL)
    
    print(f"  Added {filename}")
    return content, True

def test_build(project_file):
    """Test if the project builds successfully"""
    try:
        result = subprocess.run([
            'xcodebuild', '-project', 'SmartEdge.xcodeproj', '-scheme', 'SmartEdge', 
            '-configuration', 'Debug', 'build', '-quiet'
        ], cwd=os.path.dirname(project_file), capture_output=True, text=True, timeout=60)
        return result.returncode == 0, result.stderr
    except subprocess.TimeoutExpired:
        return False, "Build timeout"
    except Exception as e:
        return False, str(e)

def main():
    project_dir = "/Users/dean_ssong/Desktop/SmartEdge"
    target_dir = os.path.join(project_dir, "SmartEdge")
    project_file = os.path.join(project_dir, "SmartEdge.xcodeproj", "project.pbxproj")
    
    # Priority order for adding files - start with most fundamental dependencies
    priority_files = [
        # Core Protocols first
        "Core/Protocols/MediaServiceProtocol.swift",
        "Core/Protocols/CalendarServiceProtocol.swift", 
        "Core/Protocols/BatteryServiceProtocol.swift",
        "Core/Protocols/BluetoothServiceProtocol.swift",
        "Core/Protocols/ShelfServiceProtocol.swift",
        "Core/Protocols/NotchWindowProtocol.swift",
        "Core/Protocols/AppCoordinatorProtocol.swift",
        
        # Models next
        "Features/Notch/Models/NotchModels.swift",
        "Shared/Models/MediaModels.swift",
        "Shared/Models/CalendarModels.swift",
        "Shared/Models/SystemStatusModels.swift",
        "Shared/Models/ShelfModels.swift",
        
        # ViewModels
        "Features/Settings/SettingsViewModel.swift",
        "Features/Notch/NotchViewModel.swift",
        "Features/MusicPlayer/MusicPlayerViewModel.swift",
        
        # Essential Services
        "Core/Services/MediaService.swift",
        "Core/Services/BatteryService.swift",
        "Core/Services/BluetoothService.swift",
    ]
    
    print("Starting incremental file addition...")
    
    content = read_project_file(project_file)
    
    for relative_file_path in priority_files:
        full_file_path = os.path.join(target_dir, relative_file_path)
        if os.path.exists(full_file_path):
            print(f"\nAdding {relative_file_path}...")
            content, added = add_single_file(content, full_file_path, target_dir)
            
            if added:
                # Write updated project file
                with open(project_file, 'w') as f:
                    f.write(content)
                
                # Test build
                print("  Testing build...")
                success, error = test_build(project_file)
                if success:
                    print("  ✅ Build successful")
                else:
                    print("  ❌ Build failed")
                    print(f"  Error: {error[:200]}...")
                    # Continue anyway for now
            
        else:
            print(f"  ⚠️  File not found: {relative_file_path}")
    
    print(f"\nIncremental addition complete!")
    
    # Final build test
    print("\nFinal build test...")
    success, error = test_build(project_file)
    if success:
        print("🎉 Final build successful!")
    else:
        print("❌ Final build failed")
        print(f"Error: {error[:400]}...")

if __name__ == "__main__":
    main()