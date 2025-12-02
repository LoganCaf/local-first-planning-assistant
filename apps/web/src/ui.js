const WEEKDAY_LABELS = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
const MONTH_FORMATTER = new Intl.DateTimeFormat(undefined, { month: 'long', year: 'numeric' });
const DAY_NUMBER_FORMATTER = new Intl.DateTimeFormat(undefined, { day: 'numeric' });
const LONG_DAY_FORMATTER = new Intl.DateTimeFormat(undefined, {
  weekday: 'long',
  month: 'long',
  day: 'numeric'
});
const SHORT_DAY_FORMATTER = new Intl.DateTimeFormat(undefined, {
  weekday: 'short',
  month: 'short',
  day: 'numeric'
});
const TIME_FORMATTER = new Intl.DateTimeFormat(undefined, {
  hour: 'numeric',
  minute: '2-digit'
});

export function renderCalendar({
  monthLabelEl,
  weekdayHeaderEl,
  gridEl,
  calendarMonth,
  selectedDate,
  schedule,
  tasks = [],
  assignments = [],
  segments = []
}) {
  if (!monthLabelEl || !gridEl) return;
  const monthDate = normalizeDate(calendarMonth);
  const selected = normalizeDate(selectedDate);
  monthLabelEl.textContent = MONTH_FORMATTER.format(monthDate);
  if (weekdayHeaderEl && weekdayHeaderEl.childElementCount === 0) {
    WEEKDAY_LABELS.forEach((label) => {
      const span = document.createElement('span');
      span.textContent = label;
      weekdayHeaderEl.append(span);
    });
  }

  const selectedIso = toISODate(selected);
  const todayIso = toISODate(new Date());
  const markers = buildScheduleMarkers(schedule ?? [], tasks, assignments, segments);
  const matrix = buildMonthMatrix(monthDate);

  gridEl.innerHTML = '';
  matrix.forEach(({ date, isCurrentMonth }) => {
    const iso = toISODate(date);
    const cell = document.createElement('button');
    cell.type = 'button';
    cell.className = 'calendar-day';
    cell.dataset.date = iso;

    if (!isCurrentMonth) cell.classList.add('is-outside');
    if (iso === todayIso) cell.classList.add('is-today');
    if (iso === selectedIso) cell.classList.add('is-selected');
    if (markers.has(iso)) cell.classList.add('has-events');

    const number = document.createElement('span');
    number.className = 'calendar-day-number';
    number.textContent = DAY_NUMBER_FORMATTER.format(date);
    cell.append(number);

    if (markers.has(iso)) {
      const dot = document.createElement('span');
      dot.className = 'calendar-dot';
      dot.dataset.count = String(markers.get(iso));
      cell.append(dot);
    }

    gridEl.append(cell);
  });
}

