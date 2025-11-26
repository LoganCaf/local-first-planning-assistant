const API_BASE = localStorage.getItem('llm_api_base') ?? 'http://localhost:4000';

export function setApiBase(url) {
  localStorage.setItem('llm_api_base', url);
}

async function request(path, options = {}) {
  const response = await fetch(`${API_BASE}${path}`, {
    headers: { 'Content-Type': 'application/json', ...(options.headers ?? {}) },
    ...options
  });
  if (!response.ok) {
    const text = await response.text();
    throw new Error(text || 'Request failed');
  }
  return response.json();
}

export const api = {
  async health() {
    const response = await fetch(`${API_BASE}/health`).catch(() => null);
    if (!response || !response.ok) return null;
    return response.json();
  },
  listTaskSegments(taskId) {
    const query = taskId ? `?taskId=${encodeURIComponent(taskId)}` : '';
    return request(`/api/task-segments${query}`);
  },
  createTaskSegment(payload) {
    return request('/api/task-segments', {
      method: 'POST',
      body: JSON.stringify(payload)
    });
  },
  updateTaskSegment(payload) {
    return request('/api/task-segments', {
      method: 'PUT',
      body: JSON.stringify(payload)
    });
  },
  deleteTaskSegment(id) {
    return request(`/api/task-segments?id=${encodeURIComponent(id)}`, { method: 'DELETE' });
  },
  updateTaskSegmentTimer(id, action) {
    return request('/api/task-segment-timer', {
      method: 'POST',
      body: JSON.stringify({ id, action })
    });
  },
  listTasks() {
    return request('/api/tasks');
  },
  createTask(payload) {
    return request('/api/tasks', {
      method: 'POST',
      body: JSON.stringify(payload)
    });
  },
  updateTask(payload) {
    return request('/api/tasks', {
      method: 'PUT',
      body: JSON.stringify(payload)
    });
  },
  deleteTask(id) {
    return request(`/api/tasks?id=${encodeURIComponent(id)}`, { method: 'DELETE' });
  },
  updateTaskTimer(id, action) {
    return request('/api/tasks/timer', {
      method: 'POST',
      body: JSON.stringify({ id, action })
    });
  },
  listRoutines() {
    return request('/api/routines');
  },
  createRoutine(payload) {
    return request('/api/routines', {
      method: 'POST',
      body: JSON.stringify(payload)
    });
  },
  updateRoutine(payload) {
    return request('/api/routines', {
      method: 'PUT',
      body: JSON.stringify(payload)
    });
  },
  deleteRoutine(id) {
    return request(`/api/routines?id=${encodeURIComponent(id)}`, { method: 'DELETE' });
  },
  generateSchedule(options = {}) {
    return request('/api/schedule', {
      method: 'POST',
      body: JSON.stringify(options)
    });
  },
  weeklyReport(startDate) {
    const query = startDate ? `?start=${encodeURIComponent(startDate.toISOString())}` : '';
    return request(`/api/analytics/weekly${query}`);
  },
  sendAssistantMessage(message, history = []) {
    return request('/api/assistant', {
      method: 'POST',
      body: JSON.stringify({ message, history })
    });
  },
  listAssignments() {
    return request('/api/assignments');
  },
  importAssignments(icsText, sourceName = 'Canvas ICS', sourceURL) {
    return request('/api/assignments/import', {
      method: 'POST',
      body: JSON.stringify({ icsText, sourceName, sourceURL })
    });
  },
  syncAssignments() {
    return request('/api/assignments/sync', { method: 'POST' });
  },
  updateAssignment(payload) {
    return request('/api/assignments', {
      method: 'PUT',
      body: JSON.stringify(payload)
    });
  },
  listAssignmentSegments(assignmentId) {
    const query = assignmentId ? `?assignmentId=${encodeURIComponent(assignmentId)}` : '';
    return request(`/api/assignment-segments${query}`);
  },
  createAssignmentSegment(payload) {
    return request('/api/assignment-segments', {
      method: 'POST',
      body: JSON.stringify(payload)
    });
  },
  updateAssignmentSegment(payload) {
    return request('/api/assignment-segments', {
      method: 'PUT',
      body: JSON.stringify(payload)
    });
  },
  deleteAssignmentSegment(id) {
    return request(`/api/assignment-segments?id=${encodeURIComponent(id)}`, { method: 'DELETE' });
  },
  updateAssignmentTimer(id, action) {
    return request('/api/assignment-timer', {
      method: 'POST',
      body: JSON.stringify({ id, action })
    });
  },
  updateAssignmentSegmentTimer(id, action) {
    return request('/api/assignment-segment-timer', {
      method: 'POST',
      body: JSON.stringify({ id, action })
    });
  }
};
