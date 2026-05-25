#!/bin/bash
cd "$(git rev-parse --show-toplevel)" || exit 1

echo "Validating PM System..."
echo ""
echo ""

echo "🔍 Validating PM System"
echo "======================="
echo ""

errors=0
warnings=0

# Check directory structure
echo "📁 Directory Structure:"
[ -d ".ccpm" ] && echo "  ✅ .ccpm directory exists" || { echo "  ❌ .ccpm directory missing"; ((errors++)); }
[ -d ".ccpm/initiatives" ] && echo "  ✅ Initiatives directory exists" || echo "  ⚠️ Initiatives directory missing"
[ -d ".ccpm/archive" ] && echo "  ✅ Archive directory exists" || echo "  ℹ️  Archive directory not created yet"
echo ""

# Check for orphaned files
echo "🗂️ Data Integrity:"

# Check epics have epic.md files
for epic_dir in .ccpm/initiatives/*/*/; do
  [ -d "$epic_dir" ] || continue
  if [ ! -f "$epic_dir/epic.md" ]; then
    echo "  ⚠️ Missing epic.md in $(basename "$epic_dir")"
    ((warnings++))
  fi
done

for epic_dir in .ccpm/archive/*/*/; do
  [ -d "$epic_dir" ] || continue
  if [ ! -f "$epic_dir/epic.md" ]; then
    echo "  ⚠️ Missing epic.md in archived $(basename "$epic_dir")"
    ((warnings++))
  fi
done

# Check for tasks without epics
orphaned=$(find .ccpm -name "[0-9]*.md" -not -path ".ccpm/initiatives/*/*/*" 2>/dev/null | wc -l)
[ $orphaned -gt 0 ] && echo "  ⚠️ Found $orphaned orphaned task files" && ((warnings++))

# Check for broken references
echo ""
echo "🔗 Reference Check:"

for task_file in .ccpm/initiatives/*/*/[0-9]*.md; do
  [ -f "$task_file" ] || continue

  deps_line=$(grep "^depends_on:" "$task_file" | head -1)
  if [ -n "$deps_line" ]; then
    deps=$(echo "$deps_line" | sed 's/^depends_on: *//' | sed 's/^\[//' | sed 's/\]$//' | sed 's/,/ /g' | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')
    [ -z "$deps" ] && deps=""
  else
    deps=""
  fi
  if [ -n "$deps" ] && [ "$deps" != "depends_on:" ]; then
    epic_dir=$(dirname "$task_file")
    for dep in $deps; do
      if [ ! -f "$epic_dir/$dep.md" ]; then
        echo "  ⚠️ Task $(basename "$task_file" .md) references missing task: $dep"
        ((warnings++))
      fi
    done
  fi
done

for task_file in .ccpm/archive/*/*/[0-9]*.md; do
  [ -f "$task_file" ] || continue

  deps_line=$(grep "^depends_on:" "$task_file" | head -1)
  if [ -n "$deps_line" ]; then
    deps=$(echo "$deps_line" | sed 's/^depends_on: *//' | sed 's/^\[//' | sed 's/\]$//' | sed 's/,/ /g' | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')
    [ -z "$deps" ] && deps=""
  else
    deps=""
  fi
  if [ -n "$deps" ] && [ "$deps" != "depends_on:" ]; then
    epic_dir=$(dirname "$task_file")
    for dep in $deps; do
      if [ ! -f "$epic_dir/$dep.md" ]; then
        echo "  ⚠️ Archived task $(basename "$task_file" .md) references missing task: $dep"
        ((warnings++))
      fi
    done
  fi
done

if [ $warnings -eq 0 ] && [ $errors -eq 0 ]; then
  echo "  ✅ All references valid"
fi

# Check frontmatter
echo ""
echo "📝 Frontmatter Validation:"
invalid=0

for file in $(find .ccpm -name "*.md" 2>/dev/null); do
  if ! grep -q "^---" "$file"; then
    echo "  ⚠️ Missing frontmatter: $(basename "$file")"
    ((invalid++))
  fi
done

[ $invalid -eq 0 ] && echo "  ✅ All files have frontmatter"

# Summary
echo ""
echo "📊 Validation Summary:"
echo "  Errors: $errors"
echo "  Warnings: $warnings"
echo "  Invalid files: $invalid"

if [ $errors -eq 0 ] && [ $warnings -eq 0 ] && [ $invalid -eq 0 ]; then
  echo ""
  echo "✅ System is healthy!"
else
  echo ""
  echo "💡 Run /pm:clean to fix some issues automatically"
fi

exit 0
