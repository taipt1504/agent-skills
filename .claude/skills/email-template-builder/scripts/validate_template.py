#!/usr/bin/env python3
"""
Validate Mustache template syntax and placeholders.
Usage: python3 validate_template.py <template_file.html>
"""

import re
import sys
from pathlib import Path


def extract_placeholders(template_content):
    """Extract all {{placeholder}} from template."""
    pattern = r'\{\{(\w+(?:\.\w+)*)\}\}'
    matches = re.findall(pattern, template_content)
    return sorted(set(matches))


def validate_syntax(template_content):
    """Validate Mustache template syntax."""
    errors = []

    # Check for unmatched braces
    open_braces = template_content.count('{{')
    close_braces = template_content.count('}}')
    if open_braces != close_braces:
        errors.append(f"Unmatched braces: {open_braces} opening, {close_braces} closing")

    # Check for empty placeholders
    if re.search(r'\{\{\s*\}\}', template_content):
        errors.append("Found empty placeholders: {{}}")

    # Check for invalid placeholder names (must start with letter)
    invalid = re.findall(r'\{\{(\d[^}]*)\}\}', template_content)
    if invalid:
        errors.append(f"Invalid placeholder names (must start with letter): {invalid}")

    return errors


def validate_html(template_content):
    """Basic HTML validation."""
    errors = []

    # Check for common unclosed tags
    for tag in ['<div', '<p', '<span', '<a', '<img']:
        open_count = len(re.findall(f'{tag}[^>]*>', template_content))
        close_tag = tag.replace('<', '</').replace(' ', '>')
        close_count = len(re.findall(close_tag, template_content))

        if tag == '<img':  # img is self-closing, skip close tag check
            continue
        if tag == '<a' and open_count != close_count:
            errors.append(f"Mismatched {tag}...> tags")

    return errors


def main():
    if len(sys.argv) < 2:
        print("Usage: python3 validate_template.py <template_file.html>")
        sys.exit(1)

    template_path = Path(sys.argv[1])

    if not template_path.exists():
        print(f"Error: File not found: {template_path}")
        sys.exit(1)

    content = template_path.read_text()

    print(f"Validating: {template_path.name}")
    print("-" * 50)

    # Check syntax
    syntax_errors = validate_syntax(content)
    if syntax_errors:
        print("❌ Syntax Errors:")
        for error in syntax_errors:
            print(f"  - {error}")
    else:
        print("✓ Mustache syntax valid")

    # Check HTML
    html_errors = validate_html(content)
    if html_errors:
        print("⚠ HTML Issues:")
        for error in html_errors:
            print(f"  - {error}")
    else:
        print("✓ HTML structure looks good")

    # Extract placeholders
    placeholders = extract_placeholders(content)
    if placeholders:
        print(f"\n📋 Placeholders found ({len(placeholders)}):")
        for ph in placeholders:
            print(f"  - {{{{ {ph} }}}}")
    else:
        print("\n⚠ No placeholders found in template")

    # Summary
    total_errors = len(syntax_errors) + len(html_errors)
    if total_errors == 0:
        print("\n✅ Template validation passed!")
        return 0
    else:
        print(f"\n❌ Found {total_errors} issue(s)")
        return 1


if __name__ == '__main__':
    sys.exit(main())
