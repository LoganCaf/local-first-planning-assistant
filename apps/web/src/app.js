import { api } from './api.js';
import { state, setState, subscribe } from './state.js';
import {
  renderCalendar,
  renderAgenda,
  renderInsightCards,
  renderTasks,
  updateTaskFilters,
  renderRoutines,
  renderAssistantHistory,
  updateActiveTab,
  formatSelectedHeading
} from './ui.js';

const elements = {
  statusText: document.getElementById('connection-status'),
  statusDot: document.getElementById('connection-dot'),
  monthLabel: document.getElementById('calendar-month-label'),
  weekdayRow: document.getElementById('calendar-weekdays'),
  calendarGrid: document.getElementById('calendar-grid'),
  calendarPrev: document.getElementById('calendar-prev'),
  calendarNext: document.getElementById('calendar-next'),
  calendarToday: document.getElementById('calendar-today'),
  agendaTitle: document.getElementById('agenda-title'),
  agendaList: document.getElementById('agenda-list'),
  agendaEmpty: document.getElementById('agenda-empty'),
  regeneratePlan: document.getElementById('regenerate-plan'),
  insightCards: document.getElementById('insight-cards'),
  taskForm: document.getElementById('task-form'),
  taskList: document.getElementById('task-list'),
  taskFilters: document.getElementById('task-filters'),
  routineForm: document.getElementById('routine-form'),
  routineList: document.getElementById('routine-list'),
  assistantLog: document.getElementById('assistant-log'),
  assistantForm: document.getElementById('assistant-form'),
  assistantInput: document.getElementById('assistant-input'),
  tabBar: document.querySelector('.tab-bar')
};

const views = Array.from(document.querySelectorAll('[data-view]'));
const tabButtons = Array.from(document.querySelectorAll('[data-tab]'));

subscribe((snapshot) => {
  updateConnectionStatus(snapshot.connection);
  renderCalendar({
    monthLabelEl: elements.monthLabel,
    weekdayHeaderEl: elements.weekdayRow,
    gridEl: elements.calendarGrid,
    calendarMonth: snapshot.calendarMonth,
    selectedDate: snapshot.selectedDate,
    schedule: snapshot.schedule
  });
  if (elements.agendaTitle) {
    elements.agendaTitle.textContent = formatSelectedHeading(snapshot.selectedDate);
  }
  renderAgenda({
    listEl: elements.agendaList,
    emptyEl: elements.agendaEmpty,
    schedule: snapshot.schedule,
    selectedDate: snapshot.selectedDate
  });
  renderInsightCards(elements.insightCards, snapshot.insights);
  updateTaskFilters(elements.taskFilters, snapshot.taskFilter);
  renderTasks(elements.taskList, snapshot.tasks, snapshot.taskFilter);
  renderRoutines(elements.routineList, snapshot.routines);
  renderAssistantHistory(elements.assistantLog, snapshot.assistantHistory);
  updateActiveTab(snapshot.activeTab, views, tabButtons);
});

bootstrap();
registerEvents();

async function bootstrap() {
  await refreshConnection();
  await loadTasks();
  await loadRoutines();
  await refreshSchedule();
  await refreshInsights();
}

