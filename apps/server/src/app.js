import { createServer } from 'node:http';
import { URL } from 'node:url';
import {
  InMemoryDataStore,
  createTask,
  createGoal,
  createRoutine,
  generateSchedule,
  computeAnalyticsSummary,
  buildWeeklyReport,
  evaluateReminders,
  escalateSkippedTasks
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
    respondJson(res, { removed: success });
    return;
  }
  res.writeHead(405);
  res.end('Method not allowed');
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
  handleSchedule,
  handleWeeklyReport,
  handleNotifications,
  handleEscalations,
  handleAssistant
};
