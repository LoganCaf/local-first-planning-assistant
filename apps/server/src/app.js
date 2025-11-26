import { createServer } from 'node:http';
import { URL } from 'node:url';
import {
  InMemoryDataStore,
  createTask,
  createGoal,
  createRoutine,
  createAssignment,
  createAssignmentSegment,
  createTaskSegment,
  generateSchedule,
  computeAnalyticsSummary,
  buildWeeklyReport,
  evaluateReminders,
  escalateSkippedTasks,
  parseICSAssignments
} from '@llm/shared';
import { LocalAssistant } from './assistant.js';

export function createApp(options = {}) {
  const storePath = options.storePath ?? 'data/server-db.json';
  const store = new InMemoryDataStore(storePath);
  store.load();
  const assistant = options.assistant ?? new LocalAssistant(options.assistantOptions ?? {});

  const server = createServer(async (req, res) => {
    try {
      const host = req.headers.host ?? 'localhost';
      const url = new URL(req.url ?? '/', `http://${host}`);
      enableCORS(res);
      if (req.method === 'OPTIONS') {
        res.writeHead(204);
        res.end();
        return;
      }

      if (url.pathname === '/health' && req.method === 'GET') {
        respondJson(res, { status: 'ok', timestamp: new Date().toISOString() });
        return;
      }

      if (url.pathname === '/api/tasks') {
        await handleTasks(req, res, url, store);
        return;
      }
      if (url.pathname === '/api/tasks/timer' && req.method === 'POST') {
        await handleTaskTimer(req, res, store);
        return;
      }
      if (url.pathname === '/api/assignments') {
        await handleAssignments(req, res, url, store);
        return;
      }
      if (url.pathname === '/api/assignments/import' && req.method === 'POST') {
        await handleAssignmentImport(req, res, store);
        return;
      }
      if (url.pathname === '/api/assignments/sync' && req.method === 'POST') {
        await handleAssignmentSync(req, res, store);
        return;
      }
      if (url.pathname === '/api/assignment-segments') {
        await handleAssignmentSegments(req, res, url, store);
        return;
      }
      if (url.pathname === '/api/assignment-timer' && req.method === 'POST') {
        await handleAssignmentTimer(req, res, store);
        return;
      }
      if (url.pathname === '/api/assignment-segment-timer' && req.method === 'POST') {
        await handleAssignmentSegmentTimer(req, res, store);
        return;
      }
      if (url.pathname === '/api/task-segments') {
        await handleTaskSegments(req, res, url, store);
        return;
      }
      if (url.pathname === '/api/task-segment-timer' && req.method === 'POST') {
        await handleTaskSegmentTimer(req, res, store);
        return;
      }
      if (url.pathname === '/api/goals') {
        await handleGoals(req, res, url, store);
        return;
      }
      if (url.pathname === '/api/routines') {
        await handleRoutines(req, res, url, store);
        return;
      }
      if (url.pathname === '/api/schedule' && req.method === 'POST') {
        await handleSchedule(req, res, store, options.schedulerOptions ?? {});
        return;
      }
      if (url.pathname === '/api/assistant' && req.method === 'POST') {
        await handleAssistant(req, res, assistant, store);
        return;
      }
      if (url.pathname === '/api/notifications/upcoming' && req.method === 'GET') {
        await handleNotifications(res, store, options.notificationSettings ?? {});
        return;
      }
      if (url.pathname === '/api/notifications/escalations' && req.method === 'GET') {
        await handleEscalations(res, store, options.escalationSettings ?? {});
        return;
      }
      if (url.pathname === '/api/analytics/weekly' && req.method === 'GET') {
        await handleWeeklyReport(res, url, store);
        return;
      }
      if (url.pathname === '/api/export/json' && req.method === 'GET') {
        respondJson(res, store.state);
        return;
      }

      res.writeHead(404);
      res.end('Not found');
    } catch (error) {
      console.error(error);
      res.writeHead(500, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ error: 'internal_error', message: error.message }));
    }
  });

  return { server, store, assistant };
}

