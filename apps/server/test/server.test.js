import test from 'node:test';
import assert from 'node:assert/strict';
import { Readable, Writable } from 'node:stream';
import { URL } from 'node:url';
import { InMemoryDataStore } from '@llm/shared';
import { __handlers } from '../src/app.js';
import { MockAssistant } from '../src/assistant.js';

function createRequest(method, path, body = null) {
  const payload = body ? JSON.stringify(body) : '';
  let sent = false;
  const stream = new Readable({
    read() {
      if (sent) {
        this.push(null);
        return;
      }
      sent = true;
      this.push(payload);
      this.push(null);
    }
  });
  stream.method = method;
  stream.url = path;
  stream.headers = { 'content-type': 'application/json', host: 'localhost' };
  return stream;
}

function createResponse() {
  let status = 200;
  const headers = {};
  let body = '';
  const res = new Writable({
    write(chunk, _enc, callback) {
      body += chunk.toString();
      callback();
    }
  });
  res.writeHead = (code, hdrs = {}) => {
    status = code;
    Object.assign(headers, hdrs);
  };
  res.end = (chunk) => {
    if (chunk) body += chunk.toString();
    res.emit('finish');
  };
  res.getStatus = () => status;
  res.getHeaders = () => headers;
  res.getBody = () => (body ? JSON.parse(body) : {});
  return res;
}

test('task lifecycle via handlers', async () => {
  const store = new InMemoryDataStore('apps/server/test/tmp-db.json');
  store.state = { tasks: [], goals: [], routines: [], placements: [] };

  const createReq = createRequest('POST', '/api/tasks', {
    title: 'Finish project outline',
    estimatedDuration: 90,
    priority: 4
  });
  const createRes = createResponse();
  await __handlers.handleTasks(createReq, createRes, new URL('http://localhost/api/tasks'), store);
  assert.equal(createRes.getStatus(), 201);
  const { task } = createRes.getBody();
  assert.ok(task.id);
  assert.equal(store.state.tasks.length, 1);

  const listReq = createRequest('GET', '/api/tasks');
  const listRes = createResponse();
  await __handlers.handleTasks(listReq, listRes, new URL('http://localhost/api/tasks'), store);
  assert.equal(listRes.getStatus(), 200);
  assert.equal(listRes.getBody().tasks.length, 1);

  const scheduleReq = createRequest('POST', '/api/schedule', {});
  const scheduleRes = createResponse();
  await __handlers.handleSchedule(scheduleReq, scheduleRes, store, {});
  assert.equal(scheduleRes.getStatus(), 200);
  assert.equal(scheduleRes.getBody().scheduled.length, 1);

  const analyticsReq = createRequest('GET', '/api/analytics/weekly');
  const analyticsRes = createResponse();
  await __handlers.handleWeeklyReport(analyticsRes, new URL('http://localhost/api/analytics/weekly'), store);
  assert.equal(analyticsRes.getStatus(), 200);
  assert.ok(analyticsRes.getBody().summary);

  const notificationsRes = createResponse();
  await __handlers.handleNotifications(notificationsRes, store, { leadMinutes: [60] });
  assert.equal(notificationsRes.getStatus(), 200);
  assert.ok(Array.isArray(notificationsRes.getBody().reminders));

  const escalationRes = createResponse();
  await __handlers.handleEscalations(escalationRes, store, { skipThreshold: 1 });
  assert.equal(escalationRes.getStatus(), 200);
  assert.ok(Array.isArray(escalationRes.getBody().escalations));

  const assistant = new MockAssistant('Sure, prioritizing that now.');
  const assistantReq = createRequest('POST', '/api/assistant', {
    message: 'Can you adjust my study plan?',
    history: [{ role: 'user', content: 'Reminder: focus on math.' }]
  });
  const assistantRes = createResponse();
  await __handlers.handleAssistant(assistantReq, assistantRes, assistant, store);
  assert.equal(assistantRes.getStatus(), 200);
  assert.match(assistantRes.getBody().reply, /prioritizing/i);
});