export function renderAgenda({ listEl, emptyEl, schedule, tasks = [], taskSegments = [], assignments = [], assignmentSegments = [], selectedDate }) {
  if (!listEl || !emptyEl) return;
  const iso = toISODate(selectedDate ?? new Date());
  const scheduled = (schedule ?? []).map((item) => ({
    ...item,
    start: new Date(item.start),
    end: new Date(item.end),
    kind: 'scheduled'
  }));
  const taskEvents = tasks
    .filter((task) => toISODate(task.due ?? task.start ?? task.due) === iso || toISODate(task.start) === iso)
    .map((task) => {
      const start = task.start ? new Date(task.start) : task.due ? new Date(task.due) : new Date(selectedDate);
      const end = task.start
        ? new Date(start.getTime() + Math.max(15, (task.estimatedDuration ?? 60)) * 60000)
        : start;
      return {
        start,
        end,
        title: task.title,
        metadata: { priority: task.priority, due: task.due, source: 'task' }
      };
    });
  const assignmentEvents = assignments
    .filter((assignment) => toISODate(assignment.due) === iso || toISODate(assignment.end) === iso)
    .map((assignment) => ({
      start: new Date(assignment.due),
      end: assignment.end ? new Date(assignment.end) : new Date(assignment.due),
      title: assignment.title,
      metadata: { priority: assignment.priority, due: assignment.due, source: 'assignment' }
    }));

  const taskSegmentEvents = taskSegments
    .filter((seg) => toISODate(seg.due) === iso)
    .map((seg) => ({
      start: new Date(seg.start ?? seg.due ?? selectedDate),
      end: new Date(seg.due ?? seg.start ?? selectedDate),
      title: seg.title,
      metadata: { priority: seg.priority, due: seg.due, source: 'task-segment' }
    }));

  const assignmentSegmentEvents = assignmentSegments
    .filter((seg) => toISODate(seg.due) === iso)
    .map((seg) => ({
      start: new Date(seg.due ?? selectedDate),
      end: new Date(seg.due ?? selectedDate),
      title: seg.title,
      metadata: { priority: seg.priority, due: seg.due, source: 'assignment-segment' }
    }));

  const events = [...scheduled, ...taskEvents, ...assignmentEvents, ...taskSegmentEvents, ...assignmentSegmentEvents]
    .filter((item) => toISODate(item.start) === iso)
    .sort((a, b) => a.start - b.start);

  listEl.innerHTML = '';
  if (events.length === 0) {
    emptyEl.style.display = 'grid';
    return;
  }
  emptyEl.style.display = 'none';

  events.forEach((event) => {
    const li = document.createElement('li');
    li.className = 'agenda-item';
    if (event.metadata?.source === 'task') {
      li.dataset.taskId = event.metadata.id;
    }
    const title = escapeHtml(event.title ?? 'Scheduled focus block');
    const timeRange = formatTimeRange(event.start, event.end);
    const metaParts = [];
    if (event.metadata?.priority) metaParts.push(`Priority ${event.metadata.priority}`);
    if (event.metadata?.due) metaParts.push(`Due ${SHORT_DAY_FORMATTER.format(new Date(event.metadata.due))}`);
    if (event.location) metaParts.push(event.location);

    li.innerHTML = `
      <div class="agenda-time">${timeRange}</div>
      <div class="agenda-body">
        <p class="agenda-title">${title}</p>
        <p class="agenda-meta">${metaParts.join(' • ') || 'Planned by assistant'}</p>
      </div>
    `;
    li.addEventListener('click', () => handleAgendaClick(event));
    listEl.append(li);
  });
}

export function renderInsightCards(container, insights) {
  if (!container) return;
  if (!insights) {
    container.innerHTML = '<div class="insight-empty">Insights will appear after your first plan.</div>';
    return;
  }

  const cards = [
    {
      label: 'Scheduled hours',
      value: `${Number(insights.summary.totalHours ?? 0).toFixed(1)}h`
    },
    {
      label: 'Completed tasks',
      value: String(insights.summary.completedTasks ?? 0)
    },
    {
      label: 'Focus score',
      value: (insights.summary.focusScore ?? 0).toFixed(2)
    },
    {
      label: 'Streak',
      value: `${insights.summary.streakDays ?? 0}d`
    }
  ];

  container.innerHTML = cards
    .map(
      (card) => `
        <div class="insight-card">
          <span class="insight-value">${escapeHtml(card.value)}</span>
          <span class="insight-label">${escapeHtml(card.label)}</span>
        </div>
      `
    )
    .join('');
}