async function handleTasks(req, res, url, store) {
  if (req.method === 'GET') {
    respondJson(res, { tasks: store.state.tasks ?? [] });
    return;
  }
  if (req.method === 'POST') {
    const body = await readJsonBody(req);
    const task = createTask(body);
    store.upsert('tasks', task);
    respondJson(res, { task }, 201);
    return;
  }
  if (req.method === 'PUT') {
    const body = await readJsonBody(req);
    if (!body.id) throw new Error('Task id required');
    const existing = (store.state.tasks ?? []).find((t) => t.id === body.id);
    if (!existing) {
      res.writeHead(404);
      res.end('Task not found');
      return;
    }
    const task = createTask({ ...existing, ...body });
    store.upsert('tasks', task);
    respondJson(res, { task });
    return;
  }
  if (req.method === 'DELETE') {
    const id = url.searchParams.get('id');
    if (!id) {
      res.writeHead(400);
      res.end('Missing id');
      return;
    }
    const success = store.remove('tasks', id);
    if (success && Array.isArray(store.state.taskSegments)) {
      store.state.taskSegments = store.state.taskSegments.filter((seg) => seg.taskId !== id);
      store.save();
    }
    respondJson(res, { removed: success });
    return;
  }
  res.writeHead(405);
  res.end('Method not allowed');
}

async function handleTaskTimer(req, res, store) {
  const body = await readJsonBody(req);
  const id = body.id;
  const action = body.action;
  const now = new Date();
  if (!id || !action) {
    res.writeHead(400);
    res.end('id and action required');
    return;
  }

  const tasks = store.state.tasks ?? [];
  const existing = tasks.find((t) => t.id === id);
  if (!existing) {
    res.writeHead(404);
    res.end('Task not found');
    return;
  }

  const openIndex = (existing.history ?? []).findIndex((h) => h.startedAt && !h.stoppedAt);
  const history = [...(existing.history ?? [])];

  if (action === 'start') {
    if (openIndex === -1) {
      history.push({ startedAt: now });
    }
    existing.isCompleted = false;
  } else if (action === 'pause') {
    if (openIndex >= 0) {
      history[openIndex] = { ...history[openIndex], stoppedAt: now };
    }
  } else if (action === 'complete') {
    if (openIndex >= 0) {
      history[openIndex] = { ...history[openIndex], stoppedAt: now };
    }
    existing.isCompleted = true;
  } else {
    res.writeHead(400);
    res.end('Unknown action');
    return;
  }

  const updated = createTask({ ...existing, history, updatedAt: now });
  store.upsert('tasks', updated);
  respondJson(res, { task: updated });
}

async function handleGoals(req, res, url, store) {
  if (req.method === 'GET') {
    respondJson(res, { goals: store.state.goals ?? [] });
    return;
  }
  if (req.method === 'POST') {
    const body = await readJsonBody(req);
    const goal = createGoal(body);
    store.upsert('goals', goal);
    respondJson(res, { goal }, 201);
    return;
  }
  if (req.method === 'PUT') {
    const body = await readJsonBody(req);
    if (!body.id) throw new Error('Goal id required');
    const existing = (store.state.goals ?? []).find((g) => g.id === body.id);
    if (!existing) {
      res.writeHead(404);
      res.end('Goal not found');
      return;
    }
    const goal = createGoal({ ...existing, ...body });
    store.upsert('goals', goal);
    respondJson(res, { goal });
    return;
  }
  if (req.method === 'DELETE') {
    const id = url.searchParams.get('id');
    if (!id) {
      res.writeHead(400);
      res.end('Missing id');
      return;
    }
    const success = store.remove('goals', id);
    respondJson(res, { removed: success });
    return;
  }
  res.writeHead(405);
  res.end('Method not allowed');
}

