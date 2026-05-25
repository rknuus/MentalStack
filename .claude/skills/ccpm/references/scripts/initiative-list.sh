#!/bin/bash
cd "$(git rev-parse --show-toplevel)" || exit 1
# Check if Initiative directory exists
if [ ! -d ".ccpm/initiatives" ]; then
  echo "📁 No Initiative directory found. Create your first Initiative with: /pm:initiative-new <feature-name>"
  exit 0
fi

# Check for Initiative files
if ! ls .ccpm/initiatives/*.md >/dev/null 2>&1; then
  echo "📁 No Initiatives found. Create your first Initiative with: /pm:initiative-new <feature-name>"
  exit 0
fi

# Function to count epics and their statuses for an initiative
count_epics() {
  local init_name
  init_name=$(basename "$1" .md)
  local init_dir
  init_dir=$(dirname "$1")
  # If file is at top level (initiatives/foo.md), look in initiatives/foo/
  if [ "$(basename "$init_dir")" != "$init_name" ]; then
    init_dir="$init_dir/$init_name"
  fi
  local epic_total=0
  local epic_completed=0
  local epic_in_progress=0
  local epic_backlog=0

  if [ -d "$init_dir" ]; then
    for epic_file in "$init_dir"/*/epic.md; do
      [ -f "$epic_file" ] || continue
      ((epic_total++))
      local estatus
      estatus=$(grep "^status:" "$epic_file" | head -1 | sed 's/^status: *//')
      case "$estatus" in
        completed) ((epic_completed++)) ;;
        in-progress) ((epic_in_progress++)) ;;
        *) ((epic_backlog++)) ;;
      esac
    done
  fi

  if [ $epic_total -gt 0 ]; then
    echo "   Epics: $epic_total ($epic_completed completed, $epic_in_progress in-progress, $epic_backlog backlog)"
  fi
}

# Initialize counters
backlog_count=0
in_progress_count=0
implemented_count=0
total_count=0

echo "Getting Initiatives..."
echo ""
echo ""


echo "📋 Initiative List"
echo "==========="
echo ""

# Display by status groups
echo "🔍 Backlog Initiatives:"
for file in .ccpm/initiatives/*.md; do
  [ -f "$file" ] || continue
  status=$(grep "^status:" "$file" | head -1 | sed 's/^status: *//')
  if [ "$status" = "backlog" ] || [ "$status" = "draft" ] || [ -z "$status" ]; then
    desc=$(grep "^description:" "$file" | head -1 | sed 's/^description: *//')
    [ -z "$desc" ] && desc="No description"
    echo "   📋 $file - $desc"
    count_epics "$file"
    ((backlog_count++))
  fi
  ((total_count++))
done
[ $backlog_count -eq 0 ] && echo "   (none)"

echo ""
echo "🔄 In-Progress Initiatives:"
for file in .ccpm/initiatives/*.md; do
  [ -f "$file" ] || continue
  status=$(grep "^status:" "$file" | head -1 | sed 's/^status: *//')
  if [ "$status" = "in-progress" ] || [ "$status" = "active" ]; then
    desc=$(grep "^description:" "$file" | head -1 | sed 's/^description: *//')
    [ -z "$desc" ] && desc="No description"
    echo "   📋 $file - $desc"
    count_epics "$file"
    ((in_progress_count++))
  fi
done
[ $in_progress_count -eq 0 ] && echo "   (none)"

echo ""
echo "✅ Implemented Initiatives:"
for file in .ccpm/initiatives/*.md; do
  [ -f "$file" ] || continue
  status=$(grep "^status:" "$file" | head -1 | sed 's/^status: *//')
  if [ "$status" = "implemented" ] || [ "$status" = "completed" ] || [ "$status" = "complete" ] || [ "$status" = "done" ]; then
    desc=$(grep "^description:" "$file" | head -1 | sed 's/^description: *//')
    [ -z "$desc" ] && desc="No description"
    echo "   📋 $file - $desc"
    count_epics "$file"
    ((implemented_count++))
  fi
done
[ $implemented_count -eq 0 ] && echo "   (none)"

echo ""
echo "📦 Archived Initiatives:"
archived_count=0
for init_dir in .ccpm/archive/*/; do
  [ -d "$init_dir" ] || continue
  init_name=$(basename "$init_dir")
  file="$init_dir/$init_name.md"
  [ -f "$file" ] || continue
  desc=$(grep "^description:" "$file" | head -1 | sed 's/^description: *//')
  [ -z "$desc" ] && desc="No description"
  echo "   📦 $file [archived] - $desc"
  count_epics "$file"
  ((archived_count++))
done
[ $archived_count -eq 0 ] && echo "   (none)"

# Display summary
echo ""
echo "📊 Initiative Summary"
echo "   Total Initiatives: $total_count"
echo "   Backlog: $backlog_count"
echo "   In-Progress: $in_progress_count"
echo "   Implemented: $implemented_count"
echo "   Archived: $archived_count"

exit 0
