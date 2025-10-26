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
  listTasks() {
    return request('/api/tasks');
  },
  createTask(payload) {
    return request('/api/tasks', {
      method: 'POST',
      body: JSON.stringify(payload)
    });
  },
  deleteTask(id) {
    return request(`/api/tasks?id=${encodeURIComponent(id)}`, { method: 'DELETE' });
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
  }
};