async function handleAssignments(req, res, url, store) {
  if (req.method === 'GET') {
    respondJson(res, {
      assignments: store.state.assignments ?? [],
      assignmentSync: store.state.assignmentSync ?? null
    });
    return;
  }
  if (req.method === 'POST') {
    const body = await readJsonBody(req);
    const items = Array.isArray(body.assignments) ? body.assignments : [body];
    const created = items
      .filter(Boolean)
      .map((input) => createAssignment({ ...input, source: input.source ?? 'manual' }));
    created.forEach((item) => store.upsert('assignments', item));
    respondJson(res, { assignments: created }, 201);
    return;
  }
  if (req.method === 'PUT') {
    const body = await readJsonBody(req);
    if (!body.id) throw new Error('Assignment id required');
    const existing = (store.state.assignments ?? []).find((a) => a.id === body.id);
    if (!existing) {
      res.writeHead(404);
      res.end('Assignment not found');
      return;
    }
    const updated = createAssignment({ ...existing, ...body, updatedAt: new Date() });
    store.upsert('assignments', updated);
    respondJson(res, { assignment: updated });
    return;
  }
  if (req.method === 'DELETE') {
    const id = url.searchParams.get('id');
    if (!id) {
      res.writeHead(400);
      res.end('Missing id');
      return;
    }
    const removed = store.remove('assignments', id);
    if (removed && Array.isArray(store.state.assignmentSegments)) {
      store.state.assignmentSegments = store.state.assignmentSegments.filter((seg) => seg.assignmentId !== id);
      store.save();
    }
    respondJson(res, { removed });
    return;
  }
  res.writeHead(405);
  res.end('Method not allowed');
}

async function handleAssignmentImport(req, res, store) {
  const body = await readJsonBody(req);
  const icsText = body.icsText ?? '';
  const sourceName = body.sourceName ?? 'Canvas ICS';
  const sourceURL = body.sourceURL ?? null;
  const result = importAssignmentsFromICS(icsText, sourceName, sourceURL, store);
  if (!result) {
    res.writeHead(400);
    res.end('No assignments found in ICS file');
    return;
  }
  respondJson(res, { assignments: result }, 201);
}

async function handleAssignmentSync(req, res, store) {
  const sync = store.state.assignmentSync;
  if (!sync || sync.kind !== 'url' || !sync.url) {
    res.writeHead(400);
    res.end('No stored sync URL');
    return;
  }

  try {
    const response = await fetch(sync.url);
    if (!response.ok) {
      throw new Error(`Failed to fetch ICS: ${response.status}`);
    }
    const icsText = await response.text();
    const result = importAssignmentsFromICS(icsText, sync.displayName ?? 'Canvas ICS', sync.url, store);
    if (!result) {
      res.writeHead(400);
      res.end('No assignments found in ICS file');
      return;
    }
    respondJson(res, { assignments: result }, 201);
  } catch (error) {
    res.writeHead(500);
    res.end(error.message);
  }
}

function importAssignmentsFromICS(icsText, sourceName, sourceURL, store) {
  const parsed = parseICSAssignments(icsText);
  if (!parsed.length) {
    return null;
  }

  const existing = store.state.assignments ?? [];
  const merged = [];

  parsed.forEach((raw) => {
    const normalized = createAssignment({
      ...raw,
      source: sourceName,
      estimatedDuration: parseDurationFromDescription(raw.description ?? '')
    });
    const match = existing.find(
      (a) =>
        (raw.id && a.id === raw.id) ||
        (a.url && raw.url && a.url === raw.url) ||
        (a.title === normalized.title && a.due && normalized.due && a.due === normalized.due)
    );
    if (match) {
      const updated = createAssignment({
        ...match,
        ...normalized,
        id: match.id
      });
      store.upsert('assignments', updated);
      merged.push(updated);
    } else {
      store.upsert('assignments', normalized);
      merged.push(normalized);
    }
  });

  if (sourceURL) {
    store.state.assignmentSync = { kind: 'url', url: sourceURL, displayName: sourceName };
    store.state.assignmentICS = icsText;
    store.save();
  }

  return merged;
}

