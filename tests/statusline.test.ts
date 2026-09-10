import assert from 'node:assert/strict';
import { Buffer } from 'node:buffer';
import { describe, it } from 'node:test';

import {
  extractOpenAIAccountId,
  parseCodexHeaders,
  parseCodexUsagePayload,
} from '../pi/extensions/statusline/usage.ts';

function jwtWithPayload(payload: object): string {
  return `header.${Buffer.from(JSON.stringify(payload)).toString('base64url')}.signature`;
}

describe('parseCodexUsagePayload', () => {
  it('maps primary and secondary windows to the footer usage windows', () => {
    const result = parseCodexUsagePayload({
      plan_type: 'plus',
      rate_limit: {
        allowed: true,
        limit_reached: false,
        primary_window: {
          used_percent: 42.4,
          limit_window_seconds: 18_000,
          reset_at: 1_735_693_200,
        },
        secondary_window: {
          used_percent: 81,
          limit_window_seconds: 604_800,
          reset_at: 1_736_298_000,
        },
      },
    });

    assert.deepEqual(result, {
      fiveHour: { pct: 42, resetEpochSec: 1_735_693_200, rejected: false, label: '5h' },
      sevenDay: { pct: 81, resetEpochSec: 1_736_298_000, rejected: false, label: '7d' },
    });
  });

  it('uses the reported duration even when only the primary window is returned', () => {
    const result = parseCodexUsagePayload({
      rate_limit: {
        allowed: true,
        limit_reached: false,
        primary_window: {
          used_percent: 11,
          limit_window_seconds: 604_800,
          reset_at: 1_736_298_000,
        },
      },
    });

    assert.equal(result?.fiveHour?.label, '7d');
    assert.equal(result?.sevenDay, null);
  });

  it('marks returned windows as rejected when the account limit is reached', () => {
    const result = parseCodexUsagePayload({
      rate_limit: {
        allowed: false,
        limit_reached: true,
        primary_window: { used_percent: 100, reset_at: 1_735_693_200 },
      },
    });

    assert.equal(result?.fiveHour?.rejected, true);
    assert.equal(result?.sevenDay, null);
  });

  it('ignores malformed and empty account payloads', () => {
    assert.equal(parseCodexUsagePayload(null), undefined);
    assert.equal(parseCodexUsagePayload({ rate_limit: { primary_window: { used_percent: '42' } } }), undefined);
  });
});

describe('parseCodexHeaders', () => {
  it('keeps weekly primary usage and its reset under the reported duration label', () => {
    const result = parseCodexHeaders({
      'x-codex-primary-used-percent': '11',
      'x-codex-primary-window-minutes': '10080',
      'x-codex-primary-reset-at': '1736298000',
      'x-codex-secondary-used-percent': '0',
      'x-codex-secondary-window-minutes': '300',
    });

    assert.deepEqual(result, {
      fiveHour: { pct: 11, resetEpochSec: 1_736_298_000, rejected: false, label: '7d' },
      sevenDay: { pct: 0, resetEpochSec: null, rejected: false, label: '5h' },
    });
  });

  it('preserves endpoint labels when equivalent response headers replace the snapshot', () => {
    const payload = parseCodexUsagePayload({
      rate_limit: {
        primary_window: { used_percent: 11, limit_window_seconds: 604_800, reset_at: 1_736_298_000 },
      },
    });
    const headers = parseCodexHeaders({
      'x-codex-primary-used-percent': '11',
      'x-codex-primary-window-minutes': '10080',
      'x-codex-primary-reset-at': '1736298000000',
    });

    assert.deepEqual(headers, payload);
  });

  it('labels standard and nonstandard durations without changing percentages', () => {
    const result = parseCodexHeaders({
      'x-codex-primary-used-percent': '42.4',
      'x-codex-primary-window-minutes': '300',
      'x-codex-secondary-used-percent': '81',
      'x-codex-secondary-window-minutes': '60',
    });

    assert.equal(result?.fiveHour?.label, '5h');
    assert.equal(result?.fiveHour?.pct, 42);
    assert.equal(result?.sevenDay?.label, '1h');
    assert.equal(result?.sevenDay?.pct, 81);
  });

  it('leaves missing or invalid durations unlabeled and absent windows null', () => {
    for (const duration of [undefined, '', 'invalid', '0', '-1', 'Infinity']) {
      const headers: Record<string, string> = { 'x-codex-primary-used-percent': '11' };
      if (duration !== undefined) headers['x-codex-primary-window-minutes'] = duration;
      const result = parseCodexHeaders(headers);

      assert.equal(result?.fiveHour?.label, undefined);
      assert.equal(result?.fiveHour?.pct, 11);
      assert.equal(result?.sevenDay, null);
    }
    assert.equal(parseCodexHeaders({}), undefined);
    assert.equal(parseCodexHeaders({ 'x-codex-primary-window-minutes': '10080' }), undefined);
  });
});

describe('extractOpenAIAccountId', () => {
  it('reads the account id from the OpenAI auth claim', () => {
    const token = jwtWithPayload({
      'https://api.openai.com/auth': { chatgpt_account_id: 'account-123' },
    });

    assert.equal(extractOpenAIAccountId(token), 'account-123');
  });

  it('rejects malformed tokens and missing claims', () => {
    assert.equal(extractOpenAIAccountId('not-a-jwt'), undefined);
    assert.equal(extractOpenAIAccountId(jwtWithPayload({ sub: 'user-123' })), undefined);
  });
});
