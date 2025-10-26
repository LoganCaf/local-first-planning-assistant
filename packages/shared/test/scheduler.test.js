import test from 'node:test';
import assert from 'node:assert/strict';
import { createTask, createRoutine } from '../src/models.js';
import { buildAvailabilityGrid, generateSchedule } from '../src/scheduler.js';

const anchor = new Date('2024-09-02T09:00:00');

const classRoutine = createRoutine({
  name: 'Class',
  blocks: [
    {
      start: new Date('2024-09-02T12:00:00'),
      end: new Date('2024-09-02T14:00:00'),
      context: 'class',
      locked: true
    }
  ]
});

test('buildAvailabilityGrid removes routine blocks', () => {
  const availability = buildAvailabilityGrid([classRoutine], anchor, {
    planningHorizonDays: 1,
    dayStartHour: 8,
    dayEndHour: 20
  });
  const intervals = availability.values().next().value;
  const totalMinutes = intervals.reduce((acc, interval) => acc + (interval.end - interval.start) / 60000, 0);
  assert.equal(totalMinutes, 600);
});

test('generateSchedule places tasks respecting durations', () => {
  const tasks = [
    createTask({ id: 'a', title: 'Task A', estimatedDuration: 120, priority: 5 }),
    createTask({ id: 'b', title: 'Task B', estimatedDuration: 60, priority: 3 })
  ];
  const result = generateSchedule(tasks, [classRoutine], {
    planningHorizonDays: 1,
    dayStartHour: 8,
    dayEndHour: 20
  });

  assert.equal(result.scheduled.length, 2);
  assert.equal(result.unscheduled.length, 0);
  const [first, second] = result.scheduled;
  assert.ok(first.end <= second.start);
  assert.equal(first.taskId, 'a');
});