export function renderTasks(listEl, tasks = [], segments = [], activeFilter = 'all') {
  if (!listEl) return;
  const normalized = tasks.map((task) => ({
    ...task,
    category: Array.isArray(task.tags) && task.tags.length > 0 ? task.tags[0] : 'general'
  }));

  const filtered = normalized.filter((task) => {
    if (activeFilter === 'all') return true;
    return task.category?.toLowerCase() === activeFilter;
  });

  listEl.innerHTML = '';
  if (filtered.length === 0) {
    listEl.innerHTML = '<li class="empty-state">No tasks yet. Capture something and regenerate your plan.</li>';
    return;
  }

  filtered
    .sort((a, b) => {
      if (a.isCompleted !== b.isCompleted) return a.isCompleted ? 1 : -1;
      return (b.priority ?? 0) - (a.priority ?? 0);
    })
    .forEach((task) => {
      const li = document.createElement('li');
      li.className = 'task-item';
      const duration = `${task.estimatedDuration ?? 60} min`;
      const categoryLabel = capitalize(task.category ?? 'general');
      const isActive = Boolean(task.history?.find((h) => h.startedAt && !h.stoppedAt));
      const completed = Boolean(task.isCompleted);
      const taskSegments = segments.filter((seg) => seg.taskId === task.id);
      const startText = task.start ? formatDateDisplay(task.start) : null;
      const deadlineText = task.hasDeadline === false ? 'No deadline' : task.due ? formatDateDisplay(task.due) : 'No deadline';
      const timerLabel = task.history?.length ? renderTaskTimerLabel(task) : '';
      const segmentHtml = taskSegments
        .map(
          (seg) => `
        <li class="segment-row">
          <label class="checkbox">
            <input type="checkbox" data-action="toggle-task-segment" data-segment-id="${seg.id}" ${
              seg.isCompleted ? 'checked' : ''
            } />
            <span>${escapeHtml(seg.title)}</span>
          </label>
          <div class="segment-meta">
            ${seg.due ? escapeHtml(formatDateDisplay(seg.due)) : 'No due'}
            ${seg.estimatedDuration ? `• ${seg.estimatedDuration}m` : ''}
            ${seg.history?.length ? `• ${escapeHtml(renderTaskTimerLabel(seg))}` : ''}
          </div>
          <div class="task-actions">
            <button type="button" data-action="start-task-segment" data-segment-id="${seg.id}" class="ghost-button">Start</button>
            <button type="button" data-action="pause-task-segment" data-segment-id="${seg.id}" class="ghost-button">Pause</button>
            <button type="button" data-action="finish-task-segment" data-segment-id="${seg.id}" class="ghost-button">Done</button>
            <button type="button" class="ghost-button" data-action="delete-task-segment" data-segment-id="${seg.id}">Remove</button>
          </div>
        </li>
      `
        )
        .join('');

      li.innerHTML = `
        <div class="task-header">
          <span class="task-title">${escapeHtml(task.title)}</span>
          <span class="task-category">${escapeHtml(categoryLabel)}</span>
        </div>
        <div class="task-meta">
          ${duration} • Priority ${task.priority ?? 3}
          ${startText ? `• Starts ${escapeHtml(startText)}` : ''}
          • ${escapeHtml(deadlineText)}
        </div>
        <div class="task-actions">
          <button type="button" data-action="toggle-complete" data-task-id="${task.id}" class="ghost-button">
            ${completed ? 'Mark incomplete' : 'Mark complete'}
          </button>
          ${
            isActive
              ? `<button type="button" data-action="pause-task" data-task-id="${task.id}" class="ghost-button">Pause</button>`
              : `<button type="button" data-action="start-task" data-task-id="${task.id}" class="ghost-button">${
                  completed ? 'Restart' : 'Start'
                }</button>`
          }
          <button type="button" data-action="finish-task" data-task-id="${task.id}" class="ghost-button">Done</button>
          <button type="button" data-task-id="${task.id}" class="ghost-button">Delete</button>
        </div>
        ${
          isActive || task.history?.length
            ? `<div class="task-timer">${renderTaskTimerLabel(task)}</div>`
            : ''
        }
        <details class="assignment-edit">
          <summary>Edit details</summary>
          <form class="task-edit-form" data-task-id="${task.id}">
            <div class="field">
              <label>Title</label>
              <input name="title" value="${escapeHtml(task.title)}" />
            </div>
            <div class="field">
              <label>Description</label>
              <textarea name="description">${escapeHtml(task.description ?? '')}</textarea>
            </div>
            <div class="field">
              <label>Duration (min)</label>
              <input name="duration" type="number" min="0" step="15" value="${task.estimatedDuration ?? 60}" />
            </div>
            <div class="field">
              <label>Priority</label>
              <input name="priority" type="number" min="1" max="5" value="${task.priority ?? 3}" />
            </div>
            <div class="field">
              <label><input type="checkbox" name="hasDeadline" ${task.hasDeadline !== false ? 'checked' : ''} /> Has deadline</label>
            </div>
            <div class="field" data-time-row>
              <label>Due</label>
              <input name="due" type="datetime-local" value="${task.due ? toInputValue(task.due, false) : ''}" />
            </div>
            <div class="field">
              <label>Start</label>
              <input name="start" type="datetime-local" value="${task.start ? toInputValue(task.start, false) : ''}" />
            </div>
            <button type="submit" class="ghost-button">Save</button>
          </form>
        </details>
        <div class="segments">
          <h4>Segments</h4>
          <ul class="segment-list">
            ${segmentHtml || '<li class="muted">No segments yet.</li>'}
          </ul>
          <form class="segment-form" data-task-id="${task.id}">
            <input name="title" placeholder="Add a segment" required />
            <input name="due" type="date" />
            <input name="minutes" type="number" min="0" step="15" placeholder="mins" />
            <button type="submit" class="ghost-button">Add</button>
          </form>
        </div>
      `;
      listEl.append(li);
    });
}

