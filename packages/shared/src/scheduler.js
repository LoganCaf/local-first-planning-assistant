import { normalizeDate, clampPriority } from './models.js';

export const defaultSchedulingOptions = {
  planningHorizonDays: 28,
  dayStartHour: 6,
  dayEndHour: 22,
  minimumSlotMinutes: 15,
  travelBufferMinutes: 10,
  weights: {
    priority: 1.5,
    deadline: 1.2,
    goal: 0.6,
    categoryBalance: 0.3
  },
  energyPreferences: {
    morning: 1.1,
    afternoon: 1,
    evening: 0.8,
    night: 0.3
  },
  timezone: 'local'
};

/**
 * Build availability windows for the planning horizon by subtracting routine blocks.
 * @param {Array} routines
 * @param {Date} anchorDate
 * @param {Partial<typeof defaultSchedulingOptions>} options
 * @returns {Map<string, Array<{start: Date, end: Date}>>}
 */
export function buildAvailabilityGrid(routines, anchorDate = new Date(), options = {}) {
  const config = { ...defaultSchedulingOptions, ...options };
  const grid = new Map();
  const anchor = stripTime(anchorDate);

  for (let i = 0; i < config.planningHorizonDays; i += 1) {
    const day = new Date(anchor);
    day.setDate(anchor.getDate() + i);
    const key = day.toISOString().slice(0, 10);
    const start = new Date(day);
    start.setHours(config.dayStartHour, 0, 0, 0);
    const end = new Date(day);
    end.setHours(config.dayEndHour, 0, 0, 0);
    const intervals = [{ start, end, energyBand: classifyEnergyBand(start, config) }];
    grid.set(key, subtractRoutineBlocks(intervals, routines, day));
  }

  return grid;
}

/**
 * Produce schedule by greedily allocating tasks.
 * @param {Array<Object>} tasks
 * @param {Array<Object>} routines
 * @param {Object} [options]
 */
export function generateSchedule(tasks, routines = [], options = {}) {
  const config = { ...defaultSchedulingOptions, ...options };
  const now = new Date();
  const availability = buildAvailabilityGrid(routines, now, config);
  const sortedTasks = [...tasks]
    .map((task) => ({
      task,
      score: scoreTask(task, now, config)
    }))
    .sort((a, b) => b.score - a.score);

  const placements = [];
  const unscheduled = [];
  let previousPlacement = null;

  for (const item of sortedTasks) {
    const scheduleOutcome = allocateTask(item.task, availability, previousPlacement, config);
    if (scheduleOutcome) {
      placements.push(scheduleOutcome);
      previousPlacement = scheduleOutcome;
    } else {
      unscheduled.push({
        taskId: item.task.id,
        reason: 'insufficient-availability'
      });
    }
  }

  const resolvedPlacements = mergeConflicts(placements);

  return {
    scheduled: resolvedPlacements,
    unscheduled,
    availability
  };
}

/**
 * Attempt to allocate a task into availability map.
 * @param {Object} task
 * @param {Map<string, Array<{start: Date, end: Date}>>} availability
 * @param {Object|null} previousPlacement
 * @param {Object} config
 */
export function allocateTask(task, availability, previousPlacement, config) {
  const requiredMinutes =
    Math.ceil((task.estimatedDuration ?? 60) / config.minimumSlotMinutes) * config.minimumSlotMinutes;
  const travelBuffer = (task.travelMinutes ?? 0) + config.travelBufferMinutes;
  const earliestStartKey = previousPlacement ? previousPlacement.end.toISOString().slice(0, 10) : null;

  for (const [key, intervals] of availability.entries()) {
    const intervalSet = intervals;
    for (let index = 0; index < intervalSet.length; index += 1) {
      const interval = intervalSet[index];
      const slotLength = minutesBetween(interval.start, interval.end);

      if (slotLength < requiredMinutes) continue;
      const proposedStart = new Date(interval.start);
      if (earliestStartKey && key === earliestStartKey && previousPlacement) {
        // Insert travel buffer if location changes
        if (previousPlacement.location && task.location && previousPlacement.location !== task.location) {
          proposedStart.setMinutes(proposedStart.getMinutes() + travelBuffer);
        }
        if (proposedStart < previousPlacement.end) {
          proposedStart.setTime(previousPlacement.end.getTime() + travelBuffer * 60000);
        }
      }
      const proposedEnd = new Date(proposedStart);
      proposedEnd.setMinutes(proposedEnd.getMinutes() + requiredMinutes);

      if (proposedEnd > interval.end) continue;

      // Commit allocation by splitting interval
      const remaining = splitInterval(interval, proposedStart, proposedEnd);
      intervalSet.splice(index, 1, ...remaining);

      return {
        taskId: task.id,
        title: task.title,
        start: proposedStart,
        end: proposedEnd,
        location: task.location ?? null,
        metadata: {
          priority: clampPriority(task.priority ?? 3),
          energyBand: classifyEnergyBand(proposedStart, config),
          due: task.due ? new Date(task.due) : null,
          goalId: task.goalId ?? null
        }
      };
    }
  }

  return null;
}

