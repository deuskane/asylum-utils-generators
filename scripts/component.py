import os
import re
import sys
import fnmatch
import argparse


def matches_file_filter(filename, file_filter):
    if not file_filter:
        return True

    if any(char in file_filter for char in "*?[]"):
        return fnmatch.fnmatch(filename, file_filter)

    try:
        return re.fullmatch(file_filter, filename) is not None
    except re.error:
        return filename == file_filter


def create_vhdl_package(package_name, source_paths, package_path=None, file_filter=None, append=False):
    if not source_paths:
        source_paths = ["."]

    source_paths = [os.path.abspath(path) for path in source_paths]

    for source_path in source_paths:
        if not os.path.exists(source_path):
            raise FileNotFoundError(f"Path '{source_path}' don't exist.")

    print(f"Generate package '{package_name}' with source paths {source_paths}.")

    if package_path is None:
        package_path = source_paths[0]

    if os.path.splitext(package_path)[1].lower() == ".vhd":
        package_file_path = os.path.abspath(package_path)
        package_dir = os.path.dirname(package_file_path)
    else:
        package_dir = os.path.abspath(package_path)
        package_file_path = os.path.join(package_dir, f"{package_name}.vhd")

    os.makedirs(package_dir, exist_ok=True)

    print(f"* Write package to '{package_file_path}'.")

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

    component_declarations = []

    for source_path in source_paths:
        if os.path.isdir(source_path):
            if file_filter:
                print(f"* Scan files in \"{source_path}\" matching filter '{file_filter}'.")
            else:
                print(f"* Scan all file in \"{source_path}\".")

            for filename in sorted(os.listdir(source_path)):
                if not filename.endswith(".vhd") or filename == f"{package_name}.vhd":
                    continue

                if not matches_file_filter(filename, file_filter):
                    continue

                vhdl_file = os.path.join(source_path, filename)
                with open(vhdl_file, 'r') as file:
                    print(f"  * {vhdl_file}")
                    content = file.read()

                    pattern = re.compile(r'entity\s+(\w+)\s+is(.*?)end\s+(entity\s+)?\1\s*;', re.DOTALL | re.IGNORECASE)
                    matches = pattern.findall(content)

                    for entity_name, entity_body, _ in matches:
                        print(f"    * {entity_name}")
                        component_declarations.append(f"component {entity_name} is{entity_body}end component {entity_name};\n")
                        component_declarations.append("\n")
        elif os.path.isfile(source_path):
            filename = os.path.basename(source_path)
            if filename == f"{package_name}.vhd" or not filename.endswith(".vhd"):
                continue
            if not matches_file_filter(filename, file_filter):
                continue

            with open(source_path, 'r') as file:
                print(f"  * {source_path}")
                content = file.read()

                pattern = re.compile(r'entity\s+(\w+)\s+is(.*?)end\s+(entity\s+)?\1\s*;', re.DOTALL | re.IGNORECASE)
                matches = pattern.findall(content)

                for entity_name, entity_body, _ in matches:
                    print(f"    * {entity_name}")
                    component_declarations.append(f"component {entity_name} is{entity_body}end component {entity_name};\n")
                    component_declarations.append("\n")

    generated_content = "".join(component_declarations)

    print(f"* Update package content.")
    with open(package_file_path, 'r') as package_file:
        existing_content = package_file.read()

    if package_begin not in existing_content and package_end not in existing_content:
        existing_content = existing_content.replace(
            f"\nend {package_name};\n",
            f"\n{package_begin}{package_end}\n\nend {package_name};\n"
        )

    if append:
        print("* Append new component declarations to existing generated block.")
        block_match = re.search(
            re.escape(package_begin) + r'(.*?)' + re.escape(package_end),
            existing_content,
            flags=re.DOTALL
        )
        if block_match:
            existing_block_content = block_match.group(1)
            existing_entities = {
                entity.lower() for entity in re.findall(r'component\s+(\w+)\s+is', existing_block_content, flags=re.IGNORECASE)
            }
            new_component_declarations = []
            for declaration in component_declarations:
                entity_match = re.search(r'component\s+(\w+)\s+is', declaration, flags=re.IGNORECASE)
                if entity_match and entity_match.group(1).lower() in existing_entities:
                    continue
                new_component_declarations.append(declaration)

            generated_content = "".join(new_component_declarations)
            if generated_content:
                if existing_block_content and not existing_block_content.endswith("\n"):
                    existing_block_content += "\n"
                existing_block_content += generated_content
            else:
                existing_block_content = existing_block_content
            new_content = re.sub(
                re.escape(package_begin) + r'.*?' + re.escape(package_end),
                f"{package_begin}{existing_block_content}{package_end}",
                existing_content,
                flags=re.DOTALL
            )
        else:
            new_content = existing_content.replace(f"{package_begin}", f"{package_begin}{generated_content}")
    else:
        print("* Replace previous generated content.")
        new_content = re.sub(
            re.escape(package_begin) + r'.*?' + re.escape(package_end),
            f"{package_begin}{generated_content}{package_end}",
            existing_content,
            flags=re.DOTALL
        )

    with open(package_file_path, 'w') as package_file:
        package_file.write(new_content)
        
if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Generate VHDL Package with component.")
    parser.add_argument("package_name", type=str, help="Package Name.")
    parser.add_argument(
        "path",
        nargs="?",
        type=str,
        default=None,
        help="Path to the first VHDL file or directory (kept for backward compatibility)."
    )
    parser.add_argument(
        "--vhdl_path",
        action="append",
        default=[],
        help="Repeatable path to a VHDL file or directory. Can be used multiple times."
    )
    parser.add_argument(
        "--package_path",
        type=str,
        default=None,
        help="Path to the package output directory or .vhd file."
    )
    parser.add_argument(
        "--file_filter",
        type=str,
        default=None,
        help="Optional filename, glob pattern, or regex used to select VHDL files."
    )
    parser.add_argument(
        "-a",
        "--append",
        action="store_true",
        help="Append new component declarations to an existing generated block instead of replacing it."
    )
    
    args = parser.parse_args()

    source_paths = []
    if args.path:
        source_paths.append(args.path)
    source_paths.extend(args.vhdl_path)
    if not source_paths:
        source_paths = ["."]
    
    create_vhdl_package(args.package_name, source_paths, args.package_path, args.file_filter, args.append)