export function renderActiveTasks(listEl, tasks = []) {
  if (!listEl) return;
  listEl.innerHTML = '';
  const active = tasks.filter((task) => task.history?.some((h) => h.startedAt && !h.stoppedAt));
  if (!active.length) {
    listEl.innerHTML = '<li class="empty-state">No running timers.</li>';
    return;
  }
  active.forEach((task) => {
    const li = document.createElement('li');
    li.className = 'task-item';
    li.innerHTML = `
      <div class="task-header">
        <span class="task-title">${escapeHtml(task.title)}</span>
        <span class="task-category">Running</span>
      </div>
      <div class="task-meta">${renderTaskTimerLabel(task)}</div>
      <div class="task-actions">
        <button type="button" data-action="pause-task" data-task-id="${task.id}" class="ghost-button">Pause</button>
        <button type="button" data-action="finish-task" data-task-id="${task.id}" class="ghost-button">Done</button>
      </div>
    `;
    listEl.append(li);
  });
}

export function updateTaskFilters(container, activeFilter) {
  if (!container) return;
  container.querySelectorAll('[data-filter]').forEach((button) => {
    button.classList.toggle('is-active', button.dataset.filter === activeFilter);
  });
}

export function renderRoutines(listEl, routines = []) {
  if (!listEl) return;
  listEl.innerHTML = '';

  if (routines.length === 0) {
    listEl.innerHTML = '<li class="empty-state">No routines yet. Create one to protect your recurring habits.</li>';
    return;
  }

  routines.forEach((routine) => {
    const li = document.createElement('li');
    li.className = 'routine-item';
    const blocks = (routine.blocks ?? []).map((block) => formatRoutineBlock(block));
    const timeline = renderRoutineTimeline(routine);
    li.innerHTML = `
      <div class="routine-header">
        <span class="routine-name">${escapeHtml(routine.icon ?? '🔁')} ${escapeHtml(routine.name ?? 'Routine')}</span>
        <div class="routine-controls">
          <label class="checkbox">
            <input type="checkbox" data-action="toggle-routine" data-routine-id="${routine.id}" ${routine.active !== false ? 'checked' : ''} />
            <span>Enabled</span>
          </label>
          <button type="button" class="ghost-button" data-routine-id="${routine.id}">Remove</button>
        </div>
      </div>
      <div class="routine-schedule">${blocks.join('<br />')}</div>
      <div class="routine-timeline">${timeline}</div>
    `;
    listEl.append(li);
  });
}

export function renderAssistantHistory(log, history = []) {
  if (!log) return;
  log.innerHTML = '';
  if (history.length === 0) {
    log.innerHTML = '<div class="assistant-placeholder">Ask for help planning, motivating, or reprioritising.</div>';
    return;
  }

  history.forEach((entry) => {
    const bubble = document.createElement('div');
    bubble.className = `assistant-message ${entry.role}`;
    bubble.textContent = entry.content;
    log.append(bubble);
  });
  log.scrollTop = log.scrollHeight;
}

export function updateActiveTab(activeTab, views = [], tabButtons = []) {
  views.forEach((view) => {
    view.classList.toggle('active', view.dataset.view === activeTab);
  });
  tabButtons.forEach((button) => {
    button.classList.toggle('active', button.dataset.tab === activeTab);
  });
}

export function formatSelectedHeading(date) {
  const normalized = normalizeDate(date);
  const iso = toISODate(normalized);
  const todayIso = toISODate(new Date());
  if (iso === todayIso) return "Today's countdown";
  return `Countdown for ${LONG_DAY_FORMATTER.format(normalized)}`;
}

