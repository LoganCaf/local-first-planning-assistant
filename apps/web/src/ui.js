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

export function renderCalendar({ monthLabelEl, weekdayHeaderEl, gridEl, calendarMonth, selectedDate, schedule }) {
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
  const markers = buildScheduleMarkers(schedule ?? []);
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

export function renderAgenda({ listEl, emptyEl, schedule, selectedDate }) {
  if (!listEl || !emptyEl) return;
  const iso = toISODate(selectedDate ?? new Date());
  const events = (schedule ?? [])
    .map((item) => ({
      ...item,
      start: new Date(item.start),
      end: new Date(item.end)
    }))
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

export function renderTasks(listEl, tasks = [], activeFilter = 'all') {
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
    .sort((a, b) => (b.priority ?? 0) - (a.priority ?? 0))
    .forEach((task) => {
      const li = document.createElement('li');
      li.className = 'task-item';
      const duration = `${task.estimatedDuration ?? 60} min`;
      const categoryLabel = capitalize(task.category ?? 'general');
      li.innerHTML = `
        <div class="task-header">
          <span class="task-title">${escapeHtml(task.title)}</span>
          <span class="task-category">${escapeHtml(categoryLabel)}</span>
        </div>
        <div class="task-meta">${duration} • Priority ${task.priority ?? 3}</div>
        <div class="task-actions">
          <button type="button" data-task-id="${task.id}" class="ghost-button">Delete</button>
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
    li.innerHTML = `
      <div class="routine-header">
        <span class="routine-name">${escapeHtml(routine.name ?? 'Routine')}</span>
        <button type="button" class="ghost-button" data-routine-id="${routine.id}">Remove</button>
      </div>
      <div class="routine-schedule">${blocks.join('<br />')}</div>
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

function buildScheduleMarkers(schedule) {
  const markers = new Map();
  (schedule ?? []).forEach((item) => {
    const iso = toISODate(new Date(item.start));
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

function formatTimeRange(start, end) {
  if (!start || !end) return 'All day';
  const startLabel = TIME_FORMATTER.format(start);
  const endLabel = TIME_FORMATTER.format(end);
  return `${startLabel} – ${endLabel}`;
}

function toISODate(value) {
  const date = value instanceof Date ? value : new Date(value);
  if (Number.isNaN(date.getTime())) return '';
  return date.toISOString().slice(0, 10);
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
