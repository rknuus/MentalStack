#!/bin/bash
cd "$(git rev-parse --show-toplevel)" || exit 1

echo "📅 Daily Standup - $(date '+%Y-%m-%d')"
echo "================================"
echo ""

today=$(date '+%Y-%m-%d')

echo "Getting status..."
echo ""
echo ""

echo "📝 Today's Activity:"
echo "===================="
echo ""

# Find files modified today
recent_files=$(find .ccpm -name "*.md" -mtime -1 2>/dev/null)

if [ -n "$recent_files" ]; then
  # Count by type
  initiative_count=$(echo "$recent_files" | grep -c "^\.ccpm/initiatives/[^/]*\.md$" 2>/dev/null | tr -d '[:space:]')
  epic_count=$(echo "$recent_files" | grep -c "/epic.md" 2>/dev/null | tr -d '[:space:]')
  task_count=$(echo "$recent_files" | grep -c "/[0-9]*.md" 2>/dev/null | tr -d '[:space:]')
  update_count=$(echo "$recent_files" | grep -c "/updates/" 2>/dev/null | tr -d '[:space:]')
  initiative_count=${initiative_count:-0}; epic_count=${epic_count:-0}; task_count=${task_count:-0}; update_count=${update_count:-0}

  [ "$initiative_count" -gt 0 ] && echo "  • Modified $initiative_count Initiative(s)"
  [ "$epic_count" -gt 0 ] && echo "  • Updated $epic_count epic(s)"
  [ "$task_count" -gt 0 ] && echo "  • Worked on $task_count task(s)"
  [ "$update_count" -gt 0 ] && echo "  • Posted $update_count progress update(s)"
else
  echo "  No activity recorded today"
fi

echo ""
echo "🔄 Currently In Progress:"
# Show active work items
for updates_dir in .ccpm/initiatives/*/*/updates/*/; do
  [ -d "$updates_dir" ] || continue
  if [ -f "$updates_dir/progress.md" ]; then
    issue_num=$(basename "$updates_dir")
    epic_name=$(basename $(dirname $(dirname "$updates_dir")))
    completion=$(grep "^completion:" "$updates_dir/progress.md" | head -1 | sed 's/^completion: *//')
    echo "  • Issue #$issue_num ($epic_name) - ${completion:-0%} complete"
  fi
done

echo ""
echo "⏭️ Next Available Tasks:"
# Show top 3 available tasks
count=0
for epic_dir in .ccpm/initiatives/*/*/; do
  [ -d "$epic_dir" ] || continue
  for task_file in "$epic_dir"/[0-9]*.md; do
    [ -f "$task_file" ] || continue
    status=$(grep "^status:" "$task_file" | head -1 | sed 's/^status: *//')
    if [ "$status" != "open" ] && [ -n "$status" ]; then
      continue
    fi

    deps_line=$(grep "^depends_on:" "$task_file" | head -1)
    if [ -n "$deps_line" ]; then
      deps=$(echo "$deps_line" | sed 's/^depends_on: *//' | sed 's/^\[//' | sed 's/\]$//' | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')
      [ -z "$deps" ] && deps=""
    else
      deps=""
    fi
    if [ -z "$deps" ] || [ "$deps" = "depends_on:" ]; then
      task_name=$(grep "^name:" "$task_file" | head -1 | sed 's/^name: *//')
      task_num=$(basename "$task_file" .md)
      echo "  • #$task_num - $task_name"
      ((count++))
      [ $count -ge 3 ] && break 2
    fi
  done
done

echo ""
echo "📊 Quick Stats:"
init_tasks=$(find .ccpm/initiatives -name "[0-9]*.md" 2>/dev/null | wc -l)
archive_tasks=$(find .ccpm/archive -name "[0-9]*.md" 2>/dev/null | wc -l)
total_tasks=$((init_tasks + archive_tasks))
open_tasks=$(find .ccpm/initiatives -name "[0-9]*.md" 2>/dev/null | xargs grep -l "^status: *open" 2>/dev/null | wc -l)
closed_init=$(find .ccpm/initiatives -name "[0-9]*.md" 2>/dev/null | xargs grep -l "^status: *closed" 2>/dev/null | wc -l)
closed_archive=$(find .ccpm/archive -name "[0-9]*.md" 2>/dev/null | xargs grep -l "^status: *closed" 2>/dev/null | wc -l)
closed_tasks=$((closed_init + closed_archive))
echo "  Tasks: $open_tasks open, $closed_tasks closed, $total_tasks total ($archive_tasks archived)"

exit 0