export function renderCountdowns({ listEl, tasks = [], taskSegments = [], assignments = [], assignmentSegments = [], selectedDate }) {
  if (!listEl) return;
  const now = new Date();
  const targetDate = normalizeDate(selectedDate ?? now);
  const iso = toISODate(targetDate);
  const items = [
    ...tasks
      .filter((task) => toISODate(task.due ?? task.start ?? '') === iso)
      .map((task) => ({
        id: task.id,
        title: task.title,
        due: task.due ?? targetDate,
        end: task.due ?? (task.start ? new Date(new Date(task.start).getTime() + (task.estimatedDuration ?? 60) * 60000) : targetDate),
        start: task.start,
        duration: task.estimatedDuration ?? 60,
        source: 'Task',
        priority: task.priority,
        history: task.history ?? [],
        isCompleted: task.isCompleted
      })),
    ...assignments
      .filter((assignment) => toISODate(assignment.due) === iso)
      .map((assignment) => ({
        id: assignment.id,
        title: assignment.title,
        due: assignment.due,
        end: assignment.end ?? assignment.due,
        start: assignment.due,
        duration: assignment.estimatedDuration ?? 60,
        source: 'Assignment',
        priority: assignment.priority,
        history: assignment.history ?? [],
        isCompleted: assignment.isCompleted
      })),
    ...taskSegments
      .filter((seg) => toISODate(seg.due ?? seg.start ?? '') === iso)
      .map((seg) => ({
        id: seg.id,
        title: seg.title,
        due: seg.due ?? targetDate,
        end: seg.due ?? targetDate,
        start: seg.start ?? seg.due ?? targetDate,
        duration: seg.estimatedDuration ?? 60,
        source: 'Task segment',
        priority: seg.priority,
        history: seg.history ?? []
      })),
    ...assignmentSegments
      .filter((seg) => toISODate(seg.due ?? seg.start ?? '') === iso)
      .map((seg) => ({
        id: seg.id,
        title: seg.title,
        due: seg.due ?? targetDate,
        end: seg.due ?? targetDate,
        start: seg.start ?? seg.due ?? targetDate,
        duration: seg.estimatedDuration ?? 60,
        source: 'Assignment segment',
        priority: seg.priority,
        history: seg.history ?? []
      }))
  ].sort((a, b) => new Date(a.due) - new Date(b.due));

  listEl.innerHTML = '';
  if (!items.length) {
    listEl.innerHTML = '<li class="empty-state">No countdown items for this day.</li>';
    return;
  }

  items.forEach((item) => {
    const dueDate = new Date(item.due);
    const endDate = item.end ? new Date(item.end) : dueDate;
    const remainingMs = endDate - now;
    const remainingText = remainingMs > 0 ? formatRemaining(remainingMs) : 'Past due';
    const startText = item.start ? `Starts ${formatTimeRange(new Date(item.start), new Date(item.start))}` : '';
    const meta = [item.source, startText, `Due ${LONG_DAY_FORMATTER.format(endDate)}`]
      .filter(Boolean)
      .join(' • ');
    const elapsedText = renderTaskTimerLabel({ history: item.history ?? [] });
    const isAssignment = item.source === 'Assignment';
    const isTask = item.source === 'Task';
    const completedBadge = item.isCompleted ? '<span class="status-pill done">Done</span>' : '';

    const li = document.createElement('li');
    li.className = 'countdown-item';
    li.innerHTML = `
      <div class="countdown-title">${escapeHtml(item.title)}</div>
      <div class="countdown-meta">
        <span>${escapeHtml(meta)}</span>
        <span>Est. ${item.duration}m</span>
        ${completedBadge}
      </div>
      <div class="countdown-remaining">Elapsed ${escapeHtml(elapsedText)}</div>
      <div class="countdown-remaining">${escapeHtml(remainingText)}</div>
      ${
        isAssignment
          ? `<div class="task-actions">
              <button type="button" class="ghost-button" data-action="start-assignment" data-assignment-id="${item.id ?? ''}">Start</button>
              <button type="button" class="ghost-button" data-action="pause-assignment" data-assignment-id="${item.id ?? ''}">Pause</button>
              <button type="button" class="ghost-button" data-action="finish-assignment" data-assignment-id="${item.id ?? ''}">Done</button>
            </div>`
          : isTask
              ? `<div class="task-actions">
                  <button type="button" class="ghost-button" data-action="start-task" data-task-id="${item.id ?? ''}">Start</button>
                  <button type="button" class="ghost-button" data-action="pause-task" data-task-id="${item.id ?? ''}">Pause</button>
                  <button type="button" class="ghost-button" data-action="finish-task" data-task-id="${item.id ?? ''}">Done</button>
                  <button type="button" class="ghost-button" data-action="edit-task-modal" data-task-id="${item.id ?? ''}">Edit</button>
                </div>`
              : ''
      }
    `;
    listEl.append(li);
  });
}

function formatRemaining(ms) {
  const seconds = Math.max(0, Math.floor(ms / 1000));
  const hours = Math.floor(seconds / 3600);
  const minutes = Math.floor((seconds % 3600) / 60);
  const secs = seconds % 60;
  const parts = [];
  if (hours > 0) parts.push(`${hours}h`);
  parts.push(`${minutes}m`);
  parts.push(`${secs}s`);
  return `${parts.join(' ')} left`;
}

function handleAgendaClick(event) {
  const source = event.metadata?.source;
  const id = event.metadata?.id;
  if (source === 'task' && id) {
    const target = document.querySelector(`[data-task-id="${id}"]`);
    if (target) {
      target.scrollIntoView({ behavior: 'smooth', block: 'center' });
      target.classList.add('highlight');
      setTimeout(() => target.classList.remove('highlight'), 1200);
    }
  }
}

