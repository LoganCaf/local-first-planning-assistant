const now = new Date();

export const state = {
  tasks: [],
  taskSegments: [],
  routines: [],
  assignments: [],
  assignmentSegments: [],
  assignmentSync: null,
  schedule: [],
  unscheduled: [],
  insights: null,
  connection: 'checking',
  assistantHistory: [],
  assistantPending: false,
  activeTab: 'calendar',
  taskFilter: 'all',
  selectedDate: now,
  calendarMonth: new Date(now.getFullYear(), now.getMonth(), 1)
};

const listeners = new Set();

export function subscribe(callback) {
  listeners.add(callback);
  try {
    callback({ ...state });
  } catch (error) {
    console.error('Subscriber error during initial render', error);
  }
  return () => listeners.delete(callback);
}

export function setState(patch) {
  Object.assign(state, patch);
  listeners.forEach((listener) => {
    try {
      listener(state);
    } catch (error) {
      console.error('Subscriber error', error);
    }
  });
}
