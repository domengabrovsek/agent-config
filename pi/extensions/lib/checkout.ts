import { realpathSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

/**
 * Resolve `rel` against the checkout root from a module in pi/extensions/.
 * The extension dir links into the checkout, so the root sits two levels above
 * the module's real path. A path that cannot be resolved is used as given.
 */
export function checkoutPath(moduleUrl: string, rel: string): string {
  const modulePath = fileURLToPath(moduleUrl);
  let moduleDir: string;
  try {
    moduleDir = dirname(realpathSync(modulePath));
  } catch {
    moduleDir = dirname(modulePath);
  }
  return join(moduleDir, '../..', rel);
}