export function renderAssignments(listEl, assignments = [], segments = []) {
  if (!listEl) return;
  listEl.innerHTML = '';
  if (!assignments.length) {
    listEl.innerHTML = '<li class="empty-state">Import your Canvas ICS to see assignments.</li>';
    return;
  }

  const sorted = [...assignments].sort((a, b) => (new Date(a.due || 0) - new Date(b.due || 0)));
  sorted.forEach((assignment) => {
    const segmentList = segments.filter((seg) => seg.assignmentId === assignment.id);
    const dueText = assignment.allDay ? formatDateOnly(assignment.due) + ' • All day' : formatDateDisplay(assignment.due);
    const duration = assignment.estimatedDuration ?? 0;
    const completed = assignment.isCompleted;
    const course = assignment.course ? `<span class="pill">${escapeHtml(assignment.course)}</span>` : '';
    const status = completed ? '<span class="status-pill done">Done</span>' : '';
    const isRunning = assignment.history?.some((h) => h.startedAt && !h.stoppedAt);
    const timerLabel = assignment.history?.length ? renderTaskTimerLabel(assignment) : '';
    const segmentHtml = segmentList
      .map(
        (seg) => `
        <li class="segment-row">
          <label class="checkbox">
            <input type="checkbox" data-action="toggle-segment" data-segment-id="${seg.id}" ${
              seg.isCompleted ? 'checked' : ''
            } />
            <span>${escapeHtml(seg.title)}</span>
          </label>
          <div class="segment-meta">
            ${seg.due ? escapeHtml(formatDateDisplay(seg.due)) : 'No due'}
            ${seg.estimatedDuration ? `• ${seg.estimatedDuration}m` : ''}
            ${seg.history?.length ? `• ${escapeHtml(renderTaskTimerLabel(seg))}` : ''}
          </div>
          <div class="task-actions">
            <button type="button" data-action="start-segment" data-segment-id="${seg.id}" class="ghost-button">Start</button>
            <button type="button" data-action="pause-segment" data-segment-id="${seg.id}" class="ghost-button">Pause</button>
            <button type="button" data-action="finish-segment" data-segment-id="${seg.id}" class="ghost-button">Done</button>
            <button type="button" class="ghost-button" data-action="delete-segment" data-segment-id="${seg.id}">Remove</button>
          </div>
        </li>
      `
      )
      .join('');

    listEl.insertAdjacentHTML(
      'beforeend',
      `
      <li class="assignment-card" data-assignment-id="${assignment.id}">
        <div class="assignment-header">
          <div>
            <button type="button" class="ghost-button" data-action="toggle-assignment" data-assignment-id="${assignment.id}">
              ${completed ? 'Mark incomplete' : 'Mark complete'}
            </button>
            ${status}
          </div>
          <div class="assignment-meta">
            <span>${escapeHtml(assignment.title)}</span>
            ${course}
            <span class="muted">Due ${escapeHtml(dueText)}</span>
          </div>
        </div>
        <div class="assignment-body">
          ${assignment.description ? `<p class="muted">${escapeHtml(assignment.description)}</p>` : ''}
          ${assignment.location ? `<p class="muted"><strong>Location:</strong> ${escapeHtml(assignment.location)}</p>` : ''}
          <div class="task-actions">
            <button type="button" data-action="start-assignment" data-assignment-id="${assignment.id}" class="ghost-button">
              ${isRunning ? 'Resume' : 'Start'}
            </button>
            <button type="button" data-action="pause-assignment" data-assignment-id="${assignment.id}" class="ghost-button">Pause</button>
            <button type="button" data-action="finish-assignment" data-assignment-id="${assignment.id}" class="ghost-button">Done</button>
          </div>
          ${timerLabel ? `<div class="countdown-meta">Elapsed: ${escapeHtml(timerLabel)}</div>` : ''}
          <div class="field-row compact">
            <label>Duration (min)</label>
            <input type="number" min="0" step="15" value="${duration}" data-action="update-duration" data-assignment-id="${assignment.id}" />
          </div>
          ${assignment.url ? `<a class="muted" href="${escapeHtml(assignment.url)}" target="_blank" rel="noreferrer">Open in Canvas</a>` : ''}
        </div>
        <details class="assignment-edit">
          <summary>Edit details</summary>
          <form class="assignment-edit-form" data-assignment-id="${assignment.id}">
            <div class="field">
              <label>Title</label>
              <input name="title" value="${escapeHtml(assignment.title)}" />
            </div>
            <div class="field">
              <label>Course</label>
              <input name="course" value="${escapeHtml(assignment.course ?? '')}" />
            </div>
            <div class="field">
              <label>Location</label>
              <input name="location" value="${escapeHtml(assignment.location ?? '')}" />
            </div>
            <div class="field">
              <label>Duration (min)</label>
              <input name="duration" type="number" min="0" step="15" value="${duration}" />
            </div>
            <div class="field">
              <label><input type="checkbox" name="allDay" ${assignment.allDay ? 'checked' : ''} /> All day</label>
            </div>
            <div class="field" data-time-row>
              <label>Due</label>
              <input name="due" type="${assignment.allDay ? 'date' : 'datetime-local'}" value="${
                assignment.due ? toInputValue(assignment.due, assignment.allDay) : ''
              }" />
            </div>
            <div class="field">
              <label>Canvas URL</label>
              <input name="url" type="url" value="${escapeHtml(assignment.url ?? '')}" />
            </div>
            <div class="field">
              <label>Description</label>
              <textarea name="description">${escapeHtml(assignment.description ?? '')}</textarea>
            </div>
            <button type="submit" class="ghost-button">Save</button>
          </form>
        </details>
        <div class="segments">
          <h4>Segments</h4>
          <ul class="segment-list">
            ${segmentHtml || '<li class="muted">No segments yet.</li>'}
          </ul>
          <form class="segment-form" data-assignment-id="${assignment.id}">
            <input name="title" placeholder="Add a segment" required />
            <input name="due" type="date" />
            <input name="minutes" type="number" min="0" step="15" placeholder="mins" />
            <button type="submit" class="ghost-button">Add</button>
          </form>
        </div>
      </li>
    `
    );
  });
}

