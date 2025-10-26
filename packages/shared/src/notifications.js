/**
 * Notification heuristics for reminders and escalation logic.
 */

/**
 * Decide which reminders to fire based on upcoming schedule.
 * @param {Array<Object>} placements
 * @param {Date} now
 * @param {Object} settings
 */
export function evaluateReminders(placements, now = new Date(), settings = {}) {
  const leadTimes = settings.leadMinutes ?? [60, 15];
  const quietHours = settings.quietHours ?? { start: 22, end: 6 };
  const results = [];
  for (const placement of placements) {
    const minutesUntilStart = Math.floor((placement.start - now) / 60000);
    if (minutesUntilStart < 0) continue;
    for (const lead of leadTimes) {
      if (minutesUntilStart === lead) {
        if (isQuietHour(placement.start, quietHours)) continue;
        results.push({
          taskId: placement.taskId,
          fireAt: new Date(placement.start.getTime() - lead * 60000),
          message: `Upcoming: ${placement.title} in ${lead} minute${lead === 1 ? '' : 's'}`
        });
      }
    }
  }
  return results;
}

/**
 * Escalate tasks that are repeatedly skipped.
 * @param {Array<Object>} tasks
 * @param {Object} [options]
 */
export function escalateSkippedTasks(tasks, options = {}) {
  const threshold = options.skipThreshold ?? 3;
  const escalations = [];
  for (const task of tasks) {
    const skips = (task.history ?? []).filter((entry) => entry.status === 'skipped').length;
    if (skips >= threshold) {
      escalations.push({
        taskId: task.id,
        strategy: 'increase-priority',
        message: `Task "${task.title}" has been skipped ${skips} times. Consider rescoping or increasing priority.`
      });
    }
  }
  return escalations;
}

function isQuietHour(date, quietHours) {
  const hour = date.getHours();
  if (quietHours.start > quietHours.end) {
    return hour >= quietHours.start || hour < quietHours.end;
  }
  return hour >= quietHours.start && hour < quietHours.end;
}
