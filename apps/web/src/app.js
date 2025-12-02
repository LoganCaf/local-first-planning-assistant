import { api } from './api.js';
import { state, setState, subscribe } from './state.js';
import {
  renderCalendar,
  renderInsightCards,
  renderTasks,
  renderActiveTasks,
  updateTaskFilters,
  renderRoutines,
  renderAssistantHistory,
  renderAssignments,
  renderCountdowns,
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
  regeneratePlan: document.getElementById('regenerate-plan'),
  insightCards: document.getElementById('insight-cards'),
  taskForm: document.getElementById('task-form'),
  taskList: document.getElementById('task-list'),
  taskActiveList: document.getElementById('task-active-list'),
  taskFilters: document.getElementById('task-filters'),
  assignmentFile: document.getElementById('assignment-file'),
  assignmentImport: document.getElementById('assignment-import'),
  assignmentImportStatus: document.getElementById('assignment-import-status'),
  assignmentList: document.getElementById('assignment-list'),
  routineForm: document.getElementById('routine-form'),
  routineList: document.getElementById('routine-list'),
  assistantLog: document.getElementById('assistant-log'),
  assistantForm: document.getElementById('assistant-form'),
  assistantInput: document.getElementById('assistant-input'),
  openAiKeyInput: document.getElementById('openai-key'),
  openAiKeySave: document.getElementById('openai-key-save'),
  openAiKeyClear: document.getElementById('openai-key-clear'),
  openAiKeyStatus: document.getElementById('openai-key-status'),
  tabBar: document.querySelector('.tab-bar'),
  taskModal: document.getElementById('task-modal'),
  taskModalForm: document.getElementById('task-modal-form'),
  taskModalClose: document.getElementById('task-modal-close'),
  taskModalCancel: document.getElementById('task-modal-cancel')
};

const OPENAI_KEY_STORAGE = 'openai_api_key';
let openAIApiKey = loadStoredApiKey();

let countdownIntervalId;

const views = Array.from(document.querySelectorAll('[data-view]'));
const tabButtons = Array.from(document.querySelectorAll('[data-tab]'));

function switchTab(tab) {
  setState({ activeTab: tab });
  updateActiveTab(tab, views, tabButtons);
}

subscribe((snapshot) => {
  updateConnectionStatus(snapshot.connection);
  renderCalendar({
    monthLabelEl: elements.monthLabel,
    weekdayHeaderEl: elements.weekdayRow,
    gridEl: elements.calendarGrid,
    calendarMonth: snapshot.calendarMonth,
    selectedDate: snapshot.selectedDate,
    schedule: snapshot.schedule,
    tasks: snapshot.tasks,
    assignments: snapshot.assignments,
    segments: [...snapshot.taskSegments, ...snapshot.assignmentSegments]
  });
  if (elements.agendaTitle) {
    elements.agendaTitle.textContent = formatSelectedHeading(snapshot.selectedDate);
  }
  renderCountdowns({
    listEl: elements.agendaList,
    tasks: snapshot.tasks,
    taskSegments: snapshot.taskSegments,
    assignments: snapshot.assignments,
    assignmentSegments: snapshot.assignmentSegments,
    selectedDate: snapshot.selectedDate
  });
  renderInsightCards(elements.insightCards, snapshot.insights);
  updateTaskFilters(elements.taskFilters, snapshot.taskFilter);
  renderTasks(elements.taskList, snapshot.tasks, snapshot.taskSegments, snapshot.taskFilter);
  renderActiveTasks(elements.taskActiveList, snapshot.tasks);
  renderAssignments(elements.assignmentList, snapshot.assignments, snapshot.assignmentSegments);
  renderRoutines(elements.routineList, snapshot.routines);
  renderAssistantHistory(elements.assistantLog, snapshot.assistantHistory);
  updateActiveTab(snapshot.activeTab, views, tabButtons);
});

bootstrap();
registerEvents();

async function bootstrap() {
  syncOpenAIKeyUI();
  await refreshConnection();
  await loadTasks();
  await loadTaskSegments();
  await loadAssignments();
  await loadAssignmentSegments();
  await loadRoutines();
  await refreshSchedule();
  await refreshInsights();
  startCountdownTicker();
}

