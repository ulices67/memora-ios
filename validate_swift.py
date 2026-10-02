import os
import re
import sys

def check_swift_file(filepath):
    with open(filepath, 'r', encoding='utf-8') as f:
        content = f.read()

    lines = content.splitlines()
    errors = []

    # Check matching braces, brackets, parentheses
    stack = []
    in_string = False
    in_multiline_comment = False
    string_char = None
    escaped = False

    i = 0
    line_num = 1
    col_num = 1

    while i < len(content):
        ch = content[i]
        
        if ch == '\n':
            line_num += 1
            col_num = 1
            i += 1
            continue

        if in_multiline_comment:
            if ch == '*' and i + 1 < len(content) and content[i+1] == '/':
                in_multiline_comment = False
                i += 2
                col_num += 2
                continue
            i += 1
            col_num += 1
            continue

        if in_string:
            if escaped:
                escaped = False
            elif ch == '\\':
                escaped = True
            elif ch == string_char:
                in_string = False
            i += 1
            col_num += 1
            continue

        # Single line comment
        if ch == '/' and i + 1 < len(content) and content[i+1] == '/':
            # Skip until end of line
            while i < len(content) and content[i] != '\n':
                i += 1
            continue

        # Multiline comment
        if ch == '/' and i + 1 < len(content) and content[i+1] == '*':
            in_multiline_comment = True
            i += 2
            col_num += 2
            continue

        # String literal
        if ch in ('"',):
            in_string = True
            string_char = ch
            escaped = False
            i += 1
            col_num += 1
            continue

        if ch in ('{', '(', '['):
            stack.append((ch, line_num, col_num))
        elif ch in ('}', ')', ']'):
            if not stack:
                errors.append(f"Unexpected closing '{ch}' at line {line_num}:{col_num}")
            else:
                top, top_line, top_col = stack.pop()
                expected = {'{': '}', '(': ')', '[': ']'}[top]
                if ch != expected:
                    errors.append(f"Mismatched bracket: opened '{top}' at line {top_line}:{top_col}, closed with '{ch}' at line {line_num}:{col_num}")

        i += 1
        col_num += 1

    if stack:
        for top, top_line, top_col in stack:
            errors.append(f"Unclosed '{top}' opened at line {top_line}:{top_col}")

    return errors

def main():
    root = "."
    all_passed = True
    checked = 0
    for dirpath, _, filenames in os.walk(root):
        for f in filenames:
            if f.endswith(".swift"):
                full_path = os.path.join(dirpath, f)
                checked += 1
                errors = check_swift_file(full_path)
                if errors:
                    print(f"[FAIL] {full_path}")
                    for e in errors:
                        print(f"   {e}")
                    all_passed = False
                else:
                    print(f"[PASS] {full_path}")

    print(f"\nTotal Swift files verified: {checked}")
    if not all_passed:
        sys.exit(1)
    else:
        print("ALL SWIFT FILES HAVE PERFECT BALANCE & SYNTAX!")

if __name__ == "__main__":
    main()
