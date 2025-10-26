import test from 'node:test';
import assert from 'node:assert/strict';
import { state, setState, subscribe } from '../src/state.js';

test('setState updates snapshot and notifies subscribers', () => {
  const notifications = [];
  const unsubscribe = subscribe((snapshot) => notifications.push(snapshot.tasks.length));
  setState({ tasks: [{ id: '1', title: 'Test', estimatedDuration: 30, priority: 3 }] });
  unsubscribe();
  assert.equal(state.tasks.length, 1);
  assert.deepEqual(notifications, [0, 1]);
});