/**
 * Greedy scheduling helper useful for testing.
 */
export function scheduleTasksGreedy(tasks, availability, config = defaultSchedulingOptions) {
  const placements = [];
  let previous = null;
  for (const task of tasks) {
    const placement = allocateTask(task, availability, previous, config);
    if (placement) {
      placements.push(placement);
      previous = placement;
    }
  }
  return placements;
}

/**
 * Merge overlapping placements by adjusting later tasks forwards.
 * @param {Array<Object>} placements
 */
export function mergeConflicts(placements) {
  const sorted = [...placements].sort((a, b) => a.start - b.start);
  for (let i = 1; i < sorted.length; i += 1) {
    const prev = sorted[i - 1];
    const current = sorted[i];
    if (current.start < prev.end) {
      const offset = prev.end.getTime() - current.start.getTime();
      current.start = new Date(current.start.getTime() + offset);
      current.end = new Date(current.end.getTime() + offset);
    }
  }
  return sorted;
}

function subtractRoutineBlocks(intervals, routines, day) {
  let working = [...intervals];
  for (const routine of routines) {
    if (!routine || routine.active === false) continue;
    if (isPaused(routine, day)) continue;
    for (const block of routine.blocks ?? []) {
      if (!appliesOnDay(block, day)) continue;
      const blockStart = composeDateTime(day, block.start);
      let blockEnd = composeDateTime(day, block.end);
      if (blockEnd <= blockStart) {
        blockEnd = new Date(blockEnd.getTime() + 24 * 60 * 60000);
      }
      working = subtractIntervalSet(working, blockStart, blockEnd);
    }
  }
  return working.filter((interval) => minutesBetween(interval.start, interval.end) >= 15);
}

function subtractIntervalSet(intervals, removeStart, removeEnd) {
  const result = [];
  for (const interval of intervals) {
    if (removeEnd <= interval.start || removeStart >= interval.end) {
      result.push(interval);
      continue;
    }
    if (removeStart > interval.start) {
      result.push({
        start: interval.start,
        end: new Date(removeStart),
        energyBand: interval.energyBand
      });
    }
    if (removeEnd < interval.end) {
      result.push({
        start: new Date(removeEnd),
        end: interval.end,
        energyBand: interval.energyBand
      });
    }
  }
  return result;
}

function splitInterval(interval, start, end) {
  const fragments = [];
  if (start > interval.start) {
    fragments.push({
      start: interval.start,
      end: new Date(start),
      energyBand: interval.energyBand
    });
  }
  if (end < interval.end) {
    fragments.push({
      start: new Date(end),
      end: interval.end,
      energyBand: interval.energyBand
    });
  }
  return fragments;
}

function isPaused(routine, day) {
  return (routine.pauses ?? []).some((pause) => day >= pause.start && day <= pause.end);
}

function appliesOnDay(block, day) {
  const blockStart = normalizeDate(block.start) ?? new Date();
  return blockStart.getDay() === day.getDay();
}

function composeDateTime(day, templateDate) {
  const template = normalizeDate(templateDate) ?? new Date();
  const combined = new Date(day);
  combined.setHours(template.getHours(), template.getMinutes(), 0, 0);
  return combined;
}

function minutesBetween(start, end) {
  return Math.max(0, Math.floor((end - start) / 60000));
}

function stripTime(source) {
  const out = new Date(source);
  out.setHours(0, 0, 0, 0);
  return out;
}

function classifyEnergyBand(date, config) {
  const hour = date.getHours();
  if (hour >= 5 && hour < 12) return 'morning';
  if (hour >= 12 && hour < 17) return 'afternoon';
  if (hour >= 17 && hour < 22) return 'evening';
  return config.energyPreferences?.night ? 'night' : 'evening';
}

function scoreTask(task, now, config) {
  const priorityScore = (clampPriority(task.priority ?? 3) / 5) * config.weights.priority;
  const dueDate = task.due ? new Date(task.due) : null;
  const deadlineScore = dueDate
    ? (config.weights.deadline * 1) / Math.max(1, daysBetween(now, dueDate))
    : 0;
  const goalScore = task.goalId ? config.weights.goal : 0;
  const durationPenalty = Math.log10((task.estimatedDuration ?? 60) / 30 + 1) * 0.2;
  return priorityScore + deadlineScore + goalScore - durationPenalty;
}

function daysBetween(start, end) {
  const diff = stripTime(end) - stripTime(start);
  return Math.max(0, Math.floor(diff / 86400000));
}
