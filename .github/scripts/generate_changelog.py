import argparse
import subprocess
import re
import sys
import os

def run_command(shell_command):
    try:
        return subprocess.check_output(shell_command, shell=True, text=True).strip()
    except subprocess.CalledProcessError:
        return None

def get_last_stable_tag():
    # Matches logic: git tag -l | grep -v 'alpha' | tail -1
    tags = run_command("git tag -l")
    if not tags:
        return None
    stable_tags = [tag for tag in tags.splitlines() if 'alpha' not in tag.lower()]
    if not stable_tags:
        return None
    # Assuming tags are sorted or we rely on tail logic. 
    # git tag -l sorts alphabetically usually. 'tail -1' takes the last one.
    return stable_tags[-1]

def get_commits(from_ref, to_ref):
    print(f"Fetching commits from {from_ref} to {to_ref}...")
    # format: hash subject
    # We use %s (subject) to avoid body for now as per requirement summary.
    shell_command = f"git log {from_ref}..{to_ref} --format='%H %s'"
    output = run_command(shell_command)
    if not output:
        return []
    return output.splitlines()

def parse_commits(lines):
    groups = {
        "feat": [],
        "fix": [],
        "fix_ui": [],
        "perf": []
    }
    
    # Regex: type(scope): summary OR type: summary
    # Supports scopes with parens.
    # Capture: (type), (scope?), (summary)
    regex = r"^([a-z]+)(?:\(([^)]+)\))?:\s*(.+)$"
    
    for line in lines:
        parts = line.split(" ", 1)
        if len(parts) < 2:
            continue
        sha = parts[0]
        full_msg = parts[1]
        
        match = re.search(regex, full_msg)
        if match:
            commit_type = match.group(1)
            commit_scope = match.group(2)
            commit_summary = match.group(3)
            
            commit_data = {
                "sha": sha,
                "type": commit_type,
                "scope": commit_scope,
                "summary": commit_summary,
                "full_msg": full_msg
            }
            
            if commit_type == "feat":
                groups["feat"].append(commit_data)
            elif commit_type == "fix":
                if commit_scope and commit_scope.lower() == "ui":
                    groups["fix_ui"].append(commit_data)
                else:
                    groups["fix"].append(commit_data)
            elif commit_type == "perf":
                groups["perf"].append(commit_data)
            # Ignore other types (chore, refactor, etc) as requested
            
    return groups

def generate_markdown(groups):
    lines = []
    
    def add_section(header, key):
        commits = groups.get(key, [])
        if not commits:
            return
        
        lines.append(header)
        for commit_data in commits:
            # (sha commit) **type(<scope>):** (<user-facing summary>)
            short_sha = commit_data["sha"][:7]
            scope_str = f"({commit_data['scope']})" if commit_data['scope'] else ""
            lines.append(f"- {short_sha} **{commit_data['type']}{scope_str}:** {commit_data['summary']}")
        
        lines.append("\n---\n")

    add_section("## **New Features**", "feat")
    add_section("## **Bug Fixes**", "fix")
    add_section("### **UI Bug Fixes**", "fix_ui")
    add_section("## **Performance Improvements**", "perf")
    
    return "\n".join(lines).strip()

def generate_html(groups):
    lines = []
    repo_url = "https://github.com/TranPhuong319/AppLocker/commit/"
    
    def add_section(header_text, key):
        commits = groups.get(key, [])
        if not commits:
            return
        
        # Determine header level. Markdown used ## and ###.
        # Sparkle HTML usually uses h3 or strong.
        # User prompt showed: ## **New Features** in Markdown.
        # Original main.yml used <h3>The latest updates are:</h3>
        # I will use <h3> for main headers to be consistent with Sparkle styles often used.
        # For "UI Bug Fixes" (sub-header), I will use <h4> or just <b>
        
        # Mapping markdown styles to readable HTML
        tag = "h3"
        if "###" in header_text:
            tag = "h4"
        
        clean_header = header_text.replace("#", "").replace("*", "").strip()
        lines.append(f"<{tag}>{clean_header}</{tag}>")
        lines.append("<ul>")
        
        for commit_data in commits:
            short_sha = commit_data["sha"][:7]
            scope_str = f"({commit_data['scope']})" if commit_data['scope'] else ""
            
            # Link
            link = f'<a href="{repo_url}{commit_data["sha"]}"><tt>{short_sha}</tt></a>'
            # **type(scope):**
            bold_prefix = f"<b>{commit_data['type']}{scope_str}:</b>"
            
            lines.append(f"<li>{link} {bold_prefix} {commit_data['summary']}</li>")
            
        lines.append("</ul>")

    add_section("## **New Features**", "feat")
    add_section("## **Bug Fixes**", "fix")
    add_section("### **UI Bug Fixes**", "fix_ui")
    add_section("## **Performance Improvements**", "perf")
    
    return "\n".join(lines)

