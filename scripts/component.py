import os
import re
import sys
import argparse

def create_vhdl_package(package_name, path):
    # Create the directory if it doesn't exist

    if not os.path.exists(path):
        raise FileNotFoundError(f"Path '{path}' don't exist.")

    print(f"Generate package '{package_name}' with path '{path}'.")

    # Create the VHDL package file
    package_file_path = os.path.join(path, f"{package_name}.vhd")

    # Initialize package content
    package_begin    =  "-- [COMPONENT_INSERT][BEGIN]\n"
    package_end      =  "-- [COMPONENT_INSERT][END]\n"
    package_content  =  "library IEEE;\n"
    package_content +=  "use     IEEE.STD_LOGIC_1164.ALL;\n"
    package_content +=  "use     IEEE.NUMERIC_STD.ALL;\n\n"
    package_content += f"package {package_name} is\n"
    package_content += package_begin
    # Close the package declaration
    package_content += package_end
    package_content += f"\nend {package_name};\n"

    # Check if the file already exists
    if not os.path.exists(package_file_path):
        print(f"* Package '{package_name}' don't exist, create empty package.")

        # Write the package content to the file
        with open(package_file_path, 'w') as package_file:
            package_file.write(package_content)

    package_content = ""

    # Iterate through all VHDL files in the directory
    print(f"* Scan all file in \"{path}\".")
    for filename in sorted(os.listdir(path)):
        if filename.endswith(".vhd") and filename != f"{package_name}.vhd":
            with open(os.path.join(path, filename), 'r') as file:
                print(f"  * {os.path.join(path, filename)}")
                content = file.read()

                # Regular expression to find content between "entity" and "end entity"
                #pattern = re.compile(r'entity\s+.*?\s+is.*?end\s.*?;', re.DOTALL)
                pattern = re.compile(r'entity\s+(\w+)\s+is(.*?)end\s+(entity\s+)?\1\s*;', re.DOTALL | re.IGNORECASE)


                # Find all matches in the VHDL code
                matches = pattern.findall(content)

                for entity_name, entity_body, _ in matches:
                    print(f"    * {entity_name}")
                
                    package_content += f"component {entity_name} is{entity_body}end component {entity_name};\n"
                    package_content += "\n"

    print(f"* Delete previous content.")
    with open(package_file_path, 'r') as package_file:
        existing_content = package_file.read()

    # Remove old auto-generated content
    existing_content = re.sub(
        re.escape(package_begin) + r'.*?' + re.escape(package_end),
        f"{package_begin}{package_end}",
        existing_content,
        flags=re.DOTALL
    )

    # Insert new auto-generated content
    print(f"* Add new previous content.")
    new_content = existing_content.replace(f"{package_begin}", f"{package_begin}{package_content}")
    
    with open(package_file_path, 'w') as package_file:
        package_file.write(new_content)
        
if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Generate VHDL Package with component.")
    parser.add_argument("package_name", type=str, help="Package Name.")
    parser.add_argument("path",         type=str, help="Path to VHDL Files.")
    
    args = parser.parse_args()
    
    create_vhdl_package(args.package_name, args.path)