async function handleAssignmentSegments(req, res, url, store) {
  if (req.method === 'GET') {
    const assignmentId = url.searchParams.get('assignmentId');
    const segments = (store.state.assignmentSegments ?? []).filter((seg) =>
      assignmentId ? seg.assignmentId === assignmentId : true
    );
    respondJson(res, { segments });
    return;
  }
  if (req.method === 'POST') {
    const body = await readJsonBody(req);
    if (!body.assignmentId) throw new Error('assignmentId required');
    const segment = createAssignmentSegment(body);
    store.upsert('assignmentSegments', segment);
    respondJson(res, { segment }, 201);
    return;
  }
  if (req.method === 'PUT') {
    const body = await readJsonBody(req);
    if (!body.id) throw new Error('Segment id required');
    const existing = (store.state.assignmentSegments ?? []).find((s) => s.id === body.id);
    if (!existing) {
      res.writeHead(404);
      res.end('Segment not found');
      return;
    }
    const updated = createAssignmentSegment({ ...existing, ...body, updatedAt: new Date() });
    store.upsert('assignmentSegments', updated);
    respondJson(res, { segment: updated });
    return;
  }
  if (req.method === 'DELETE') {
    const id = url.searchParams.get('id');
    if (!id) {
      res.writeHead(400);
      res.end('Missing id');
      return;
    }
    const removed = store.remove('assignmentSegments', id);
    respondJson(res, { removed });
    return;
  }
  res.writeHead(405);
  res.end('Method not allowed');
}

async function handleRoutines(req, res, url, store) {
  if (req.method === 'GET') {
    respondJson(res, { routines: store.state.routines ?? [] });
    return;
  }
  if (req.method === 'POST') {
    const body = await readJsonBody(req);
    const routine = createRoutine(body);
    store.upsert('routines', routine);
    respondJson(res, { routine }, 201);
    return;
  }
  if (req.method === 'PUT') {
    const body = await readJsonBody(req);
    if (!body.id) throw new Error('Routine id required');
    const existing = (store.state.routines ?? []).find((g) => g.id === body.id);
    if (!existing) {
      res.writeHead(404);
      res.end('Routine not found');
      return;
    }
    const routine = createRoutine({ ...existing, ...body });
    store.upsert('routines', routine);
    respondJson(res, { routine });
    return;
  }
  if (req.method === 'DELETE') {
    const id = url.searchParams.get('id');
    if (!id) {
      res.writeHead(400);
      res.end('Missing id');
      return;
    }
    const success = store.remove('routines', id);
    respondJson(res, { removed: success });
    return;
  }
  res.writeHead(405);
  res.end('Method not allowed');
}

async function handleSchedule(req, res, store, schedulerOptions) {
  const body = await readJsonBody(req);
  const tasks = body.tasks ?? store.state.tasks ?? [];
  const routines = body.routines ?? store.state.routines ?? [];
  const options = { ...schedulerOptions, ...(body.options ?? {}) };
  const result = generateSchedule(tasks, routines, options);
  store.state.placements = result.scheduled;
  store.save();
  respondJson(res, result);
}

async function handleWeeklyReport(res, url, store) {
  const startParam = url.searchParams.get('start');
  const start = startParam ? new Date(startParam) : new Date();
  const placements = store.state.placements ?? [];
  const tasks = store.state.tasks ?? [];
  const summary = computeAnalyticsSummary(tasks, placements, { start });
  const weekly = buildWeeklyReport(tasks, placements, start);
  respondJson(res, { summary, weekly });
}