def get_current_branch():
    return run_command("git rev-parse --abbrev-ref HEAD")

def get_merge_base(branch, base="main"):
    return run_command(f"git merge-base {base} {branch}")

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--from-ref", dest="from_ref", help="Start commit/tag")
    parser.add_argument("--to-ref", dest="to_ref", default="HEAD", help="End commit/tag")
    parser.add_argument("--current-tag", dest="current_tag", help="Current release tag for display (e.g., v1.6.1)")
    args = parser.parse_args()
    
    from_ref = args.from_ref
    if not from_ref:
        current_branch = get_current_branch()
        if current_branch and current_branch != "main":
            print(f"Detected branch '{current_branch}'. Using merge-base with main.")
            from_ref = get_merge_base(current_branch, "main")
            if not from_ref:
                print("Merge-base not found, falling back to last stable tag.")
                from_ref = get_last_stable_tag()
        else:
            print("On main branch or branch detection failed. Finding last stable tag...")
            from_ref = get_last_stable_tag()
    
    if not from_ref:
        print("Error: Could not determine start reference.")
        sys.exit(1)

    commits = get_commits(from_ref, args.to_ref)
    groups = parse_commits(commits)
    
    # Calculate total significant changes
    total_changes = len(groups["feat"]) + len(groups["fix"]) + len(groups["fix_ui"]) + len(groups["perf"])
    has_changes = total_changes > 0
    
    # Output to GITHUB_OUTPUT for workflow conditional
    if 'GITHUB_OUTPUT' in os.environ:
        with open(os.environ['GITHUB_OUTPUT'], 'a') as output_file:
            output_file.write(f"HAS_CHANGES={'true' if has_changes else 'false'}\n")
    else:
        print(f"Total significant changes: {total_changes}")

    # Comparison link
    # Always use last stable tag for compare link (tag...tag format)
    base_url = "https://github.com/TranPhuong319/AppLocker/compare/"
    
    # Get last stable tag for display (e.g., v1.6.0)
    previous_stable_tag = get_last_stable_tag()
    display_from = previous_stable_tag if previous_stable_tag else (from_ref[:7] if len(from_ref) > 20 else from_ref)
    display_to = args.current_tag if args.current_tag else (args.to_ref[:7] if len(args.to_ref) > 20 else args.to_ref)
    
    # Build compare link: prefer tag...tag format
    link_from = previous_stable_tag if previous_stable_tag else from_ref
    link_to = args.current_tag if args.current_tag else args.to_ref
    compare_link = f"{base_url}{link_from}...{link_to}"
    
    md_footer = f"\n\n**See more changes: [{display_from}...{display_to}]({compare_link})**"
    html_footer = f'<p><b>See more changes: <a href="{compare_link}">{display_from}...{display_to}</a></b></p>'

    md_output = generate_markdown(groups)
    html_output = generate_html(groups)
    
    print("Writing ReleaseNotes.md...")
    with open("ReleaseNotes.md", "a") as changelog:
        # User requested specific header in MD?
        # "Latest Updates"
        changelog.write("# Latest Updates\n\n")
        changelog.write("---\n\n")
        if has_changes:
            changelog.write(md_output)
        else:
            changelog.write("*No significant changes in this version.*\n")
        changelog.write(md_footer)
        
    print("Writing changelog_body.html...")
    with open("changelog_body.html", "w") as changelog:
        if has_changes:
            changelog.write(html_output)
        else:
            changelog.write("<p><i>No significant changes in this version.</i></p>")
        changelog.write(html_footer)

if __name__ == "__main__":
    main()
