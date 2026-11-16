/**
 * Tests for pi/extensions/lib/checkout.ts: extension modules reach checkout
 * files through the real path of a symlinked extensions dir.
 */

import assert from 'node:assert/strict';
import { mkdirSync, mkdtempSync, realpathSync, rmSync, symlinkSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { after, describe, it } from 'node:test';
import { pathToFileURL } from 'node:url';

import { checkoutPath } from '../pi/extensions/lib/checkout.ts';

describe('checkoutPath', () => {
  const root = realpathSync(mkdtempSync(join(tmpdir(), 'checkout-path-')));
  after(() => rmSync(root, { recursive: true, force: true }));

  it('resolves against the checkout behind a symlinked extensions dir', () => {
    const checkout = join(root, 'repo');
    mkdirSync(join(checkout, 'pi/extensions'), { recursive: true });
    writeFileSync(join(checkout, 'pi/extensions/ext.ts'), '');
    mkdirSync(join(root, 'agent'));
    symlinkSync(join(checkout, 'pi/extensions'), join(root, 'agent/extensions'));

    const linked = pathToFileURL(join(root, 'agent/extensions/ext.ts')).href;
    assert.equal(checkoutPath(linked, 'scripts/x.sh'), join(checkout, 'scripts/x.sh'));
  });

  it('falls back to the given path when the module does not exist', () => {
    const missing = pathToFileURL(join(root, 'gone/pi/extensions/ext.ts')).href;
    assert.equal(checkoutPath(missing, 'settings.json'), join(root, 'gone/settings.json'));
  });
});
