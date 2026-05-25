#!/bin/bash
cd "$(git rev-parse --show-toplevel)" || exit 1
echo "Getting epics..."
echo ""
echo ""

[ ! -d ".ccpm/initiatives" ] && echo "📁 No epics directory found. Create your first epic with: /pm:initiative-parse <feature-name>" && exit 0
[ -z "$(ls -d .ccpm/initiatives/*/ 2>/dev/null)" ] && echo "📁 No epics found. Create your first epic with: /pm:initiative-parse <feature-name>" && exit 0

echo "📚 Project Epics"
echo "================"
echo ""

# Initialize arrays to store epics by status
planning_epics=""
in_progress_epics=""
completed_epics=""

# Process all epics
for dir in .ccpm/initiatives/*/*/; do
  [ -d "$dir" ] || continue
  [ -f "$dir/epic.md" ] || continue

  # Extract metadata
  n=$(grep "^name:" "$dir/epic.md" | head -1 | sed 's/^name: *//')
  s=$(grep "^status:" "$dir/epic.md" | head -1 | sed 's/^status: *//' | tr '[:upper:]' '[:lower:]')
  p=$(grep "^progress:" "$dir/epic.md" | head -1 | sed 's/^progress: *//')
  g=$(grep "^github:" "$dir/epic.md" | head -1 | sed 's/^github: *//')

  # Defaults
  [ -z "$n" ] && n=$(basename "$dir")
  [ -z "$p" ] && p="0%"

  # Count tasks
  t=$(ls "$dir"/[0-9]*.md 2>/dev/null | wc -l)

  # Format output with GitHub issue number if available
  if [ -n "$g" ]; then
    i=$(echo "$g" | grep -o '/[0-9]*$' | tr -d '/')
    entry="   📋 ${dir}epic.md (#$i) - $p complete ($t tasks)"
  else
    entry="   📋 ${dir}epic.md - $p complete ($t tasks)"
  fi

  # Categorize by status (handle various status values)
  case "$s" in
    planning|draft|"")
      planning_epics="${planning_epics}${entry}\n"
      ;;
    in-progress|in_progress|active|started)
      in_progress_epics="${in_progress_epics}${entry}\n"
      ;;
    completed|complete|done|closed|finished)
      completed_epics="${completed_epics}${entry}\n"
      ;;
    *)
      # Default to planning for unknown statuses
      planning_epics="${planning_epics}${entry}\n"
      ;;
  esac
done

# Archived epics
archived_epics=""
for dir in .ccpm/archive/*/*/; do
  [ -d "$dir" ] || continue
  [ -f "$dir/epic.md" ] || continue

  n=$(grep "^name:" "$dir/epic.md" | head -1 | sed 's/^name: *//')
  p=$(grep "^progress:" "$dir/epic.md" | head -1 | sed 's/^progress: *//')
  [ -z "$n" ] && n=$(basename "$dir")
  [ -z "$p" ] && p="0%"
  t=$(ls "$dir"/[0-9]*.md 2>/dev/null | wc -l)

  archived_epics="${archived_epics}   📦 ${dir}epic.md [archived] - $p complete ($t tasks)\n"
done

# Display categorized epics
echo "📝 Planning:"
if [ -n "$planning_epics" ]; then
  echo -e "$planning_epics" | sed '/^$/d'
else
  echo "   (none)"
fi

echo ""
echo "🚀 In Progress:"
if [ -n "$in_progress_epics" ]; then
  echo -e "$in_progress_epics" | sed '/^$/d'
else
  echo "   (none)"
fi

echo ""
echo "✅ Completed:"
if [ -n "$completed_epics" ]; then
  echo -e "$completed_epics" | sed '/^$/d'
else
  echo "   (none)"
fi

echo ""
echo "📦 Archived:"
if [ -n "$archived_epics" ]; then
  echo -e "$archived_epics" | sed '/^$/d'
else
  echo "   (none)"
fi

# Summary
echo ""
echo "📊 Summary"
total=$(ls -d .ccpm/initiatives/*/ 2>/dev/null | wc -l)
tasks=$(find .ccpm/initiatives -name "[0-9]*.md" 2>/dev/null | wc -l)
echo "   Total epics: $total"
echo "   Total tasks: $tasks"
archived_total=$(ls -d .ccpm/archive/*/ 2>/dev/null | wc -l)
archived_tasks=$(find .ccpm/archive -name "[0-9]*.md" 2>/dev/null | wc -l)
echo "   Archived epics: $archived_total"
echo "   Archived tasks: $archived_tasks"

exit 0