function registerEvents() {
  if (elements.tabBar) {
    elements.tabBar.addEventListener('click', (event) => {
      const target = event.target.closest('[data-tab]');
      if (!target) return;
      setState({ activeTab: target.dataset.tab });
    });
  }

  if (elements.taskFilters) {
    elements.taskFilters.addEventListener('click', (event) => {
      const button = event.target.closest('[data-filter]');
      if (!button) return;
      setState({ taskFilter: button.dataset.filter });
    });
  }

  if (elements.calendarPrev) {
    elements.calendarPrev.addEventListener('click', () => {
      const month = new Date(state.calendarMonth);
      month.setMonth(month.getMonth() - 1);
      setState({ calendarMonth: month });
    });
  }

  if (elements.calendarNext) {
    elements.calendarNext.addEventListener('click', () => {
      const month = new Date(state.calendarMonth);
      month.setMonth(month.getMonth() + 1);
      setState({ calendarMonth: month });
    });
  }

  if (elements.calendarToday) {
    elements.calendarToday.addEventListener('click', () => {
      const today = new Date();
      setState({ selectedDate: today, calendarMonth: new Date(today.getFullYear(), today.getMonth(), 1) });
    });
  }

  if (elements.calendarGrid) {
    elements.calendarGrid.addEventListener('click', (event) => {
      const cell = event.target.closest('[data-date]');
      if (!cell) return;
      const targetDate = new Date(cell.dataset.date);
      if (Number.isNaN(targetDate.getTime())) return;
      setState({
        selectedDate: targetDate,
        calendarMonth: new Date(targetDate.getFullYear(), targetDate.getMonth(), 1)
      });
    });
  }

  if (elements.regeneratePlan) {
    elements.regeneratePlan.addEventListener('click', async () => {
      pushAssistantMessage('ai', 'Regenerating your plan...');
      await refreshSchedule();
      await refreshInsights();
      pushAssistantMessage('ai', 'Schedule updated. Let me know if you need adjustments.');
    });
  }

  if (elements.taskForm) {
    elements.taskForm.addEventListener('submit', async (event) => {
      event.preventDefault();
      const data = new FormData(elements.taskForm);
      const title = (data.get('title') || '').toString().trim();
      if (!title) return;
      const category = (data.get('category') || 'general').toString().toLowerCase();
      const notes = (data.get('notes') || '').toString().trim();
      const payload = {
        title,
        description: notes || undefined,
        estimatedDuration: Number(data.get('duration') || 60),
        priority: Number(data.get('priority') || 3),
        tags: category === 'all' ? [] : [category]
      };
      const due = (data.get('due') || '').toString();
      if (due) payload.due = new Date(`${due}T00:00:00`);
      await api.createTask(payload);
      elements.taskForm.reset();
      await loadTasks();
      await refreshSchedule();
      await refreshInsights();
    });
  }

  if (elements.taskList) {
    elements.taskList.addEventListener('click', async (event) => {
      const button = event.target.closest('[data-task-id]');
      if (!button) return;
      await api.deleteTask(button.dataset.taskId);
      await loadTasks();
      await refreshSchedule();
      await refreshInsights();
    });
  }

  if (elements.routineForm) {
    elements.routineForm.addEventListener('submit', async (event) => {
      event.preventDefault();
      const data = new FormData(elements.routineForm);
      const name = (data.get('name') || '').toString().trim() || 'Routine';
      const startTime = (data.get('start') || '').toString();
      const endTime = (data.get('end') || '').toString();
      const days = data.getAll('day').map((value) => Number(value));
      const targetDays = days.length ? days : [new Date().getDay()];
      if (!startTime || !endTime) return;
      const blocks = targetDays.map((day) => buildRoutineBlock(day, startTime, endTime, name));
      await api.createRoutine({ name, blocks, active: true });
      elements.routineForm.reset();
      await loadRoutines();
      await refreshSchedule();
    });
  }

  if (elements.routineList) {
    elements.routineList.addEventListener('click', async (event) => {
      const button = event.target.closest('[data-routine-id]');
      if (!button) return;
      await api.deleteRoutine(button.dataset.routineId);
      await loadRoutines();
      await refreshSchedule();
    });
  }

  if (elements.assistantForm) {
    elements.assistantForm.addEventListener('submit', async (event) => {
      event.preventDefault();
      const message = elements.assistantInput.value.trim();
      if (!message) return;
      pushAssistantMessage('user', message);
      elements.assistantInput.value = '';
      await respondAssistant(message);
    });
  }
}

async function refreshConnection() {
  const health = await api.health().catch(() => null);
  setState({ connection: health ? 'online' : 'offline' });
}

async function loadTasks() {
  const payload = await api.listTasks().catch(() => ({ tasks: [] }));
  setState({ tasks: payload.tasks ?? [] });
}

async function loadRoutines() {
  const payload = await api.listRoutines().catch(() => ({ routines: [] }));
  setState({ routines: payload.routines ?? [] });
}

async function refreshSchedule() {
  const payload = await api.generateSchedule().catch(() => ({ scheduled: [], unscheduled: [] }));
  setState({ schedule: payload.scheduled ?? [], unscheduled: payload.unscheduled ?? [] });
}

async function refreshInsights() {
  const report = await api.weeklyReport(new Date()).catch(() => null);
  setState({ insights: report });
}

async function respondAssistant(message) {
  setState({ assistantPending: true });
  try {
    const history = [...state.assistantHistory];
    const response = await api.sendAssistantMessage(message, history);
    pushAssistantMessage('ai', response.reply ?? 'Noted. I will keep that in mind.');
  } catch (error) {
    console.error(error);
    pushAssistantMessage('ai', "I'm offline at the moment. Capture it as a task and I'll reschedule once I'm back.");
  } finally {
    setState({ assistantPending: false });
  }
}

function pushAssistantMessage(role, content) {
  const updated = [...state.assistantHistory, { role, content }];
  setState({ assistantHistory: updated });
}

function updateConnectionStatus(status) {
  if (!elements.statusText) return;
  const online = status === 'online';
  const offline = status === 'offline';
  let label = 'Checking connection';
  if (online) label = 'Online';
  if (offline) label = 'Offline';
  elements.statusText.textContent = label;
  elements.statusText.classList.remove('is-online', 'is-offline');
  if (online) elements.statusText.classList.add('is-online');
  if (offline) elements.statusText.classList.add('is-offline');
  if (elements.statusDot) {
    elements.statusDot.classList.remove('is-online', 'is-offline');
    if (online) elements.statusDot.classList.add('is-online');
    if (offline) elements.statusDot.classList.add('is-offline');
  }
}

function buildRoutineBlock(day, start, end, name) {
  const reference = getReferenceDateForDay(day);
  const startDate = composeDate(reference, start);
  const endDate = composeDate(reference, end);
  if (endDate <= startDate) {
    endDate.setDate(endDate.getDate() + 1);
  }
  return {
    start: startDate,
    end: endDate,
    context: name,
    locked: false
  };
}

function composeDate(reference, time) {
  const [hour, minute] = time.split(':').map(Number);
  const result = new Date(reference);
  result.setHours(hour ?? 0, minute ?? 0, 0, 0);
  return result;
}

function getReferenceDateForDay(day) {
  const base = new Date('2024-01-01T00:00:00');
  const offset = (day - base.getDay() + 7) % 7;
  const reference = new Date(base);
  reference.setDate(base.getDate() + offset);
  return reference;
}