// ---- helpers ----

function buildMonthMatrix(anchor = new Date()) {
  const first = new Date(anchor.getFullYear(), anchor.getMonth(), 1);
  const start = new Date(first);
  start.setDate(first.getDate() - first.getDay());
  const result = [];
  for (let i = 0; i < 42; i += 1) {
    const date = new Date(start);
    date.setDate(start.getDate() + i);
    result.push({ date, isCurrentMonth: date.getMonth() === anchor.getMonth() });
  }
  return result;
}

function buildScheduleMarkers(schedule, tasks = [], assignments = [], segments = []) {
  const markers = new Map();
  (schedule ?? []).forEach((item) => {
    const iso = toISODate(new Date(item.start));
    markers.set(iso, (markers.get(iso) ?? 0) + 1);
  });
  tasks.forEach((task) => {
    const iso = toISODate(task.due ?? task.start);
    if (!iso) return;
    markers.set(iso, (markers.get(iso) ?? 0) + 1);
  });
  assignments.forEach((assignment) => {
    const iso = toISODate(assignment.due);
    if (!iso) return;
    markers.set(iso, (markers.get(iso) ?? 0) + 1);
  });
  segments.forEach((seg) => {
    const iso = toISODate(seg.due ?? seg.start);
    if (!iso) return;
    markers.set(iso, (markers.get(iso) ?? 0) + 1);
  });
  return markers;
}

function formatRoutineBlock(block) {
  if (!block) return 'Every day';
  const start = new Date(block.start);
  const end = new Date(block.end);
  const day = WEEKDAY_LABELS[start.getDay()];
  return `${day} • ${formatTimeRange(start, end)}`;
}

function renderRoutineTimeline(routine) {
  const days = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
  const blocksByDay = new Map();
  (routine.blocks ?? []).forEach((block) => {
    const start = new Date(block.start);
    const end = new Date(block.end);
    const day = start.getDay();
    if (!blocksByDay.has(day)) blocksByDay.set(day, []);
    blocksByDay.get(day).push({ start, end, context: block.context });
  });

  return days
    .map((label, idx) => {
      const dayBlocks = blocksByDay.get(idx) ?? [];
      const bars = dayBlocks
        .map((block) => {
          const duration = Math.max(0.25, (block.end - block.start) / (60 * 60 * 1000));
          const offset = (block.start.getHours() + block.start.getMinutes() / 60) / 24;
          const width = Math.min(1, duration / 24);
          const color = routine.color ?? '#60a5fa';
          return `<div class="routine-block" style="background:${color}30;"><span style="color:${color}; left:${Math.min(
            80,
            offset * 100
          )}%">${escapeHtml(routine.icon ?? '🔁')}</span><div style="width:${width * 100}%; background:${color}; height:100%; opacity:0.75;"></div></div>`;
        })
        .join('') || '<div class="routine-block" style="background:rgba(255,255,255,0.1);"></div>';
      return `<div class="routine-day"><label>${label}</label>${bars}</div>`;
    })
    .join('');
}

