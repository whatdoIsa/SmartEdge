#!/usr/bin/env python3
"""
Remove duplicate build file references from Xcode project
"""
import re

def cleanup_duplicates():
    project_file = '/Users/dean_ssong/Desktop/SmartEdge/SmartEdge.xcodeproj/project.pbxproj'
    
    with open(project_file, 'r') as f:
        content = f.read()
    
    # Find the Sources build phase section
    sources_pattern = r'([\w\d]+) /\* Sources \*/ = \{[^}]*?files = \((.*?)\)[^}]*?\};'
    sources_match = re.search(sources_pattern, content, re.DOTALL)
    
    if sources_match:
        sources_phase_id = sources_match.group(1)
        files_section = sources_match.group(2)
        
        # Extract all build file references
        file_refs = re.findall(r'([\w\d]+) /\* [^*]+ in Sources \*/,?', files_section)
        
        # Remove duplicates while preserving order
        seen = set()
        unique_refs = []
        for ref in file_refs:
            if ref not in seen:
                seen.add(ref)
                unique_refs.append(ref)
        
        print(f"Removed {len(file_refs) - len(unique_refs)} duplicate file references")
        
        # Reconstruct the files section
        new_files_section = ""
        for ref in unique_refs:
            # Find the full line with the comment
            ref_pattern = rf'({ref} /\* [^*]+ in Sources \*/),?'
            ref_match = re.search(ref_pattern, files_section)
            if ref_match:
                new_files_section += f"\t\t\t\t{ref_match.group(1)},\n"
        
        # Remove trailing comma
        new_files_section = new_files_section.rstrip(',\n') + '\n'
        
        # Replace the sources section
        new_sources_section = f'''{sources_phase_id} /* Sources */ = {{
\t\t\tisa = PBXSourcesBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
{new_files_section}\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};'''
        
        # Replace in content
        content = re.sub(sources_pattern, new_sources_section, content, flags=re.DOTALL)
        
        # Write back to file
        with open(project_file, 'w') as f:
            f.write(content)
        
        print("Successfully cleaned up duplicate build file references")
    else:
        print("Could not find Sources build phase")

if __name__ == "__main__":
    cleanup_duplicates()
