import { readFileSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';
import { spawnSync } from 'node:child_process';

function loadConfig(customPath) {
  const locations = [customPath, resolve('config/local-llm.json')].filter(Boolean);
  for (const location of locations) {
    try {
      if (location && existsSync(location)) {
        const raw = readFileSync(location, 'utf-8');
        return JSON.parse(raw);
      }
    } catch (error) {
      console.warn(`Failed to load LLM config from ${location}:`, error.message);
    }
  }
  return {};
}

function buildPrompt(message, history = [], systemPrompt) {
  const promptParts = [];
  const system = systemPrompt ?? 'You are a helpful scheduling assistant.';
  promptParts.push(`System: ${system}`);

  for (const entry of history.slice(-6)) {
    promptParts.push(`${entry.role === 'user' ? 'User' : 'Assistant'}: ${entry.content}`);
  }
  promptParts.push(`User: ${message}`);
  promptParts.push('Assistant:');
  return promptParts.join('\n');
}

export class LocalAssistant {
  constructor(options = {}) {
    const config = loadConfig(options.configPath);
    this.modelPath = resolve(options.modelPath ?? config.modelPath ?? './model.gguf');
    this.binaryPath = resolve(options.binaryPath ?? config.binaryPath ?? './llama-cli');
    this.maxTokens = options.maxTokens ?? config.maxTokens ?? 192;
    this.temperature = options.temperature ?? config.temperature ?? 0.7;
    this.topP = options.topP ?? config.topP ?? 0.9;
    this.systemPrompt = options.systemPrompt ?? config.systemPrompt;
  }

  async generateReply({ message, history = [] }) {
    if (!message?.trim()) {
      return {
        content: 'Please provide a prompt for me to respond to.'
      };
    }

    if (!existsSync(this.modelPath) || !existsSync(this.binaryPath)) {
      return this.fallbackResponse(message);
    }

    const prompt = buildPrompt(message, history, this.systemPrompt);
    const args = [
      '--model',
      this.modelPath,
      '--prompt',
      prompt,
      '--n-predict',
      String(this.maxTokens),
      '--temp',
      String(this.temperature),
      '--top-p',
      String(this.topP),
      '--no-display-prompt',
      '--simple-io'
    ];

    const result = spawnSync(this.binaryPath, args, {
      encoding: 'utf-8',
      maxBuffer: 1024 * 1024 * 4
    });

    if (result.error || result.status !== 0) {
      console.warn('Local model execution failed:', result.error ?? result.stderr);
      return this.fallbackResponse(message);
    }

    const cleaned = sanitizeOutput(result.stdout ?? '');
    if (!cleaned) {
      return this.fallbackResponse(message);
    }

    return { content: cleaned };
  }

  fallbackResponse(message) {
    const templates = [
      "I don't have the local model ready, but I suggest blocking at least 30 minutes to work on it.",
      'Consider slotting this into your next focus block. Let me know if you need help scheduling it.',
      'Until the local model is configured, use the task form to capture this and regenerate your schedule.'
    ];
    const index = Math.abs(hashCode(message)) % templates.length;
    return { content: templates[index] };
  }
}

function sanitizeOutput(raw) {
  if (!raw) return '';
  const lines = raw
    .replace(/\r/g, '')
    .split('\n')
    .filter((line) => !line.startsWith('> EOF'));
  return lines.join('\n').trim();
}

export class MockAssistant {
  constructor(response = 'Acknowledged. I will adjust your plan accordingly.') {
    this.response = response;
  }

  async generateReply({ message }) {
    return { content: `${this.response} (${message})` };
  }
}

function hashCode(input) {
  let hash = 0;
  for (let i = 0; i < input.length; i += 1) {
    hash = (hash << 5) - hash + input.charCodeAt(i);
    hash |= 0;
  }
  return hash;
}

export function buildPromptPreview(message, history, systemPrompt) {
  return buildPrompt(message, history, systemPrompt);
}
