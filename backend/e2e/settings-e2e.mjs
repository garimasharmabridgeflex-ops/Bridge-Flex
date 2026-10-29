// End-to-end exercise of EVERY admin-console Settings action in a real browser.
//
// Quickest path: `make e2e` (backend/) — e2e/run.sh starts everything below
// that isn't already running, then tears down what it started.
//
// Prerequisites when running by hand (see backend/README.md):
//   1. Auth/Firestore/Storage/PubSub emulators running (firebase emulators:start)
//   2. Seeded data (npm run seed) — signs in as admin@example.com / password123
//   3. Local functions-core processes for the settings endpoints
//      (services/core/run-local.sh, with the emulator env vars exported)
//   4. `node proxy.mjs` (this folder) — serves the console and proxies
//      /<EndpointName> to those local processes
//   5. `npm install` in this folder (puppeteer-core, uses system Chrome)
//
// Each action is verified twice: the success toast the admin actually sees,
// and a full page reload followed by re-reading the value from the rendered
// Settings tab — i.e. the value really persisted through the API + Firestore,
// not just that the request didn't visibly explode.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import puppeteer from 'puppeteer-core';

const BASE = process.env.BASE_URL || 'http://127.0.0.1:5050';
const CHROME = process.env.CHROME || '/usr/bin/google-chrome';
const EMAIL = 'admin@example.com';
const PASSWORD = 'password123';

const results = [];
const record = (name, ok, detail = '') => {
  results.push({ name, ok, detail });
  console.log(`${ok ? 'PASS' : 'FAIL'}  ${name}${detail ? ' — ' + detail : ''}`);
};

let page;
const netErrors = [];
const pageErrors = [];

const fail = (name, detail) => record(name, false, detail);

// ── helpers ────────────────────────────────────────────────────────────────

async function toastTexts() {
  return page.$$eval('.toast-msg', els => els.map(e => (e.textContent || '').trim()));
}

/** Wait until any toast contains `needle`. Returns the matching text, or throws. */
async function expectToast(needle, timeout = 9000) {
  try {
    await page.waitForFunction(
      (t) => [...document.querySelectorAll('.toast-msg')]
        .some(e => (e.textContent || '').includes(t)),
      { timeout },
      needle,
    );
  } catch (err) {
    const seen = await toastTexts();
    throw new Error(`no toast containing "${needle}" (saw: ${JSON.stringify(seen)})`);
  }
  const texts = await toastTexts();
  return texts.find(t => t.includes(needle));
}

async function openSettings() {
  await page.waitForSelector('#app-view', { visible: true, timeout: 20000 });
  await page.click('.nav-item[data-tab="settings"]');
  try {
    await page.waitForFunction(() => {
      const el = document.querySelector('#tab-settings');
      return !!el && (el.textContent.includes('Feature gates') || !!el.querySelector('.empty'));
    }, { timeout: 20000 });
  } catch (e) {
    throw new Error('Settings tab did not render within 20s (no panels, no error box)');
  }
  // A failed GET inside renderSettings repaints the whole tab as
  // <div class="panel"><div class="empty">error</div></div> — treat that as a
  // hard failure, never silently continue. Deliberately NOT a bare '.empty'
  // match: tables legitimately render empty states as <td class="empty">
  // ("No policies yet…", "No audit entries yet") when a fetch succeeded with
  // zero rows, and those must not be mistaken for a failed load.
  const err = await page.$('#tab-settings .panel > .empty');
  if (err) {
    const msg = await page.$eval('#tab-settings .panel > .empty', e => e.textContent);
    throw new Error(`settings panel failed to load: ${msg}`);
  }
}

async function reloadToSettings() {
  await page.reload({ waitUntil: 'domcontentloaded' });
  await openSettings();
}

/** Set an input/textarea value AND fire an input event so the console's
 *  data-dirty guard sees the edit (silent refresh must not clobber it). */
async function setField(selector, value) {
  const ok = await page.evaluate((sel, val) => {
    const el = document.querySelector(sel);
    if (!el) return false;
    el.value = val;
    el.dispatchEvent(new Event('input', { bubbles: true }));
    el.dispatchEvent(new Event('change', { bubbles: true }));
    return true;
  }, selector, String(value));
  if (!ok) throw new Error(`field not found: ${selector}`);
}

async function field(selector) {
  return page.$eval(selector, el => el.value);
}

/** Type into an input after clearing whatever value it was pre-filled with.
 *  The plan modal pre-fills "0.00" / "0", and page.type into a pre-filled
 *  field prepends instead of replacing ("7" into "0" → "70", "19.99" into
 *  "0.00" → garbage), so the cleared-then-typed value is the only reliable
 *  way to fill these. Fires an input event on the clear so the console's
 *  data-dirty guard sees the edit. */
