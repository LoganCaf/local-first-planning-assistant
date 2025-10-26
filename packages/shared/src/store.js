import { readFileSync, writeFileSync, mkdirSync, existsSync } from 'node:fs';
import { dirname, resolve } from 'node:path';

/**
 * Basic JSON-backed store for local development.
 */
export class InMemoryDataStore {
  constructor(filepath = 'data/db.json') {
    this.filepath = resolve(filepath);
    this.state = {
      tasks: [],
      routines: [],
      goals: [],
      preferences: {},
      placements: []
    };
  }

  load() {
    if (!existsSync(this.filepath)) return this.state;
    const content = readFileSync(this.filepath, 'utf-8');
    this.state = JSON.parse(content);
    return this.state;
  }

  save() {
    const dir = dirname(this.filepath);
    if (!existsSync(dir)) {
      mkdirSync(dir, { recursive: true });
    }
    writeFileSync(this.filepath, JSON.stringify(this.state, null, 2));
  }

  upsert(collection, item) {
    if (!this.state[collection]) {
      this.state[collection] = [];
    }
    const list = this.state[collection];
    const index = list.findIndex((entry) => entry.id === item.id);
    if (index >= 0) {
      list[index] = item;
    } else {
      list.push(item);
    }
    this.save();
    return item;
  }

  remove(collection, id) {
    if (!this.state[collection]) return false;
    const list = this.state[collection];
    const index = list.findIndex((entry) => entry.id === id);
    if (index === -1) return false;
    list.splice(index, 1);
    this.save();
    return true;
  }
}