function formatTimeRange(start, end) {
  if (!start || !end) return 'All day';
  const startLabel = TIME_FORMATTER.format(start);
  const endLabel = TIME_FORMATTER.format(end);
  return `${startLabel} – ${endLabel}`;
}

function toISODate(value) {
  const date = value instanceof Date ? value : new Date(value);
  if (Number.isNaN(date.getTime())) return '';
  const year = date.getFullYear();
  const month = String(date.getMonth() + 1).padStart(2, '0');
  const day = String(date.getDate()).padStart(2, '0');
  return `${year}-${month}-${day}`;
}

function normalizeDate(value) {
  if (value instanceof Date && !Number.isNaN(value.getTime())) return value;
  const parsed = new Date(value ?? Date.now());
  if (Number.isNaN(parsed.getTime())) return new Date();
  return parsed;
}

function capitalize(text = '') {
  return text.charAt(0).toUpperCase() + text.slice(1);
}

function escapeHtml(value = '') {
  return value
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

function formatDateDisplay(value) {
  const date = value instanceof Date ? value : new Date(value);
  if (Number.isNaN(date.getTime())) return 'No due date';
  return LONG_DAY_FORMATTER.format(date);
}

function formatDateOnly(value) {
  const date = value instanceof Date ? value : new Date(value);
  if (Number.isNaN(date.getTime())) return 'No due date';
  return date.toLocaleDateString();
}

function renderTaskTimerLabel(task) {
  const history = Array.isArray(task.history) ? task.history : [];
  let elapsedMs = 0;
  history.forEach((entry) => {
    const start = entry.startedAt ? new Date(entry.startedAt) : null;
    const stop = entry.stoppedAt ? new Date(entry.stoppedAt) : null;
    if (start) {
      const end = stop ?? new Date();
      elapsedMs += Math.max(0, end - start);
    }
  });
  const totalSeconds = Math.floor(elapsedMs / 1000);
  const hours = Math.floor(totalSeconds / 3600);
  const minutes = Math.floor((totalSeconds % 3600) / 60);
  const seconds = totalSeconds % 60;
  const active = history.some((h) => h.startedAt && !h.stoppedAt);
  const parts = [];
  if (hours > 0) parts.push(`${hours}h`);
  parts.push(`${minutes}m`);
  parts.push(`${seconds}s`);
  return parts.join(' ') + (active ? ' (running)' : '');
}

function toInputValue(dateValue, allDay = false) {
  const d = dateValue instanceof Date ? dateValue : new Date(dateValue);
  if (Number.isNaN(d.getTime())) return '';
  if (allDay) {
    return d.toISOString().slice(0, 10);
  }
  const offset = d.getTimezoneOffset();
  const local = new Date(d.getTime() - offset * 60000);
  return local.toISOString().slice(0, 16);
}

export function renderActiveTracking({ listEl, tasks = [], taskSegments = [], assignments = [], assignmentSegments = [] }) {
  if (!listEl) return;
  listEl.innerHTML = '';
  const items = [];

  tasks
    .filter((t) => t.history?.some((h) => h.startedAt && !h.stoppedAt))
    .forEach((t) => items.push({ title: t.title, source: 'Todo', timer: renderTaskTimerLabel(t) }));
  assignments
    .filter((a) => a.history?.some((h) => h.startedAt && !h.stoppedAt))
    .forEach((a) => items.push({ title: a.title, source: 'Assignment', timer: renderTaskTimerLabel(a) }));
  taskSegments
    .filter((s) => s.history?.some((h) => h.startedAt && !h.stoppedAt))
    .forEach((s) => items.push({ title: s.title, source: 'Todo segment', timer: renderTaskTimerLabel(s) }));
  assignmentSegments
    .filter((s) => s.history?.some((h) => h.startedAt && !h.stoppedAt))
    .forEach((s) => items.push({ title: s.title, source: 'Assignment segment', timer: renderTaskTimerLabel(s) }));

  if (!items.length) {
    listEl.innerHTML = '<li class="empty-state">No active timers.</li>';
    return;
  }

  items.forEach((item) => {
    const li = document.createElement('li');
    li.className = 'active-item';
    li.innerHTML = `
      <div class="task-header">
        <span class="task-title">${escapeHtml(item.title)}</span>
        <span class="task-category">${escapeHtml(item.source)}</span>
      </div>
      <div class="task-meta">${escapeHtml(item.timer)}</div>
    `;
    listEl.append(li);
  });
}
