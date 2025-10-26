/**
 * Basic constructors and validation helpers for core domain objects.
 * Implemented with plain objects to avoid dependency on external libraries.
 */

const DEFAULT_PRIORITY = 3;

/**
 * @typedef {Object} Task
 * @property {string} id
 * @property {string} title
 * @property {string} [description]
 * @property {number} estimatedDuration Minutes
 * @property {Array<string>} [tags]
 * @property {number} priority 1 (low) - 5 (critical)
 * @property {Date|null} [due]
 * @property {boolean} hardDeadline
 * @property {Array<string>} [dependencies]
 * @property {string|null} [projectId]
 * @property {string|null} [goalId]
 * @property {string|null} [location]
 * @property {number} [travelMinutes] optional manual travel buffer
 * @property {Array<Object>} [history] log of timer entries
 * @property {Object<string, number>} [categoryWeights]
 */

/**
 * @typedef {Object} Routine
 * @property {string} id
 * @property {string} name
 * @property {Array<ScheduleBlock>} blocks
 * @property {boolean} active
 * @property {Array<DateRange>} pauses
 */

/**
 * @typedef {Object} Goal
 * @property {string} id
 * @property {string} name
 * @property {'time'|'occurrence'} targetType
 * @property {number} targetValue
 * @property {'daily'|'weekly'|'monthly'|'custom'} period
 * @property {number} [customDays]
 * @property {Array<string>} [linkedTaskIds]
 */

/**
 * @typedef {Object} ScheduleBlock
 * @property {string} id
 * @property {Date} start
 * @property {Date} end
 * @property {string} context e.g., sleep, class, work
 * @property {boolean} locked
 */

/**
 * @typedef {Object} DateRange
 * @property {Date} start
 * @property {Date} end
 */

/**
 * Generates a numeric identifier friendly string.
 * @returns {string}
 */
export function generateId() {
  const now = Date.now().toString(36);
  const rand = Math.random().toString(36).slice(2, 8);
  return `${now}-${rand}`;
}

/**
 * Normalize task input and ensure defaults.
 * @param {Partial<Task>} input
 * @returns {Task}
 */
export function createTask(input) {
  const now = new Date();
  return {
    id: input.id ?? generateId(),
    title: input.title?.trim() ?? 'Untitled Task',
    description: input.description ?? '',
    estimatedDuration: Math.max(15, Math.round(input.estimatedDuration ?? 60)),
    tags: Array.isArray(input.tags) ? [...new Set(input.tags.map((t) => t.trim()))] : [],
    priority: clampPriority(input.priority ?? DEFAULT_PRIORITY),
    due: normalizeDate(input.due),
    hardDeadline: Boolean(input.hardDeadline),
    dependencies: Array.isArray(input.dependencies) ? [...new Set(input.dependencies)] : [],
    projectId: input.projectId ?? null,
    goalId: input.goalId ?? null,
    location: input.location ?? null,
    travelMinutes: typeof input.travelMinutes === 'number' ? Math.max(0, input.travelMinutes) : 0,
    history: Array.isArray(input.history) ? [...input.history] : [],
    categoryWeights: input.categoryWeights ?? {},
    createdAt: input.createdAt ? new Date(input.createdAt) : now,
    updatedAt: now
  };
}

/**
 * Normalize a recurring routine definition.
 * @param {Partial<Routine>} input
 * @returns {Routine}
 */
export function createRoutine(input) {
  return {
    id: input.id ?? generateId(),
    name: input.name ?? 'Routine',
    blocks: (input.blocks ?? []).map((block) => ({
      id: block.id ?? generateId(),
      start: normalizeDate(block.start) ?? new Date(),
      end: normalizeDate(block.end) ?? new Date(),
      context: block.context ?? 'unspecified',
      locked: Boolean(block.locked)
    })),
    active: input.active !== false,
    pauses: (input.pauses ?? []).map((pause) => ({
      start: normalizeDate(pause.start) ?? new Date(),
      end: normalizeDate(pause.end) ?? new Date()
    }))
  };
}

/**
 * Normalize goal input.
 * @param {Partial<Goal>} input
 * @returns {Goal}
 */
export function createGoal(input) {
  return {
    id: input.id ?? generateId(),
    name: input.name ?? 'Goal',
    targetType: input.targetType ?? 'time',
    targetValue: Math.max(1, Number(input.targetValue ?? 1)),
    period: input.period ?? 'weekly',
    customDays: input.period === 'custom' ? Math.max(1, Number(input.customDays ?? 7)) : undefined,
    linkedTaskIds: Array.isArray(input.linkedTaskIds) ? [...new Set(input.linkedTaskIds)] : []
  };
}

/**
 * Ensures numeric priority bounds.
 * @param {number} value
 * @returns {number}
 */
export function clampPriority(value) {
  if (Number.isNaN(value)) return DEFAULT_PRIORITY;
  return Math.min(5, Math.max(1, Math.round(value)));
}

/**
 * Normalize date-like input.
 * @param {unknown} value
 * @returns {Date|null}
 */
export function normalizeDate(value) {
  if (!value) return null;
  const d = value instanceof Date ? value : new Date(value);
  return Number.isNaN(d.getTime()) ? null : d;
}

/**
 * Normalize a raw object into a Task while preserving known fields.
 * @param {Object} input
 * @returns {Task}
 */
export function normalizeTaskInput(input) {
  return createTask({
    ...input,
    due: input.due ? new Date(input.due) : null,
    history: Array.isArray(input.history)
      ? input.history.map((entry) => ({
          startedAt: entry.startedAt ? new Date(entry.startedAt) : null,
          stoppedAt: entry.stoppedAt ? new Date(entry.stoppedAt) : null,
          elapsedMinutes: entry.elapsedMinutes ?? null,
          note: entry.note ?? null
        }))
      : []
  });
}
