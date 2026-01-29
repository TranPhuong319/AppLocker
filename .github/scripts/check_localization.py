import os
import sys
import json
import argparse
from pycountry import languages
from collections import defaultdict

def get_lang_name(code):
    if '-' in code:
        code = code.split('-')[0]
    # Handle specific edge cases or fallbacks if needed
    lang = languages.get(alpha_2=code)
    return lang.name if lang else code

def write_stats(file_path):
    print(f"Reading localization file: {file_path}")
    
    if not os.path.exists(file_path):
        raise FileNotFoundError(f"File not found: {file_path}")

    with open(file_path, 'r', encoding='utf-8') as file:
        data = json.load(file)

    if data.get("version") != "1.1":
        raise ValueError(f"Unsupported version: {data.get('version')}")

    strings = data.get("strings", {})
    localizations = defaultdict(int)

    for string in strings.values():
        if "localizations" in string:
            for lang_code in string["localizations"].keys():
                localizations[lang_code] += 1

    summary = ["## i18n Stats", "",
               "| Language | Code | Completion |",
               "| :-- | :-- | --: |"]

    total_strings = len(strings)
    if total_strings == 0:
        print("No strings found in localization file.")
        return

    # Sort languages by completion percentage descending
    sorted_langs = sorted(localizations.items(), key=lambda item: item[1], reverse=True)

    for lang_code, count in sorted_langs:
        completion = (count / total_strings) * 100
        summary.append(f"| {get_lang_name(lang_code)} | {lang_code} | {completion:.2f}% |")

    summary.extend(["",
                    f"- **Total Languages**: {len(localizations)}",
                    f"- **Total Strings**: {total_strings}"])

    # Output to GITHUB_STEP_SUMMARY if running in GitHub Actions
    if 'GITHUB_STEP_SUMMARY' in os.environ:
        with open(os.environ['GITHUB_STEP_SUMMARY'], 'a') as f:
            f.write('\n'.join(summary) + '\n')
    else:
        # Print to stdout for local testing
        print('\n'.join(summary))

def main():
    parser = argparse.ArgumentParser(description="Check localization statistics.")
    parser.add_argument("file", nargs="?", default="AppLocker/Resources/Localizable.xcstrings", help="Path to the .xcstrings file")
    args = parser.parse_args()

    try:
        write_stats(args.file)
    except Exception as e:
        print(f"::error::{str(e)}")
        sys.exit(1)

if __name__ == "__main__":
    main()
