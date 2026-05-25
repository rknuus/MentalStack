#!/bin/bash
cd "$(git rev-parse --show-toplevel)" || exit 1

echo "📄 Initiative Status Report"
echo "===================="
echo ""

if [ ! -d ".ccpm/initiatives" ]; then
  echo "No Initiative directory found."
  exit 0
fi

total=$(ls .ccpm/initiatives/*.md 2>/dev/null | wc -l)
[ "$total" -eq 0 ] && echo "No Initiatives found." && exit 0

# Count by status
backlog=0
in_progress=0
implemented=0

for file in .ccpm/initiatives/*.md; do
  [ -f "$file" ] || continue
  status=$(grep "^status:" "$file" | head -1 | sed 's/^status: *//')

  case "$status" in
    backlog|draft|"") ((backlog++)) ;;
    in-progress|active) ((in_progress++)) ;;
    implemented|completed|complete|done) ((implemented++)) ;;
    *) ((backlog++)) ;;
  esac
done

archived=0
for init_dir in .ccpm/archive/*/; do
  [ -d "$init_dir" ] || continue
  ((archived++))
done
total=$((total + archived))

echo "Getting status..."
echo ""
echo ""

# Display chart
echo "📊 Distribution:"
echo "================"

echo ""
if [ "$total" -gt 0 ]; then
  echo "  Backlog:     $(printf '%-3d' $backlog) [$(printf '%0.s█' $(seq 1 $((backlog*20/total))) 2>/dev/null)]"
  echo "  In Progress: $(printf '%-3d' $in_progress) [$(printf '%0.s█' $(seq 1 $((in_progress*20/total))) 2>/dev/null)]"
  echo "  Implemented: $(printf '%-3d' $implemented) [$(printf '%0.s█' $(seq 1 $((implemented*20/total))) 2>/dev/null)]"
  echo "  Archived:    $(printf '%-3d' $archived) [$(printf '%0.s█' $(seq 1 $((archived*20/total))) 2>/dev/null)]"
fi
echo ""
echo "  Total Initiatives: $total"

# Epic breakdown per initiative
echo ""
echo "📦 Epic Breakdown:"
for file in .ccpm/initiatives/*.md; do
  [ -f "$file" ] || continue
  init_name=$(basename "$file" .md)
  init_dir=".ccpm/initiatives/$init_name"

  name=$(grep "^name:" "$file" | head -1 | sed 's/^name: *//')
  [ -z "$name" ] && name="$init_name"

  echo "  Initiative: $name"

  if [ ! -d "$init_dir" ]; then
    echo "    (no epics)"
    continue
  fi

  epic_found=false
  for epic_file in "$init_dir"/*/epic.md; do
    [ -f "$epic_file" ] || continue
    epic_found=true
    epic_name=$(grep "^name:" "$epic_file" | head -1 | sed 's/^name: *//')
    [ -z "$epic_name" ] && epic_name=$(basename "$(dirname "$epic_file")")
    epic_status=$(grep "^status:" "$epic_file" | head -1 | sed 's/^status: *//')
    epic_progress=$(grep "^progress:" "$epic_file" | head -1 | sed 's/^progress: *//')
    [ -z "$epic_status" ] && epic_status="backlog"
    [ -z "$epic_progress" ] && epic_progress="0%"

    case "$epic_status" in
      completed) echo "    ✅ $epic_name ($epic_status, $epic_progress)" ;;
      in-progress) echo "    🔄 $epic_name ($epic_status, $epic_progress)" ;;
      *) echo "    📋 $epic_name ($epic_status, $epic_progress)" ;;
    esac
  done

  if [ "$epic_found" = false ]; then
    echo "    (no epics)"
  fi
done

for init_dir in .ccpm/archive/*/; do
  [ -d "$init_dir" ] || continue
  init_name=$(basename "$init_dir")
  file="$init_dir/$init_name.md"

  name="$init_name"
  if [ -f "$file" ]; then
    name_val=$(grep "^name:" "$file" | head -1 | sed 's/^name: *//')
    [ -n "$name_val" ] && name="$name_val"
  fi

  echo "  Initiative: $name [archived]"

  epic_found=false
  for epic_file in "$init_dir"/*/epic.md; do
    [ -f "$epic_file" ] || continue
    epic_found=true
    epic_name=$(grep "^name:" "$epic_file" | head -1 | sed 's/^name: *//')
    [ -z "$epic_name" ] && epic_name=$(basename "$(dirname "$epic_file")")
    echo "    ✅ $epic_name (archived)"
  done

  if [ "$epic_found" = false ]; then
    echo "    (no epics)"
  fi
done

# Recent activity
echo ""
echo "📅 Recent Initiatives (last 5 modified):"
ls -t .ccpm/initiatives/*.md 2>/dev/null | head -5 | while read -r file; do
  name=$(grep "^name:" "$file" | head -1 | sed 's/^name: *//')
  [ -z "$name" ] && name=$(basename "$file" .md)
  echo "  • $name"
done

# Suggestions
echo ""
echo "💡 Next Actions:"
[ $backlog -gt 0 ] && echo "  • Parse backlog Initiatives to epics: /pm:initiative-parse <name>"
[ $in_progress -gt 0 ] && echo "  • Check progress on active Initiatives: /pm:epic-status <name>"
[ "$total" -eq 0 ] && echo "  • Create your first Initiative: /pm:initiative-new <name>"

exit 0
