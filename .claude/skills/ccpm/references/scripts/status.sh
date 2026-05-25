#!/bin/bash
cd "$(git rev-parse --show-toplevel)" || exit 1

echo "Getting status..."
echo ""
echo ""


echo "📊 Project Status"
echo "================"
echo ""

echo "📄 Initiatives:"
if [ -d ".ccpm/prds" ]; then
  total=$(ls .ccpm/initiatives/*.md 2>/dev/null | wc -l)
  echo "  Total: $total"
else
  echo "  No Initiatives found"
fi

echo ""
echo "📚 Epics:"
if [ -d ".ccpm/epics" ]; then
  total=$(ls -d .ccpm/initiatives/*/ 2>/dev/null | grep -v '/archived/$' | wc -l)
  echo "  Total: $total"
else
  echo "  No epics found"
fi

echo ""
echo "📝 Tasks:"
if [ -d ".ccpm/epics" ]; then
  total=$(find .ccpm/epics -path "*/archived/*" -prune -o -name "[0-9]*.md" -print 2>/dev/null | wc -l)
  open=$(find .ccpm/epics -path "*/archived/*" -prune -o -name "[0-9]*.md" -print 2>/dev/null | xargs grep -l "^status: *open" 2>/dev/null | wc -l)
  closed=$(find .ccpm/epics -path "*/archived/*" -prune -o -name "[0-9]*.md" -print 2>/dev/null | xargs grep -l "^status: *closed" 2>/dev/null | wc -l)
  echo "  Open: $open"
  echo "  Closed: $closed"
  echo "  Total: $total"
else
  echo "  No tasks found"
fi

exit 0
