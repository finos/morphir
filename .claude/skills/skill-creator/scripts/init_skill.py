#!/usr/bin/env python3
"""
Skill Initializer - Creates a new skill from a standardized template

Usage:
    python scripts/init_skill.py <skill-name> --path <output-directory>

Example:
    python scripts/init_skill.py my-skill --path .claude/skills
    python scripts/init_skill.py pdf-editor --path ~/.claude/skills
"""

import argparse
import sys
from pathlib import Path

# Template for SKILL.md
SKILL_MD_TEMPLATE = '''---
name: {skill_name}
description: TODO - Describe what this skill does and when it should be used. Include specific triggers and contexts.
---

# {skill_title}

TODO: Write the main instructions for this skill.

## Overview

TODO: Describe the skill's purpose and capabilities.

## Usage

TODO: Document how to use this skill.

## Resources

This skill includes the following resources:

- **scripts/**: Executable scripts for automation
- **references/**: Documentation and reference materials
- **assets/**: Templates and files for output

## Workflow

TODO: Document the typical workflow when using this skill.

1. Step one
2. Step two
3. Step three
'''

# Example script template
EXAMPLE_SCRIPT = '''#!/usr/bin/env python3
"""
Example script for {skill_name}

TODO: Replace this with your actual script implementation.
"""

import sys

def main():
    print("Hello from {skill_name}!")
    # TODO: Add your script logic here

if __name__ == "__main__":
    main()
'''

# Example reference template
EXAMPLE_REFERENCE = '''# Reference Documentation

TODO: Add reference documentation for the skill here.

## Overview

This file contains reference information that Claude can load when needed.

## Details

Add detailed information, schemas, API documentation, or other reference material here.
'''


def create_skill(skill_name: str, output_path: Path) -> bool:
    """
    Create a new skill directory with template files.

    Args:
        skill_name: Name of the skill (hyphen-case)
        output_path: Directory where the skill folder will be created

    Returns:
        True if successful, False otherwise
    """
    # Validate skill name
    if not skill_name:
        print("❌ Error: Skill name cannot be empty")
        return False

    # Convert to hyphen-case if needed
    skill_name = skill_name.lower().replace('_', '-').replace(' ', '-')

    # Create skill directory path
    skill_dir = output_path / skill_name

    # Check if skill already exists
    if skill_dir.exists():
        print(f"❌ Error: Skill directory already exists: {skill_dir}")
        return False

    try:
        # Create directory structure
        skill_dir.mkdir(parents=True, exist_ok=True)
        (skill_dir / "scripts").mkdir(exist_ok=True)
        (skill_dir / "references").mkdir(exist_ok=True)
        (skill_dir / "assets").mkdir(exist_ok=True)

        print(f"✅ Created skill directory: {skill_dir}")

        # Create SKILL.md
        skill_title = skill_name.replace('-', ' ').title()
        skill_md_content = SKILL_MD_TEMPLATE.format(
            skill_name=skill_name,
            skill_title=skill_title
        )
        (skill_dir / "SKILL.md").write_text(skill_md_content)
        print(f"✅ Created SKILL.md")

        # Create example script
        example_script_content = EXAMPLE_SCRIPT.format(skill_name=skill_name)
        example_script_path = skill_dir / "scripts" / "example.py"
        example_script_path.write_text(example_script_content)
        example_script_path.chmod(0o755)
        print(f"✅ Created scripts/example.py")

        # Create example reference
        example_ref_content = EXAMPLE_REFERENCE
        (skill_dir / "references" / "reference.md").write_text(example_ref_content)
        print(f"✅ Created references/reference.md")

        # Create .gitkeep in assets (often empty initially)
        (skill_dir / "assets" / ".gitkeep").write_text("")
        print(f"✅ Created assets/.gitkeep")

        print(f"\n🎉 Successfully initialized skill: {skill_name}")
        print(f"   Location: {skill_dir}")
        print("\nNext steps:")
        print("1. Edit SKILL.md to add your skill's description and instructions")
        print("2. Add scripts, references, and assets as needed")
        print("3. Delete any example files you don't need")
        print("4. Test your skill with Claude")
        print("5. Package with: python scripts/package_skill.py <skill-path>")

        return True

    except Exception as e:
        print(f"❌ Error creating skill: {e}")
        return False


def main():
    parser = argparse.ArgumentParser(
        description="Initialize a new Claude skill from template",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
    python scripts/init_skill.py my-skill --path .claude/skills
    python scripts/init_skill.py pdf-editor --path ~/.claude/skills
    python scripts/init_skill.py code-reviewer --path /path/to/skills
        """
    )

    parser.add_argument(
        "skill_name",
        help="Name of the skill to create (use hyphen-case, e.g., 'my-skill')"
    )
    parser.add_argument(
        "--path",
        required=True,
        help="Output directory where the skill folder will be created"
    )

    args = parser.parse_args()

    output_path = Path(args.path).resolve()

    # Ensure output path exists
    if not output_path.exists():
        try:
            output_path.mkdir(parents=True, exist_ok=True)
            print(f"📁 Created output directory: {output_path}")
        except Exception as e:
            print(f"❌ Error creating output directory: {e}")
            sys.exit(1)

    if not output_path.is_dir():
        print(f"❌ Error: Path is not a directory: {output_path}")
        sys.exit(1)

    print(f"🚀 Initializing skill: {args.skill_name}")
    print(f"   Output path: {output_path}\n")

    success = create_skill(args.skill_name, output_path)
    sys.exit(0 if success else 1)


if __name__ == "__main__":
    main()