async function typeInto(selector, text) {
  const ok = await page.evaluate((sel) => {
    const el = document.querySelector(sel);
    if (!el) return false;
    el.focus();
    el.value = '';
    el.dispatchEvent(new Event('input', { bubbles: true }));
    return true;
  }, selector);
  if (!ok) throw new Error(`field not found: ${selector}`);
  await page.type(selector, text);
}

/** Wait until a settings table row containing `text` exists, then return it.
 *  Tables fetched outside renderSettings' Promise.all (discount codes) land
 *  after the panels render, so an immediate rowText query races the fetch. */
async function waitForRow(text, timeout = 8000) {
  try {
    await page.waitForFunction(
      (t) => [...document.querySelectorAll('#tab-settings tr')]
        .some(r => (r.textContent || '').includes(t)),
      { timeout }, text,
    );
  } catch {
    throw new Error(`row "${text}" never appeared within ${timeout}ms`);
  }
  return rowText(text);
}

/** Version number from a Rate card panel note like "Version 3 · active". */
const rateCardVersion = (note) => Number((note.match(/Version (\d+)/) || [])[1] || 0);

async function numField(selector) {
  return Number(await field(selector));
}

/** Click the first VISIBLE <button> whose text contains `text`. Visible-only
 *  so a hidden button from another tab (still in the DOM) can't win. */
async function clickButton(text) {
  const ok = await page.evaluate((t) => {
    const btn = [...document.querySelectorAll('button')]
      .filter(b => b.offsetParent !== null)
      .find(b => (b.textContent || '').toLowerCase().includes(t.toLowerCase()));
    if (!btn) return false;
    btn.click();
    return true;
  }, text);
  if (!ok) throw new Error(`button not found: "${text}"`);
}

/** Click a button inside the table row containing `row`. */
async function clickRowButton(row, buttonText) {
  const ok = await page.evaluate((rowText, btnText) => {
    const tr = [...document.querySelectorAll('#tab-settings tr')]
      .find(r => (r.textContent || '').includes(rowText));
    if (!tr) return false;
    const btn = [...tr.querySelectorAll('button')]
      .find(b => (b.textContent || '').toLowerCase().includes(btnText.toLowerCase()));
    if (!btn) return false;
    btn.click();
    return true;
  }, row, buttonText);
  if (!ok) throw new Error(`row "${row}" / button "${buttonText}" not found`);
}

const rowText = (row) => page.evaluate((r) => {
  const tr = [...document.querySelectorAll('#tab-settings tr')]
    .find(x => (x.textContent || '').includes(r));
  return tr ? tr.textContent.replace(/\s+/g, ' ').trim() : null;
}, row);

/** Text of the <p> in the panel whose heading contains `title`. */
async function panelNote(title) {
  return page.evaluate((t) => {
    const head = [...document.querySelectorAll('#tab-settings .panel-head')]
      .find(h => (h.querySelector('h3')?.textContent || '').includes(t));
    return head ? (head.querySelector('p')?.textContent || '') : '';
  }, title);
}

/** Every step's own try/catch so one broken action doesn't hide the rest. */
async function step(name, fn) {
  try {
    const detail = await fn();
    record(name, true, typeof detail === 'string' ? detail : '');
  } catch (err) {
    fail(name, err.message);
  }
}

// ── the run ────────────────────────────────────────────────────────────────

