/**
 * Basic analytics helpers that operate on schedule placements and task history.
 */

/**
 * Computes summary metrics for a date range.
 * @param {Array<Object>} tasks
 * @param {Array<Object>} placements
 * @param {Object} [options]
 */
export function computeAnalyticsSummary(tasks, placements, options = {}) {
  const start = options.start ? new Date(options.start) : null;
  const end = options.end ? new Date(options.end) : null;
  const filteredPlacements = placements.filter((placement) => {
    const startOk = start ? placement.start >= start : true;
    const endOk = end ? placement.end <= end : true;
    return startOk && endOk;
  });

  const metrics = {
    totalScheduledMinutes: 0,
    completedTasks: 0,
    overdueTasks: 0,
    categoryTotals: new Map(),
    focusScore: 0,
    streakDays: 0
  };

  const completionDates = new Set();

  for (const placement of filteredPlacements) {
    const duration = minutesBetween(placement.start, placement.end);
    metrics.totalScheduledMinutes += duration;
    const task = tasks.find((t) => t.id === placement.taskId);
    if (!task) continue;
    const completionEntry = task.history?.find((entry) => entry.elapsedMinutes);
    if (completionEntry) {
      metrics.completedTasks += 1;
      const entryDate = new Date(completionEntry.stoppedAt ?? completionEntry.startedAt ?? new Date());
      completionDates.add(entryDate.toISOString().slice(0, 10));
    } else if (task.due && new Date(task.due) < new Date()) {
      metrics.overdueTasks += 1;
    }
    accumulateCategory(metrics.categoryTotals, task);
  }

  metrics.focusScore = computeFocusScore(metrics.categoryTotals);
  metrics.streakDays = computeStreak(completionDates);

  return {
    totalScheduledMinutes: metrics.totalScheduledMinutes,
    totalHours: Number((metrics.totalScheduledMinutes / 60).toFixed(2)),
    completedTasks: metrics.completedTasks,
    overdueTasks: metrics.overdueTasks,
    categoryTotals: Object.fromEntries(metrics.categoryTotals),
    focusScore: Number(metrics.focusScore.toFixed(2)),
    streakDays: metrics.streakDays
  };
}

/**
 * Build a weekly report with narrative insights.
 * @param {Array<Object>} tasks
 * @param {Array<Object>} placements
 * @param {Date} referenceWeek
 */
export function buildWeeklyReport(tasks, placements, referenceWeek = new Date()) {
  const startOfWeek = startOf(referenceWeek, 'week');
  const endOfWeek = new Date(startOfWeek);
  endOfWeek.setDate(endOfWeek.getDate() + 7);

  const summary = computeAnalyticsSummary(tasks, placements, { start: startOfWeek, end: endOfWeek });

  const highlights = [];
  if (summary.completedTasks > 0) {
    highlights.push(`Great job completing ${summary.completedTasks} task${summary.completedTasks === 1 ? '' : 's'}!`);
  }
  if (summary.focusScore > 0.8) {
    highlights.push('You maintained solid focus balance across your categories.');
  } else if (summary.focusScore < 0.4) {
    highlights.push('Consider diversifying your focus to avoid burnout in one area.');
  }
  if (summary.overdueTasks > 0) {
    highlights.push(`Attention: ${summary.overdueTasks} task${summary.overdueTasks === 1 ? ' is' : 's are'} overdue.`);
  }

  return {
    weekStart: startOfWeek,
    weekEnd: endOfWeek,
    metrics: summary,
    highlights,
    suggestions: deriveSuggestions(summary)
  };
}

function accumulateCategory(map, task) {
  const categories = Object.keys(task.categoryWeights ?? {});
  if (categories.length === 0) {
    const tag = (task.tags && task.tags[0]) || 'uncategorized';
    increment(map, tag, task.estimatedDuration ?? 60);
    return;
  }

  for (const [category, weight] of Object.entries(task.categoryWeights)) {
    increment(map, category, (task.estimatedDuration ?? 60) * weight);
  }
}

function increment(map, key, value) {
  map.set(key, (map.get(key) ?? 0) + value);
}

function computeFocusScore(categoryTotals) {
  if (categoryTotals.size <= 1) return 1;
  const totals = Array.from(categoryTotals.values());
  const sum = totals.reduce((acc, val) => acc + val, 0);
  if (sum === 0) return 0;
  const normalized = totals.map((val) => val / sum);
  const entropy = normalized.reduce((acc, val) => acc - val * Math.log2(val || 1), 0);
  const maxEntropy = Math.log2(totals.length);
  return maxEntropy === 0 ? 1 : entropy / maxEntropy;
}

function computeStreak(daySet) {
  const dates = Array.from(daySet).sort();
  let longest = 0;
  let current = 0;
  let previous = null;
  for (const iso of dates) {
    const currentDate = new Date(iso);
    if (previous) {
      const delta = (currentDate - previous) / 86400000;
      if (delta === 1) {
        current += 1;
      } else {
        current = 1;
      }
    } else {
      current = 1;
    }
    longest = Math.max(longest, current);
    previous = currentDate;
  }
  return longest;
}

function deriveSuggestions(summary) {
  const suggestions = [];
  if (summary.overdueTasks > 0) {
    suggestions.push('Schedule focused sessions to catch up on overdue tasks.');
  }
  if (summary.focusScore < 0.5) {
    suggestions.push('Balance your categories by allocating time to underrepresented areas.');
  }
  if (summary.totalHours < 10) {
    suggestions.push('Consider increasing planned time to stay on track with your goals.');
  }
  return suggestions;
}

function startOf(date, unit) {
  const copy = new Date(date);
  if (unit === 'week') {
    const day = copy.getDay();
    const diff = copy.getDate() - day + (day === 0 ? -6 : 1); // Monday as first day
    copy.setDate(diff);
  }
  copy.setHours(0, 0, 0, 0);
  return copy;
}

function minutesBetween(start, end) {
  return Math.max(0, Math.floor((end - start) / 60000));
}