async function handleAssistant(req, res, assistant, store) {
  const body = await readJsonBody(req);
  const message = body.message ?? '';
  const history = Array.isArray(body.history) ? body.history : [];
  const result = await assistant.generateReply({ message, history });

  if (!store.state.conversationLog) {
    store.state.conversationLog = [];
  }
  store.state.conversationLog.push({
    timestamp: new Date().toISOString(),
    user: message,
    assistant: result.content
  });
  if (store.state.conversationLog.length > 200) {
    store.state.conversationLog.shift();
  }
  store.save();

  respondJson(res, { reply: result.content });
}

async function handleNotifications(res, store, notificationSettings) {
  const placements = store.state.placements ?? [];
  const reminders = evaluateReminders(placements, new Date(), notificationSettings);
  respondJson(res, { reminders });
}

async function handleEscalations(res, store, escalationSettings) {
  const tasks = store.state.tasks ?? [];
  const escalations = escalateSkippedTasks(tasks, escalationSettings);
  respondJson(res, { escalations });
}

function enableCORS(res) {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET,POST,PUT,DELETE,OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');
}

function respondJson(res, payload, statusCode = 200) {
  res.writeHead(statusCode, { 'Content-Type': 'application/json' });
  res.end(JSON.stringify(payload));
}

async function readJsonBody(req) {
  const chunks = [];
  for await (const chunk of req) {
    chunks.push(chunk);
  }
  if (chunks.length === 0) return {};
  const raw = Buffer.concat(chunks).toString('utf-8');
  return raw ? JSON.parse(raw) : {};
}

export { readJsonBody, respondJson };

export const __handlers = {
  handleTasks,
  handleGoals,
  handleRoutines,
  handleAssignments,
  handleAssignmentImport,
  handleAssignmentSync,
  handleAssignmentSegments,
  handleAssignmentTimer,
  handleAssignmentSegmentTimer,
  handleTaskSegments,
  handleTaskSegmentTimer,
  handleSchedule,
  handleWeeklyReport,
  handleNotifications,
  handleEscalations,
  handleAssistant
};

function parseDurationFromDescription(text = '') {
  const hoursMatch = text.match(/(\d+(?:\.\d+)?)\s*hour/i);
  const minutesMatch = text.match(/(\d+)\s*min/i);
  const hours = hoursMatch ? Number(hoursMatch[1]) : 0;
  const minutes = minutesMatch ? Number(minutesMatch[1]) : 0;
  const total = hours * 60 + minutes;
  return Number.isNaN(total) ? 0 : total;
}

async function handleAssignmentTimer(req, res, store) {
  const body = await readJsonBody(req);
  const id = body.id;
  const action = body.action;
  const now = new Date();
  if (!id || !action) {
    res.writeHead(400);
    res.end('id and action required');
    return;
  }

  const assignments = store.state.assignments ?? [];
  const existing = assignments.find((a) => a.id === id);
  if (!existing) {
    res.writeHead(404);
    res.end('Assignment not found');
    return;
  }

  const history = Array.isArray(existing.history) ? [...existing.history] : [];
  const openIndex = history.findIndex((h) => h.startedAt && !h.stoppedAt);

  if (action === 'start') {
    if (openIndex === -1) {
      history.push({ startedAt: now });
    }
    existing.isCompleted = false;
  } else if (action === 'pause') {
    if (openIndex >= 0) {
      history[openIndex] = { ...history[openIndex], stoppedAt: now };
    }
  } else if (action === 'complete') {
    if (openIndex >= 0) {
      history[openIndex] = { ...history[openIndex], stoppedAt: now };
    }
    existing.isCompleted = true;
  } else {
    res.writeHead(400);
    res.end('Unknown action');
    return;
  }

  const updated = createAssignment({ ...existing, history, updatedAt: now });
  store.upsert('assignments', updated);
  respondJson(res, { assignment: updated });
}

