// Checks the café system prompt is built correctly from the real content/ folder.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { buildSystemPrompt } from '../src/content.js';

test('system prompt contains every document and the safety rules', () => {
  const docs = [
    { name: 'menu.md', text: '# Menu\nIced Spanish Latte ₱170' },
    { name: 'policies.md', text: '# Policies\nShared kitchen' },
  ];
  const prompt = buildSystemPrompt(docs);
  assert.match(prompt, /### Document: menu\.md/);
  assert.match(prompt, /### Document: policies\.md/);
  assert.match(prompt, /₱170/);
  assert.match(prompt, /Never say that any food or drink is safe/);
  assert.match(prompt, /cannot take orders/);
});