async function main() {
  const browser = await puppeteer.launch({
    executablePath: CHROME,
    headless: 'new',
    args: ['--no-sandbox', '--disable-dev-shm-usage', '--window-size=1440,2200'],
    defaultViewport: { width: 1440, height: 2200 },
  });
  page = await browser.newPage();
  page.on('pageerror', e => pageErrors.push(String(e)));
  page.on('response', r => {
    const u = r.url();
    if (r.status() >= 400 && !u.includes('favicon')) netErrors.push(`${r.status()} ${r.request().method()} ${u}`);
  });

  try {
    // 1 ─ sign in ---------------------------------------------------------
    await page.goto(`${BASE}/admin`, { waitUntil: 'domcontentloaded' });
    await page.waitForSelector('#admin-email', { visible: true });
    await page.type('#admin-email', EMAIL);
    await page.type('#admin-password', PASSWORD);
    await page.click('#btn-login');
    await step('sign in as admin', async () => {
      await page.waitForSelector('#app-view', { visible: true, timeout: 20000 });
      return 'admin@example.com';
    });
    if (!results.at(-1)?.ok) throw new Error('cannot continue without sign-in');

    // 2 ─ Settings tab loads ---------------------------------------------
    await step('Settings tab loads all panels', () => openSettings());
    if (!results.at(-1)?.ok) throw new Error('cannot continue without Settings');

    // 3 ─ Feature gates ---------------------------------------------------
    await step('feature gate save persists', async () => {
      const current = await field('select[data-flag="nurseryApprovalRequired"]');
      const next = current === 'enforce' ? 'warn' : 'enforce';
      await page.select('select[data-flag="nurseryApprovalRequired"]', next);
      await clickButton('Save gates');
      await expectToast('Feature gates saved');
      await reloadToSettings();
      const after = await field('select[data-flag="nurseryApprovalRequired"]');
      if (after !== next) throw new Error(`expected ${next}, page shows ${after}`);
      return `${current} → ${next} (survived reload)`;
    });

    // 4 ─ Plans -----------------------------------------------------------
    await step('plan create persists', async () => {
      await clickButton('New plan');
      await page.waitForSelector('#plan-id', { visible: true });
      await typeInto('#plan-id', 'e2e-plan');
      await typeInto('#plan-name', 'E2E Plan');
      await typeInto('#plan-description', 'Created by the browser e2e run');
      await typeInto('#plan-price', '19.99');
      await typeInto('#plan-trial', '7');
      await clickButton('Save plan');
      await expectToast('Plan saved');
      await reloadToSettings();
      const row = await rowText('E2E Plan');
      if (!row) throw new Error('E2E Plan row missing after reload');
      if (!row.includes('19.99')) throw new Error(`row lacks price: ${row}`);
      return row.slice(0, 90);
    });

    // 5 ─ Rate card -------------------------------------------------------
    await step('rate card version publish persists', async () => {
      await setField('[data-pay="none"]', '13.00');
      await setField('[data-charge="none"]', '16.75');
      await clickButton('Publish new rate card version');
      await expectToast('New rate card version published');
      await reloadToSettings();
      const pay = await numField('[data-pay="none"]');
      const charge = await numField('[data-charge="none"]');
      if (Math.abs(pay - 13) > 0.001) throw new Error(`pay reverted to ${pay}`);
      if (Math.abs(charge - 16.75) > 0.001) throw new Error(`charge reverted to ${charge}`);
      const first = rateCardVersion(await panelNote('Rate card'));
      if (first < 1) throw new Error(`no active rate card shown after save`);
      // Publishing again must mint the next version (the panel promises
      // "Saving creates a new version"). The first publish on a fresh
      // project also lands on v1 because the pre-save panel shows the
      // *virtual* DefaultRateCard (v1, never stored in rateCards), so only a
      // second consecutive publish can prove the version actually advances.
      await setField('[data-pay="none"]', '13.25');
      await clickButton('Publish new rate card version');
      await expectToast('New rate card version published');
      await reloadToSettings();
      const pay2 = await numField('[data-pay="none"]');
      if (Math.abs(pay2 - 13.25) > 0.001) throw new Error(`second publish reverted to ${pay2}`);
      const second = rateCardVersion(await panelNote('Rate card'));
      if (second !== first + 1) {
        throw new Error(`version did not advance: ${first} → ${second}`);
      }
      return `v${first} → v${second}, unqualified pay £${pay2.toFixed(2)}/h`;
    });

    // 6 ─ Company details -------------------------------------------------
    await step('company details save persists', async () => {
      await setField('[data-company="companyName"]', 'E2E Nurseries Ltd');
      await clickButton('Save company');
      await expectToast('Company details saved');
      await reloadToSettings();
      const v = await field('[data-company="companyName"]');
      if (v !== 'E2E Nurseries Ltd') throw new Error(`reverted to "${v}"`);
      return 'companyName survived reload';
    });

    // 7 ─ Cancellation policy --------------------------------------------
    await step('cancellation policy save persists', async () => {
      await setField('#cancel-notice', '36');
      await setField('#cancel-fee', '25.50');
      await setField('#cancel-notes', 'E2E cancellation note');
      // Publish the policy before asserting the fee: LoadCancellationPolicy
      // deliberately zeroes nurseryFeePence while published=false (a fee that
      // was never published must never be shown or charged), so an unpublished
      // fee can't survive a reload by design.
      const wasChecked = await page.$eval('#cancel-published', el => el.checked);
      if (!wasChecked) await page.click('#cancel-published');
      await clickButton('Save policy');
      await expectToast('Cancellation policy saved');
      await reloadToSettings();
      const notice = await numField('#cancel-notice');
      const fee = await numField('#cancel-fee');
      const notes = await field('#cancel-notes');
      const published = await page.$eval('#cancel-published', el => el.checked);
      if (notice !== 36) throw new Error(`noticeHours reverted to ${notice}`);
      if (Math.abs(fee - 25.5) > 0.001) throw new Error(`fee reverted to ${fee}`);
      if (!notes.includes('E2E cancellation note')) throw new Error(`notes reverted to "${notes}"`);
      if (!published) throw new Error('published checkbox reverted to unchecked');
      return '36h notice / £25.50 fee / published — all survived reload';
    });

    // 8 ─ Legal policies: draft → approve → publish ------------------------
    await step('policy draft → approve → publish', async () => {
      await clickButton('New draft');
      await page.waitForSelector('#policy-title', { visible: true });
      await page.select('#policy-type', 'privacy');
      await page.type('#policy-title', 'E2E Privacy Policy');
      await page.type('#policy-summary', 'End-to-end privacy policy');
      await page.type('#policy-content', 'Full policy text written by the e2e run.');
      await clickButton('Save draft');
      await expectToast('Draft saved');
      await reloadToSettings();

      const draftRow = await rowText('E2E Privacy Policy');
      if (!draftRow) throw new Error('draft row missing after reload');
      if (!draftRow.toLowerCase().includes('draft')) throw new Error(`not a draft: ${draftRow}`);

      await clickRowButton('E2E Privacy Policy', 'Approve');
      await expectToast('Policy approved');
      await reloadToSettings();
      const approvedRow = await rowText('E2E Privacy Policy');
      if (!approvedRow || !approvedRow.toLowerCase().includes('approved')) {
        throw new Error(`not approved after reload: ${approvedRow}`);
      }

      await clickRowButton('E2E Privacy Policy', 'Publish');
      await expectToast('Policy published');
      await reloadToSettings();
      const publishedRow = await rowText('E2E Privacy Policy');
      if (!publishedRow || !publishedRow.toLowerCase().includes('published')) {
        throw new Error(`not published after reload: ${publishedRow}`);
      }
      return publishedRow.slice(0, 90);
    });

    // 9 ─ Discount codes ---------------------------------------------------
    await step('discount code create + toggle persists', async () => {
      // Unique per run: CreateDiscountCode deliberately fails loudly on an
      // existing code ("Create, not Set"), so re-running against a live
      // emulator must not collide with the previous run's code.
      const code = 'E2E' + Date.now().toString(36).toUpperCase().slice(-6);
      await clickButton('New code');
      await page.waitForSelector('#dc-code', { visible: true });
      await typeInto('#dc-code', code);
      await typeInto('#dc-percent', '10');
      await clickButton('Create');
      await expectToast(`Discount code ${code} created`);
      await reloadToSettings();
      const row = await waitForRow(code);
      if (!row) throw new Error(`${code} row missing after reload`);
      if (!row.includes('10%')) throw new Error(`row lacks 10% off: ${row}`);

      await clickRowButton(code, 'Deactivate');
      await expectToast(`${code} deactivated`);
      await reloadToSettings();
      const off = await waitForRow(code);
      if (!off || !off.includes('inactive')) throw new Error(`not inactive: ${off}`);

      await clickRowButton(code, 'Activate');
      await expectToast(`${code} activated`);
      await reloadToSettings();
      const on = await waitForRow(code);
      if (!on || on.includes('inactive')) throw new Error(`not active again: ${on}`);
      return 'created → deactivated → activated, all after reloads';
    });

    // 10 ─ Broadcast notification ------------------------------------------
    await step('admin notification sends', async () => {
      await page.type('#notify-title', 'E2E test notice');
      await page.type('#notify-body', 'Written by the browser end-to-end run.');
      await clickButton('Send notification');
      const toast = await expectToast('Notification sent to');
      const count = Number((toast.match(/sent to (\d+) account/) || [])[1] || 0);
      if (count < 1) throw new Error(`sent count was ${count}: ${toast}`);
      return `${count} account(s) notified`;
    });

    // 11 ─ whole-run hygiene ------------------------------------------------
    await step('no failed API calls during the run', async () => {
      if (netErrors.length) throw new Error(netErrors.slice(0, 8).join(' | '));
    });
    await step('no uncaught page errors during the run', async () => {
      if (pageErrors.length) throw new Error(pageErrors.slice(0, 8).join(' | '));
    });
  } finally {
    await browser.close();
    const passed = results.filter(r => r.ok).length;
    const report = {
      when: new Date().toISOString(),
      passed,
      failed: results.length - passed,
      results,
      netErrors,
      pageErrors,
    };
    const here = path.dirname(fileURLToPath(import.meta.url));
    fs.writeFileSync(path.join(here, 'last-run.json'), JSON.stringify(report, null, 2));
    console.log(`\n${passed}/${results.length} checks passed — report: backend/e2e/last-run.json`);
    if (netErrors.length) console.log('failed HTTP calls:\n  ' + netErrors.join('\n  '));
    if (pageErrors.length) console.log('page errors:\n  ' + pageErrors.join('\n  '));
  }

  if (results.some(r => !r.ok)) process.exit(1);
}

main().catch(err => {
  console.error('E2E harness crashed:', err);
  process.exit(2);
});