function registerEvents() {
  if (elements.tabBar) {
    elements.tabBar.addEventListener('click', (event) => {
      const target = event.target.closest('[data-tab]');
      if (!target) return;
      switchTab(target.dataset.tab);
    });
  }

  if (elements.taskModalClose) {
    elements.taskModalClose.addEventListener('click', closeTaskModal);
  }
  if (elements.taskModalCancel) {
    elements.taskModalCancel.addEventListener('click', closeTaskModal);
  }

  const deadlineCheckbox = document.getElementById('task-has-deadline');
  const dueInput = document.getElementById('task-due');
  if (deadlineCheckbox && dueInput) {
    const syncDeadlineState = () => {
      dueInput.disabled = !deadlineCheckbox.checked;
    };
    deadlineCheckbox.addEventListener('change', syncDeadlineState);
    syncDeadlineState();
  }
  // ensure initial active tab styling even if a render fails elsewhere
  switchTab(state.activeTab);

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
      const targetDate = parseLocalISODate(cell.dataset.date);
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
      const start = (data.get('start') || '').toString();
      if (start) payload.start = new Date(start);
      const hasDeadline = data.get('hasDeadline') !== null;
      payload.hasDeadline = hasDeadline;
      const due = (data.get('due') || '').toString();
      if (hasDeadline && due) payload.due = new Date(due);
      await api.createTask(payload);
      elements.taskForm.reset();
      const deadlineCheckbox = document.getElementById('task-has-deadline');
      if (deadlineCheckbox) deadlineCheckbox.checked = true;
      await loadTasks();
      await refreshSchedule();
      await refreshInsights();
    });
  }

  if (elements.taskList) {
    elements.taskList.addEventListener('click', async (event) => {
      const deleteButton = event.target.closest('[data-task-id]');
      const toggleButton = event.target.closest('[data-action="toggle-complete"]');
      const startButton = event.target.closest('[data-action="start-task"]');
      const pauseButton = event.target.closest('[data-action="pause-task"]');
      const doneButton = event.target.closest('[data-action="finish-task"]');
      const editButton = event.target.closest('[data-action="edit-task"]');
      const startSeg = event.target.closest('[data-action="start-task-segment"]');
      const pauseSeg = event.target.closest('[data-action="pause-task-segment"]');
      const finishSeg = event.target.closest('[data-action="finish-task-segment"]');
      const deleteSeg = event.target.closest('[data-action="delete-task-segment"]');
      const toggleSeg = event.target.closest('[data-action="toggle-task-segment"]');

      if (toggleButton) {
        await toggleTaskCompletion(toggleButton.dataset.taskId);
        return;
      }

      if (startButton) {
        await api.updateTaskTimer(startButton.dataset.taskId, 'start');
        await loadTasks();
        return;
      }

      if (pauseButton) {
        await api.updateTaskTimer(pauseButton.dataset.taskId, 'pause');
        await loadTasks();
        return;
      }

      if (doneButton) {
        await api.updateTaskTimer(doneButton.dataset.taskId, 'complete');
        await loadTasks();
        await refreshSchedule();
        await refreshInsights();
        return;
      }

      if (editButton) {
        await promptEditTask(editButton.dataset.taskId);
        return;
      }

      if (startSeg) {
        await api.updateTaskSegmentTimer(startSeg.dataset.segmentId, 'start');
        await loadTaskSegments();
        return;
      }

      if (pauseSeg) {
        await api.updateTaskSegmentTimer(pauseSeg.dataset.segmentId, 'pause');
        await loadTaskSegments();
        return;
      }

      if (finishSeg) {
        await api.updateTaskSegmentTimer(finishSeg.dataset.segmentId, 'complete');
        await loadTaskSegments();
        return;
      }

      if (toggleSeg) {
        await api.updateTaskSegment({ ...state.taskSegments.find((s) => s.id === toggleSeg.dataset.segmentId), isCompleted: toggleSeg.checked });
        await loadTaskSegments();
        return;
      }

      if (deleteSeg) {
        await api.deleteTaskSegment(deleteSeg.dataset.segmentId);
        await loadTaskSegments();
        return;
      }

      if (deleteButton) {
        await api.deleteTask(deleteButton.dataset.taskId);
        await loadTasks();
        await loadTaskSegments();
        await refreshSchedule();
        await refreshInsights();
      }
    });

    elements.taskList.addEventListener('change', async (event) => {
      const editForm = event.target.closest('.task-edit-form');
      if (editForm && event.target.name === 'hasDeadline') {
        const timeRow = editForm.querySelector('[data-time-row]');
        if (timeRow) {
          timeRow.style.display = event.target.checked ? 'grid' : 'none';
        }
      }
    });

    elements.taskList.addEventListener('submit', async (event) => {
      const editForm = event.target.closest('.task-edit-form');
      if (editForm) {
        event.preventDefault();
        const taskId = editForm.dataset.taskId;
        const formData = new FormData(editForm);
        const current = state.tasks.find((t) => t.id === taskId);
        if (!current) return;
        const updated = { ...current };
        updated.title = formData.get('title')?.toString().trim() || updated.title;
        updated.description = formData.get('description')?.toString() || '';
        const dur = Number(formData.get('duration') || updated.estimatedDuration || 0);
        updated.estimatedDuration = Number.isNaN(dur) ? 0 : dur;
        const pri = Number(formData.get('priority') || updated.priority || 3);
        updated.priority = Number.isNaN(pri) ? updated.priority : pri;
        updated.hasDeadline = formData.get('hasDeadline') === 'on';
        const due = formData.get('due')?.toString();
        if (updated.hasDeadline && due) {
          updated.due = new Date(due);
        } else if (!updated.hasDeadline) {
          updated.due = null;
        }
        const start = formData.get('start')?.toString();
        if (start) {
          updated.start = new Date(start);
        }
        await api.updateTask(updated);
        await loadTasks();
        return;
      }

      const segmentForm = event.target.closest('.segment-form');
      if (segmentForm && segmentForm.dataset.taskId) {
        event.preventDefault();
        const taskId = segmentForm.dataset.taskId;
        const formData = new FormData(segmentForm);
        const title = (formData.get('title') || '').toString().trim();
        if (!title) return;
        const due = formData.get('due');
        const minutes = Number(formData.get('minutes') || 0);
        await api.createTaskSegment({
          taskId,
          title,
          due: due ? new Date(`${due}T00:00:00`) : null,
          estimatedDuration: minutes > 0 ? minutes : 0
        });
        segmentForm.reset();
        await loadTaskSegments();
        return;
      }
    });
  }

  if (elements.agendaList) {
    elements.agendaList.addEventListener('click', async (event) => {
      const button = event.target.closest('button[data-action]');
      if (button) {
        event.stopPropagation();
        const action = button.dataset.action;
        if (action === 'start-assignment') {
          await api.updateAssignmentTimer(button.dataset.assignmentId, 'start');
          await loadAssignments();
          return;
        }
        if (action === 'pause-assignment') {
          await api.updateAssignmentTimer(button.dataset.assignmentId, 'pause');
          await loadAssignments();
          return;
        }
        if (action === 'finish-assignment') {
          await api.updateAssignmentTimer(button.dataset.assignmentId, 'complete');
          await loadAssignments();
          return;
        }
        if (action === 'start-task') {
          await api.updateTaskTimer(button.dataset.taskId, 'start');
          await loadTasks();
          return;
        }
        if (action === 'pause-task') {
          await api.updateTaskTimer(button.dataset.taskId, 'pause');
          await loadTasks();
          return;
        }
        if (action === 'finish-task') {
          await api.updateTaskTimer(button.dataset.taskId, 'complete');
          await loadTasks();
          return;
        }
        if (action === 'edit-task-modal') {
          const task = state.tasks.find((t) => t.id === button.dataset.taskId);
          if (task) openTaskModal(task);
          return;
        }
        return;
      }

    });
  }

  if (elements.taskModalForm) {
    elements.taskModalForm.addEventListener('submit', async (event) => {
      event.preventDefault();
      const form = elements.taskModalForm;
      const id = form.elements.id.value;
      const existing = state.tasks.find((t) => t.id === id);
      if (!existing) return;
      const updated = { ...existing };
      updated.title = form.elements.title.value.trim() || existing.title;
      updated.description = form.elements.description.value.trim() || '';
      const dur = Number(form.elements.duration.value || existing.estimatedDuration || 0);
      updated.estimatedDuration = Number.isNaN(dur) ? 0 : dur;
      const pri = Number(form.elements.priority.value || existing.priority || 3);
      updated.priority = Number.isNaN(pri) ? existing.priority : pri;
      updated.hasDeadline = form.elements.hasDeadline.checked;
      const dueVal = form.elements.due.value;
      updated.due = dueVal ? new Date(dueVal) : null;
      const startVal = form.elements.start.value;
      updated.start = startVal ? new Date(startVal) : null;
      await api.updateTask(updated);
      await loadTasks();
      closeTaskModal();
    });
  }

  if (elements.routineForm) {
    elements.routineForm.addEventListener('submit', async (event) => {
      event.preventDefault();
      const data = new FormData(elements.routineForm);
      const name = (data.get('name') || '').toString().trim() || 'Routine';
      const icon = (data.get('icon') || '🔁').toString();
      const color = (data.get('color') || '#60a5fa').toString();
      const active = data.get('active') !== null;
      const startTime = (data.get('start') || '').toString();
      const endTime = (data.get('end') || '').toString();
      const days = data.getAll('day').map((value) => Number(value));
      const targetDays = days.length ? days : [new Date().getDay()];
      if (!startTime || !endTime) return;
      const blocks = targetDays.map((day) => buildRoutineBlock(day, startTime, endTime, name));
      await api.createRoutine({ name, blocks, active, icon, color });
      elements.routineForm.reset();
      await loadRoutines();
      await refreshSchedule();
    });
  }

  if (elements.routineList) {
    elements.routineList.addEventListener('click', async (event) => {
      const button = event.target.closest('[data-routine-id]');
      const toggle = event.target.closest('[data-action="toggle-routine"]');
      if (toggle) {
        const id = toggle.dataset.routineId;
        const routine = state.routines.find((r) => r.id === id);
        if (!routine) return;
        await api.updateRoutine({ ...routine, active: toggle.checked });
        await loadRoutines();
        await refreshSchedule();
        return;
      }
      if (button) {
        await api.deleteRoutine(button.dataset.routineId);
        await loadRoutines();
        await refreshSchedule();
      }
    });
  }

  if (elements.assignmentImport) {
    elements.assignmentImport.addEventListener('click', async () => {
      const file = elements.assignmentFile?.files?.[0];
      if (!file) {
        setImportStatus('Select an ICS file first.');
        return;
      }
      setImportStatus('Importing...');
      const text = await file.text();
      try {
        await api.importAssignments(text, file.name);
        await loadAssignments();
        await loadAssignmentSegments();
        setImportStatus('Imported assignments from ICS.');
      } catch (error) {
        console.error(error);
        setImportStatus('Failed to import ICS file.');
      }
    });
  }

  const assignmentRemoveAll = document.getElementById('assignment-remove-all');
  if (assignmentRemoveAll) {
    assignmentRemoveAll.addEventListener('click', async () => {
      if (!window.confirm('Remove all assignments? This cannot be undone.')) return;
      try {
        await api.deleteAllAssignments();
        await loadAssignments();
        await loadAssignmentSegments();
        setImportStatus('All assignments removed.');
      } catch (error) {
        console.error(error);
        setImportStatus('Failed to remove assignments.');
      }
    });
  }

  const assignmentImportURL = document.getElementById('assignment-import-url');
  const assignmentURLInput = document.getElementById('assignment-url');
  const assignmentSyncButton = document.getElementById('assignment-sync');

  if (assignmentImportURL && assignmentURLInput) {
    assignmentImportURL.addEventListener('click', async () => {
      const url = assignmentURLInput.value.trim();
      if (!url) {
        setImportStatus('Enter an ICS URL first.');
        return;
      }
      setImportStatus('Fetching ICS...');
      try {
        await api.importAssignments('', url, url);
        await loadAssignments();
        await loadAssignmentSegments();
        setImportStatus('Imported assignments from URL.');
      } catch (error) {
        console.error(error);
        setImportStatus('Failed to import from URL.');
      }
    });
  }

  if (assignmentSyncButton) {
    assignmentSyncButton.addEventListener('click', async () => {
      setImportStatus('Syncing...');
      try {
        await api.syncAssignments();
        await loadAssignments();
        await loadAssignmentSegments();
        setImportStatus('Synced assignments from stored URL.');
      } catch (error) {
        console.error(error);
        setImportStatus('Failed to sync assignments.');
      }
    });
  }

  if (elements.assignmentList) {
    elements.assignmentList.addEventListener('click', async (event) => {
      const toggle = event.target.closest('[data-action="toggle-assignment"]');
      if (toggle) {
        const id = toggle.dataset.assignmentId;
        await toggleAssignmentCompletion(id);
        return;
      }
      const startAssign = event.target.closest('[data-action="start-assignment"]');
      if (startAssign) {
        await api.updateAssignmentTimer(startAssign.dataset.assignmentId, 'start');
        await loadAssignments();
        return;
      }
      const pauseAssign = event.target.closest('[data-action="pause-assignment"]');
      if (pauseAssign) {
        await api.updateAssignmentTimer(pauseAssign.dataset.assignmentId, 'pause');
        await loadAssignments();
        return;
      }
      const finishAssign = event.target.closest('[data-action="finish-assignment"]');
      if (finishAssign) {
        await api.updateAssignmentTimer(finishAssign.dataset.assignmentId, 'complete');
        await loadAssignments();
        return;
      }
      const toggleSegment = event.target.closest('[data-action="toggle-segment"]');
      if (toggleSegment) {
        const id = toggleSegment.dataset.segmentId;
        await toggleSegmentCompletion(id);
        return;
      }
      const startSeg = event.target.closest('[data-action="start-segment"]');
      if (startSeg) {
        await api.updateAssignmentSegmentTimer(startSeg.dataset.segmentId, 'start');
        await loadAssignmentSegments();
        return;
      }
      const pauseSeg = event.target.closest('[data-action="pause-segment"]');
      if (pauseSeg) {
        await api.updateAssignmentSegmentTimer(pauseSeg.dataset.segmentId, 'pause');
        await loadAssignmentSegments();
        return;
      }
      const finishSeg = event.target.closest('[data-action="finish-segment"]');
      if (finishSeg) {
        await api.updateAssignmentSegmentTimer(finishSeg.dataset.segmentId, 'complete');
        await loadAssignmentSegments();
        return;
      }
      const deleteSegment = event.target.closest('[data-action="delete-segment"]');
      if (deleteSegment) {
        const id = deleteSegment.dataset.segmentId;
        await api.deleteAssignmentSegment(id);
        await loadAssignmentSegments();
        return;
      }
    });

    elements.assignmentList.addEventListener('change', async (event) => {
      const durationInput = event.target.closest('[data-action="update-duration"]');
      if (durationInput) {
        const id = durationInput.dataset.assignmentId;
        const minutes = Number(durationInput.value);
        await updateAssignmentDuration(id, minutes);
      }
      const editForm = event.target.closest('.assignment-edit-form');
      if (editForm && event.target.name === 'allDay') {
        const timeRow = editForm.querySelector('[data-time-row]');
        if (timeRow) {
          timeRow.style.display = event.target.checked ? 'none' : 'grid';
        }
      }
    });

    elements.assignmentList.addEventListener('submit', async (event) => {
      const segmentForm = event.target.closest('.segment-form');
      if (segmentForm) {
        event.preventDefault();
        const assignmentId = segmentForm.dataset.assignmentId;
        const formData = new FormData(segmentForm);
        const title = (formData.get('title') || '').toString().trim();
        if (!title) return;
        const due = formData.get('due');
        const minutes = Number(formData.get('minutes') || 0);
        await api.createAssignmentSegment({
          assignmentId,
          title,
          due: due ? new Date(`${due}T00:00:00`) : null,
          estimatedDuration: minutes > 0 ? minutes : 0
        });
        segmentForm.reset();
        await loadAssignmentSegments();
        return;
      }

      const editForm = event.target.closest('.assignment-edit-form');
      if (editForm) {
        event.preventDefault();
        const assignmentId = editForm.dataset.assignmentId;
        const formData = new FormData(editForm);
        const current = state.assignments.find((a) => a.id === assignmentId);
        if (!current) return;
        const updated = { ...current };
        updated.title = formData.get('title')?.toString().trim() || updated.title;
        updated.course = formData.get('course')?.toString().trim() || '';
        updated.location = formData.get('location')?.toString().trim() || '';
        updated.description = formData.get('description')?.toString() || '';
        updated.url = formData.get('url')?.toString().trim() || '';
        const duration = Number(formData.get('duration') || updated.estimatedDuration || 0);
        updated.estimatedDuration = Number.isNaN(duration) ? 0 : duration;
        const allDay = formData.get('allDay') === 'on';
        updated.allDay = allDay;
        const due = formData.get('due')?.toString();
        if (due) {
          updated.due = allDay ? new Date(`${due}T00:00:00`) : new Date(due);
          if (allDay) {
            const end = new Date(`${due}T00:00:00`);
            end.setHours(23, 59, 0, 0);
            updated.end = end;
          }
        }
        await api.updateAssignment(updated);
        await loadAssignments();
      }
    });
  }

  if (elements.openAiKeySave && elements.openAiKeyInput) {
    elements.openAiKeySave.addEventListener('click', () => {
      const value = elements.openAiKeyInput.value.trim();
      openAIApiKey = value;
      localStorage.setItem(OPENAI_KEY_STORAGE, value);
      syncOpenAIKeyUI();
    });
  }

  if (elements.openAiKeyClear) {
    elements.openAiKeyClear.addEventListener('click', () => {
      openAIApiKey = '';
      localStorage.removeItem(OPENAI_KEY_STORAGE);
      syncOpenAIKeyUI();
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

function startCountdownTicker() {
  if (countdownIntervalId) {
    clearInterval(countdownIntervalId);
  }
  countdownIntervalId = setInterval(() => {
    renderCountdowns({
      listEl: elements.agendaList,
      tasks: state.tasks,
      taskSegments: state.taskSegments,
      assignments: state.assignments,
      assignmentSegments: state.assignmentSegments,
      selectedDate: state.selectedDate
    });
  }, 1000);
}

function parseLocalISODate(value) {
  if (!value) return new Date(NaN);
  const parts = value.split('-').map((p) => Number(p));
  if (parts.length < 3 || parts.some((n) => Number.isNaN(n))) return new Date(NaN);
  return new Date(parts[0], parts[1] - 1, parts[2]);
}

async function refreshConnection() {
  const health = await api.health().catch(() => null);
  setState({ connection: health ? 'online' : 'offline' });
}

async function loadTasks() {
  const payload = await api.listTasks().catch(() => ({ tasks: [] }));
  setState({ tasks: payload.tasks ?? [] });
}

async function loadTaskSegments() {
  const payload = await api.listTaskSegments().catch(() => ({ segments: [] }));
  setState({ taskSegments: payload.segments ?? [] });
}

async function loadAssignments() {
  const payload = await api.listAssignments().catch(() => ({ assignments: [], assignmentSync: null }));
  setState({ assignments: payload.assignments ?? [], assignmentSync: payload.assignmentSync ?? null });
}

async function loadAssignmentSegments() {
  const payload = await api.listAssignmentSegments().catch(() => ({ segments: [] }));
  setState({ assignmentSegments: payload.segments ?? [] });
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

async function toggleTaskCompletion(id) {
  const existing = state.tasks.find((t) => t.id === id);
  if (!existing) return;
  await api.updateTask({ ...existing, isCompleted: !existing.isCompleted });
  await loadTasks();
}

async function toggleTaskSegmentCompletion(id) {
  const existing = state.taskSegments.find((s) => s.id === id);
  if (!existing) return;
  await api.updateTaskSegment({ ...existing, isCompleted: !existing.isCompleted });
  await loadTaskSegments();
}

async function promptEditTask(id) {
  const existing = state.tasks.find((t) => t.id === id);
  if (!existing) return;
  const title = window.prompt('Update title', existing.title);
  if (title === null) return;
  const duration = window.prompt('Update duration (minutes)', existing.estimatedDuration ?? 60);
  const priority = window.prompt('Update priority (1-5)', existing.priority ?? 3);
  const payload = {
    ...existing,
    title: title.trim() || existing.title,
    estimatedDuration: Number(duration ?? existing.estimatedDuration ?? 60),
    priority: Number(priority ?? existing.priority ?? 3)
  };
  await api.updateTask(payload);
  await loadTasks();
}

async function respondAssistant(message) {
  setState({ assistantPending: true });
  try {
    const key = openAIApiKey.trim();
    if (key) {
      const result = await sendOpenAIChat(message, key);
      if (result.replyText) {
        pushAssistantMessage('ai', result.replyText);
      }
      if (result.actions?.length) {
        const summaries = await applyScheduleActions(result.actions);
        summaries.forEach((summary) => pushAssistantMessage('ai', summary));
      }
    } else {
      const history = [...state.assistantHistory];
      const response = await api.sendAssistantMessage(message, history);
      pushAssistantMessage('ai', response.reply ?? 'Noted. I will keep that in mind.');
    }
  } catch (error) {
    console.error(error);
    pushAssistantMessage('ai', "I'm offline at the moment. Capture it as a task and I'll reschedule once I'm back.");
  } finally {
    setState({ assistantPending: false });
  }
}

async function toggleAssignmentCompletion(id) {
  const existing = state.assignments.find((a) => a.id === id);
  if (!existing) return;
  await api.updateAssignment({ ...existing, isCompleted: !existing.isCompleted });
  await loadAssignments();
}

async function updateAssignmentDuration(id, minutes) {
  const existing = state.assignments.find((a) => a.id === id);
  if (!existing) return;
  const sanitized = Number.isNaN(minutes) || minutes < 0 ? 0 : Math.round(minutes);
  await api.updateAssignment({ ...existing, estimatedDuration: sanitized });
  await loadAssignments();
}

async function toggleSegmentCompletion(id) {
  const existing = state.assignmentSegments.find((s) => s.id === id);
  if (!existing) return;
  await api.updateAssignmentSegment({ ...existing, isCompleted: !existing.isCompleted });
  await loadAssignmentSegments();
}

function setImportStatus(message) {
  if (!elements.assignmentImportStatus) return;
  elements.assignmentImportStatus.textContent = message;
}

function openTaskModal(task) {
  if (!elements.taskModal || !elements.taskModalForm) return;
  elements.taskModal.classList.remove('hidden');
  const form = elements.taskModalForm;
  form.elements.id.value = task.id;
  form.elements.title.value = task.title;
  form.elements.description.value = task.description ?? '';
  form.elements.duration.value = task.estimatedDuration ?? task.estimatedDurationMinutes ?? 0;
  form.elements.priority.value = task.priority ?? 3;
  form.elements.hasDeadline.checked = task.hasDeadline !== false;
  form.elements.due.value = task.due ? toInputValue(task.due, false) : '';
  form.elements.start.value = task.start ? toInputValue(task.start, false) : '';
}

function closeTaskModal() {
  if (!elements.taskModal) return;
  elements.taskModal.classList.add('hidden');
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

function loadStoredApiKey() {
  return localStorage.getItem(OPENAI_KEY_STORAGE) ?? '';
}

function syncOpenAIKeyUI() {
  if (elements.openAiKeyInput) {
    elements.openAiKeyInput.value = openAIApiKey ? openAIApiKey : '';
  }
  if (elements.openAiKeyStatus) {
    elements.openAiKeyStatus.textContent = openAIApiKey
      ? 'Using OpenAI key (stored locally). Ask me to add or toggle tasks.'
      : 'No OpenAI key set. Using the local assistant fallback.';
  }
}

function buildSystemPrompt() {
  const now = new Date();
  const snapshot = buildScheduleSnapshot();
  return [
    `You are the "Local Planning Assistant" in a web app. Current local time: ${now.toString()}.`,
    'When a change is needed, include ONE <schedule_actions>...</schedule_actions> block containing a JSON object with optional "reply" and an "actions" array.',
    'Supported actions (all dates/times MUST be local, no timezone suffix or Z):',
    '- {"type":"todo.add","title":"Task","dueDate":"2025-12-04T18:00:00","startDate":"2025-12-04T17:00:00","priority":"high","durationMinutes":90}',
    '- {"type":"todo.toggle","identifier":"Task title or id"}',
    '- {"type":"assignment.setDuration","identifier":"Assignment title or id","durationMinutes":120}',
    'Strict JSON rules: valid JSON only, no comments, no trailing commas, all fields quoted. If no change is needed, omit the block entirely.',
    'Date rules: treat user-provided dates/times as local; DO NOT convert to UTC; DO NOT include timezone offsets or Z. Use "YYYY-MM-DDTHH:MM:SS".',
    'Defaults: if date is implied as today, use today with a sensible time; if duration is unclear, omit durationMinutes.',
    'Be concise in the visible reply.',
    'Snapshot of current items:',
    snapshot
  ].join('\n');
}

function buildScheduleSnapshot() {
  const maxItems = 8;
  const tasks = state.tasks
    .slice(0, maxItems)
    .map((task, idx) => {
      const due = task.due ? new Date(task.due) : null;
      const dueLabel = due ? due.toISOString() : 'none';
      const startLabel = task.start ? new Date(task.start).toISOString() : '';
      const duration = task.estimatedDuration ?? 0;
      return `${idx + 1}. ${task.isCompleted ? '✅' : '⏳'} ${task.title} · due ${dueLabel}${
        startLabel ? ` · start ${startLabel}` : ''
      } · priority ${task.priority ?? 3}${duration ? ` · est ${duration}m` : ''}`;
    })
    .join('\n');

  const assignments = state.assignments
    .slice(0, maxItems)
    .map((assignment, idx) => {
      const due = assignment.due ? new Date(assignment.due).toISOString() : 'none';
      return `${idx + 1}. ${assignment.isCompleted ? '✅' : '📚'} ${assignment.title} · due ${due}${
        assignment.estimatedDuration ? ` · est ${assignment.estimatedDuration}m` : ''
      }`;
    })
    .join('\n');

  const routines = state.routines
    .slice(0, maxItems)
    .map((routine, idx) => `${idx + 1}. ${routine.active !== false ? '🔁' : '⏸️'} ${routine.name}`)
    .join('\n');

  return `[Tasks]\n${tasks || 'None'}\n\n[Assignments]\n${assignments || 'None'}\n\n[Routines]\n${routines || 'None'}`;
}

async function sendOpenAIChat(latestMessage, apiKey) {
  const history = [...state.assistantHistory];
  const limited = history.slice(-12);
  const messages = [{ role: 'system', content: buildSystemPrompt() }, ...limited.map((entry) => ({
    role: entry.role === 'ai' ? 'assistant' : 'user',
    content: entry.content
  }))];

  // Ensure the latest user input is present even if history is out of sync
  if (!limited.length || limited[limited.length - 1].content !== latestMessage) {
    messages.push({ role: 'user', content: latestMessage });
  }

  const payload = {
    model: 'gpt-4o-mini',
    temperature: 0.3,
    messages
  };

  const response = await fetch('https://api.openai.com/v1/chat/completions', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${apiKey}`
    },
    body: JSON.stringify(payload)
  });

  if (!response.ok) {
    const text = await response.text().catch(() => '');
    throw new Error(text || `OpenAI request failed (${response.status})`);
  }

  const data = await response.json();
  const content = data?.choices?.[0]?.message?.content ?? '';
  const { replyText, actions } = extractScheduleActions(content);
  return { replyText, actions };
}

async function applyScheduleActions(actions = []) {
  const summaries = [];
  let touchedTasks = false;
  let touchedAssignments = false;

  for (const action of actions) {
    const type = (action.type || '').toLowerCase();
    if (type === 'todo.add') {
      const title = action.title?.trim();
      if (!title) {
        summaries.push('⚠️ Missing title for todo.add action.');
        continue;
      }
      const due = parseAssistantDate(action.dueDate);
      const start = parseAssistantDate(action.startDate);
      const priority = mapPriorityValue(action.priority);
      const duration = sanitizeDuration(action.durationMinutes);
      await api.createTask({
        title,
        due,
        start,
        priority,
        estimatedDuration: duration ?? undefined,
        hasDeadline: Boolean(due)
      });
      summaries.push(`🆕 Added task "${title}"${due ? ` due ${due.toLocaleString()}` : ''}.`);
      touchedTasks = true;
    } else if (type === 'todo.toggle' || type === 'todo.complete') {
      const identifier = action.identifier || action.title;
      const target = findTaskByIdentifier(identifier);
      if (!target) {
        summaries.push(`⚠️ Could not find task matching "${identifier ?? 'unknown'}".`);
        continue;
      }
      const nextState = !target.isCompleted;
      await api.updateTask({ ...target, isCompleted: nextState });
      summaries.push(`🔄 Marked "${target.title}" as ${nextState ? 'complete' : 'incomplete'}.`);
      touchedTasks = true;
    } else if (
      type === 'assignment.setduration' ||
      type === 'assignment.duration' ||
      type === 'assignment.updateduration'
    ) {
      const identifier = action.identifier || action.title;
      const target = findAssignmentByIdentifier(identifier);
      if (!target) {
        summaries.push(`⚠️ Could not find assignment matching "${identifier ?? 'unknown'}".`);
        continue;
      }
      const duration = sanitizeDuration(action.durationMinutes);
      await api.updateAssignment({ ...target, estimatedDuration: duration ?? 0 });
      summaries.push(
        duration
          ? `⏱️ Set "${target.title}" duration to ${duration}m.`
          : `⏱️ Cleared estimated duration for "${target.title}".`
      );
      touchedAssignments = true;
    }
  }

  if (touchedTasks) {
    await loadTasks();
    await refreshSchedule();
    await refreshInsights();
  }
  if (touchedAssignments) {
    await loadAssignments();
    await refreshSchedule();
    await refreshInsights();
  }

  return summaries;
}

function extractScheduleActions(content = '') {
  const start = content.indexOf('<schedule_actions>');
  const end = content.indexOf('</schedule_actions>');
  if (start === -1 || end === -1 || end <= start) {
    return { replyText: content.trim(), actions: [] };
  }
  const rawJson = content.slice(start + '<schedule_actions>'.length, end).trim();
  const cleanedText = (content.slice(0, start) + content.slice(end + '</schedule_actions>'.length)).trim();
  let envelope = null;
  try {
    envelope = JSON.parse(rawJson);
  } catch (error) {
    // try to recover by wrapping braces if missing
    try {
      envelope = JSON.parse(rawJson.startsWith('{') ? rawJson : `{${rawJson}}`);
    } catch (err) {
      return { replyText: cleanedText || content.trim(), actions: [] };
    }
  }

  const replyText = (envelope.reply ?? cleanedText ?? content).toString().trim();
  const actions = Array.isArray(envelope.actions) ? envelope.actions : [];
  return { replyText, actions };
}

function parseAssistantDate(value) {
  if (!value) return null;
  const trimmed = value.toString().trim();
  const normalized = trimmed.replace(' ', 'T');
  // Capture date/time and ignore any trailing timezone info to keep it local
  const match = normalized.match(
    /^(\d{4})-(\d{2})-(\d{2})(?:T(\d{2}):(\d{2})(?::(\d{2}))?)?/
  );
  if (!match) return null;
  const [, y, m, d, hh = '00', mm = '00', ss = '00'] = match;
  const year = Number(y);
  const month = Number(m) - 1;
  const day = Number(d);
  const hour = Number(hh);
  const minute = Number(mm);
  const second = Number(ss);
  return new Date(year, month, day, hour, minute, second);
}

function mapPriorityValue(value) {
  if (typeof value === 'number') return value;
  if (!value) return 3;
  const lowered = value.toString().toLowerCase();
  if (lowered === 'low') return 2;
  if (lowered === 'high') return 5;
  return 3;
}

function sanitizeDuration(value) {
  if (typeof value === 'number' && Number.isFinite(value) && value > 0) {
    return Math.round(value);
  }
  if (typeof value === 'string') {
    const parsed = Number(value);
    if (Number.isFinite(parsed) && parsed > 0) return Math.round(parsed);
  }
  return null;
}

function findTaskByIdentifier(identifier) {
  if (!identifier) return null;
  const trimmed = identifier.toString().trim().toLowerCase();
  return (
    state.tasks.find((task) => task.id === identifier) ||
    state.tasks.find((task) => task.title?.toLowerCase().includes(trimmed))
  );
}

function findAssignmentByIdentifier(identifier) {
  if (!identifier) return null;
  const trimmed = identifier.toString().trim().toLowerCase();
  return (
    state.assignments.find((assignment) => assignment.id === identifier) ||
    state.assignments.find(
      (assignment) =>
        assignment.title?.toLowerCase().includes(trimmed) || assignment.course?.toLowerCase().includes(trimmed)
    )
  );
}