async function handleAssignmentSegmentTimer(req, res, store) {
  const body = await readJsonBody(req);
  const id = body.id;
  const action = body.action;
  const now = new Date();
  if (!id || !action) {
    res.writeHead(400);
    res.end('id and action required');
    return;
  }

  const segments = store.state.assignmentSegments ?? [];
  const existing = segments.find((s) => s.id === id);
  if (!existing) {
    res.writeHead(404);
    res.end('Segment not found');
    return;
  }

  const history = Array.isArray(existing.history) ? [...existing.history] : [];
  const openIndex = history.findIndex((h) => h.startedAt && !h.stoppedAt);

  if (action === 'start') {
    if (openIndex === -1) {
      history.push({ startedAt: now });
    }
    existing.isCompleted = false;
  } else if (action === 'pause') {
    if (openIndex >= 0) {
      history[openIndex] = { ...history[openIndex], stoppedAt: now };
    }
  } else if (action === 'complete') {
    if (openIndex >= 0) {
      history[openIndex] = { ...history[openIndex], stoppedAt: now };
    }
    existing.isCompleted = true;
  } else {
    res.writeHead(400);
    res.end('Unknown action');
    return;
  }

  const updated = createAssignmentSegment({ ...existing, history, updatedAt: now });
  store.upsert('assignmentSegments', updated);
  respondJson(res, { segment: updated });
}

async function handleTaskSegments(req, res, url, store) {
  if (req.method === 'GET') {
    const taskId = url.searchParams.get('taskId');
    const segments = (store.state.taskSegments ?? []).filter((seg) => (taskId ? seg.taskId === taskId : true));
    respondJson(res, { segments });
    return;
  }
  if (req.method === 'POST') {
    const body = await readJsonBody(req);
    if (!body.taskId) throw new Error('taskId required');
    const segment = createTaskSegment(body);
    store.upsert('taskSegments', segment);
    respondJson(res, { segment }, 201);
    return;
  }
  if (req.method === 'PUT') {
    const body = await readJsonBody(req);
    if (!body.id) throw new Error('Segment id required');
    const existing = (store.state.taskSegments ?? []).find((s) => s.id === body.id);
    if (!existing) {
      res.writeHead(404);
      res.end('Segment not found');
      return;
    }
    const updated = createTaskSegment({ ...existing, ...body, updatedAt: new Date() });
    store.upsert('taskSegments', updated);
    respondJson(res, { segment: updated });
    return;
  }
  if (req.method === 'DELETE') {
    const id = url.searchParams.get('id');
    if (!id) {
      res.writeHead(400);
      res.end('Missing id');
      return;
    }
    const removed = store.remove('taskSegments', id);
    respondJson(res, { removed });
    return;
  }
  res.writeHead(405);
  res.end('Method not allowed');
}

async function handleTaskSegmentTimer(req, res, store) {
  const body = await readJsonBody(req);
  const id = body.id;
  const action = body.action;
  const now = new Date();
  if (!id || !action) {
    res.writeHead(400);
    res.end('id and action required');
    return;
  }

  const segments = store.state.taskSegments ?? [];
  const existing = segments.find((s) => s.id === id);
  if (!existing) {
    res.writeHead(404);
    res.end('Segment not found');
    return;
  }

  const history = Array.isArray(existing.history) ? [...existing.history] : [];
  const openIndex = history.findIndex((h) => h.startedAt && !h.stoppedAt);

  if (action === 'start') {
    if (openIndex === -1) {
      history.push({ startedAt: now });
    }
    existing.isCompleted = false;
  } else if (action === 'pause') {
    if (openIndex >= 0) {
      history[openIndex] = { ...history[openIndex], stoppedAt: now };
    }
  } else if (action === 'complete') {
    if (openIndex >= 0) {
      history[openIndex] = { ...history[openIndex], stoppedAt: now };
    }
    existing.isCompleted = true;
  } else {
    res.writeHead(400);
    res.end('Unknown action');
    return;
  }

  const updated = createTaskSegment({ ...existing, history, updatedAt: now });
  store.upsert('taskSegments', updated);
  respondJson(res, { segment: updated });
}
