/**
 * Tests for pi/extensions/statusline/format.ts: token and countdown text,
 * unified usage headers, window colors, and segment layout under width pressure.
 */

import assert from 'node:assert/strict';
import { describe, it } from 'node:test';

import {
  assembleLine,
  buildSegs,
  type ColorToken,
  type FooterStyle,
  formatTokens,
  humanizeReset,
  type LiveFooter,
  parseUnifiedHeaders,
  type TextMeasure,
  usageColorName,
} from '../pi/extensions/statusline/format.ts';

/* Plain text instead of ANSI, so widths are string lengths and colors are visible. */
const theme: FooterStyle = {
  fg: (token: ColorToken, text: string) => `<${token}>${text}`,
  bold: (text: string) => `*${text}*`,
};
const plain: FooterStyle = { fg: (_token, text) => text, bold: (text) => text };
const measure: TextMeasure = {
  visibleWidth: (text) => text.length,
  truncateToWidth: (text, width) => text.slice(0, width),
};

const NOW = 1_700_000_000;
const baseLive: LiveFooter = {
  cwd: '/work/app',
  branch: 'main',
  dirty: false,
  spendParts: ['↑12k', '$0.40'],
  context: { tokens: 145_000, percent: 34.4 },
  nowSec: NOW,
  modelId: 'model-x',
  thinkingLevel: 'high',
};

describe('formatTokens', () => {
  it('compacts counts like the pi footer', () => {
    assert.equal(formatTokens(999), '999');
    assert.equal(formatTokens(1234), '1.2k');
    assert.equal(formatTokens(145_000), '145k');
    assert.equal(formatTokens(2_500_000), '2.5M');
    assert.equal(formatTokens(25_000_000), '25M');
  });
});

describe('humanizeReset', () => {
  it('renders a compact countdown', () => {
    assert.equal(humanizeReset(0), '');
    assert.equal(humanizeReset(30), '<1m');
    assert.equal(humanizeReset(14 * 60), '14m');
    assert.equal(humanizeReset(112 * 60), '1h 52m');
    assert.equal(humanizeReset(51 * 3600), '2d 3h');
  });
});

describe('parseUnifiedHeaders', () => {
  it('reads utilization, reset, and status for both windows', () => {
    const parsed = parseUnifiedHeaders({
      'anthropic-ratelimit-unified-5h-utilization': '0.234',
      'anthropic-ratelimit-unified-5h-reset': '1700003600',
      'anthropic-ratelimit-unified-7d-utilization': '0.71',
      'anthropic-ratelimit-unified-7d-status': 'rate_limited',
    });
    assert.deepEqual(parsed, {
      fiveHour: { pct: 23, resetEpochSec: 1_700_003_600, rejected: false },
      sevenDay: { pct: 71, resetEpochSec: null, rejected: true },
    });
  });

  it('returns undefined without unified headers', () => {
    assert.equal(parseUnifiedHeaders({ 'content-type': 'application/json' }), undefined);
  });
});

describe('usageColorName', () => {
  it('turns yellow at 50% and red at 80% or when binding', () => {
    assert.equal(usageColorName(49, false), 'success');
    assert.equal(usageColorName(50, false), 'warning');
    assert.equal(usageColorName(80, false), 'error');
    assert.equal(usageColorName(10, true), 'error');
  });
});

describe('buildSegs', () => {
  it('orders folder, branch, spend, context, usage, and model', () => {
    const segs = buildSegs(theme, {
      ...baseLive,
      dirty: true,
      windows: {
        provider: 'p',
        fiveHour: { pct: 23, resetEpochSec: NOW + 112 * 60, rejected: false },
        sevenDay: null,
        capturedAt: NOW * 1000,
      },
    });
    assert.deepEqual(segs, [
      { text: '*app*' },
      { text: '<dim>on <error>main*' },
      { text: '<dim>↑12k $0.40', drop: 3 },
      { text: '<accent>context <success>145k (34%)' },
      { text: '<success>5h 23% <dim>(1h 52m)', drop: 2 },
      { text: '<dim>model-x · high', drop: 1 },
    ]);
  });

  it('shows a dash without context data and hides windows older than an hour', () => {
    const segs = buildSegs(plain, {
      ...baseLive,
      context: undefined,
      windows: { provider: 'p', fiveHour: { pct: 5, resetEpochSec: null, rejected: false }, sevenDay: null, capturedAt: (NOW - 3600) * 1000 },
    });
    assert.deepEqual(
      segs.map((s) => s.text),
      ['app', 'on main', '↑12k $0.40', 'context -', 'model-x · high'],
    );
  });
});

describe('assembleLine', () => {
  const segs = buildSegs(plain, baseLive);

  it('joins every segment when the line fits', () => {
    assert.equal(
      assembleLine(segs, { theme: plain, width: 200, measure }),
      'app │ on main │ ↑12k $0.40 │ context 145k (34%) │ model-x · high',
    );
  });

  it('drops the model first, then spend, under width pressure', () => {
    assert.equal(assembleLine(segs, { theme: plain, width: 50, measure }), 'app │ on main │ ↑12k $0.40 │ context 145k (34%)');
    assert.equal(assembleLine(segs, { theme: plain, width: 35, measure }), 'app │ on main │ context 145k (34%)');
  });

  it('truncates once nothing droppable is left', () => {
    assert.equal(assembleLine(segs, { theme: plain, width: 10, measure }), 'app │ on m');
  });
});
